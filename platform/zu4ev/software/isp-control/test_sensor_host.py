import pathlib,subprocess,tempfile,struct,sys,fcntl,time,signal
exe=pathlib.Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory() as d:
 p=pathlib.Path(d)/'gpio'; lock=pathlib.Path(d)/'lock'
 original=bytearray(4096)
 struct.pack_into('<I',original,0x2c4,0xa5a50000)
 struct.pack_into('<I',original,0x2c8,0x5a5a0000)
 struct.pack_into('<I',original,0x6c,3)
 p.write_bytes(original)
 def run(*args,ok=False):
  r=subprocess.run([str(exe),'--base','0','--dev',str(p),'--lock',str(lock),'--delay-us','10',*args],capture_output=True,text=True,timeout=3)
  assert (r.returncode==0)==ok,(args,r.stdout,r.stderr)
  return r
 for args in [('write','0x10000','0'),('write','0','256'),('read','65535','2'),('read','0','0'),('read','-1'),('write','0','1','extra')]:
  run(*args);assert p.read_bytes()==original
 r=run('read','0x3107');assert 'NACK' in r.stderr
 after=p.read_bytes();assert struct.unpack_from('<I',after,0x2c4)[0]==0xa5a50000;assert struct.unpack_from('<I',after,0x2c8)[0]==0x5a5a0000
 assert struct.unpack_from('<I',after,0x18)[0]==0xfffc0000
 # Clock held low must fail in bounded time and restore owned bits.
 struct.pack_into('<I',original,0x6c,2);p.write_bytes(original)
 r=run('read','0x3107');assert 'bus not idle' in r.stderr
 with open(lock,'w') as f:
  fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB);before=p.read_bytes();r=run('write','0','0');assert 'lock busy' in r.stderr;assert p.read_bytes()==before
print('PASS sensor validation, NACK, idle failure, GPIO bit preservation, lock exclusion')

# Resident lifecycle: one lock/mapping, malformed commands do not hit the bus,
# failures latch unknown state, EOF and SIGTERM both restore GPIO ownership.
with tempfile.TemporaryDirectory() as d:
 p=pathlib.Path(d)/'gpio';lock=pathlib.Path(d)/'lock'
 original=bytearray(4096)
 struct.pack_into('<I',original,0x2c4,0xa5a50000)
 struct.pack_into('<I',original,0x2c8,0x5a5a0000)
 struct.pack_into('<I',original,0x6c,3)
 p.write_bytes(original)
 argv=[str(exe),'--base','0','--dev',str(p),'--lock',str(lock),'--delay-us','10','serve']
 for sig in (False,True):
  p.write_bytes(original)
  proc=subprocess.Popen(argv,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
  assert proc.stdout.readline().startswith('ready protocol=1')
  with open(lock,'w') as f:
   try: fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)
   except BlockingIOError: pass
   else: raise AssertionError('resident did not retain lock')
  before=p.read_bytes()
  proc.stdin.write('exposure -1\nexposure 0x10000\nexposure 12 extra\n'+'x'*200+'\n');proc.stdin.flush()
  for _ in range(4): assert proc.stdout.readline().startswith('error')
  assert p.read_bytes()==before
  proc.stdin.write('exposure 0x1000\nexposure 0x1000\n');proc.stdin.flush()
  assert proc.stdout.readline().startswith('io-failed-state-unknown')
  before=p.read_bytes()
  assert proc.stdout.readline().startswith('state-unknown-restart-required')
  assert p.read_bytes()==before
  if sig: proc.send_signal(signal.SIGTERM)
  else: proc.stdin.close()
  proc.wait(timeout=3);assert proc.returncode==0,proc.stderr.read()
  after=p.read_bytes()
  assert struct.unpack_from('<I',after,0x2c4)[0]==0xa5a50000
  assert struct.unpack_from('<I',after,0x2c8)[0]==0x5a5a0000
  with open(lock,'w') as f: fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)
print('PASS resident protocol, retained lock, unknown-state latch, EOF/SIGTERM cleanup')
