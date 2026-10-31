import subprocess,tempfile,pathlib,struct,sys,threading,time,mmap
exe=pathlib.Path(sys.argv[1]).resolve()
assert exe.exists(), 'ispctl binary missing'
with tempfile.TemporaryDirectory() as d:
 p=pathlib.Path(d)/'mmio';p.write_bytes(bytes(65536))
 def run(*a,ok=True):
  r=subprocess.run([str(exe),'--base','0','--dev',str(p),'--lock',str(pathlib.Path(d)/'lock'),*a],capture_output=True,text=True)
  assert (r.returncode==0)==ok,(a,r.stdout,r.stderr)
  return r.stdout
 run('set','black','052'); assert struct.unpack_from('<I',p.read_bytes(),0x14)[0]==52
 run('set','sigma','32');assert struct.unpack_from('<I',p.read_bytes(),0x1c)[0]==1
 run('write','0xfffc','0xdeadbeef');assert 'deadbeef' in run('read','0xfffc')
 run('ae','status',ok=False)
 data=bytearray(p.read_bytes());struct.pack_into('<I',data,8,0x20);p.write_bytes(data)
 run('ae','enable','1');assert struct.unpack_from('<I',p.read_bytes(),0x248)[0]==1
 assert '00000001' in run('ae','status')
 run('ae','enable','0');assert struct.unpack_from('<I',p.read_bytes(),0x248)[0]==0
 run('ae','enable','2',ok=False)
 run('set','blc','0',ok=False)
 data=bytearray(p.read_bytes());struct.pack_into('<I',data,8,0x60);p.write_bytes(data)
 run('set','blc','0');assert struct.unpack_from('<I',p.read_bytes(),0x5c)[0]==0
 run('set','blc','1');assert struct.unpack_from('<I',p.read_bytes(),0x5c)[0]==1
 run('set','tone','0',ok=False)
 data=bytearray(p.read_bytes());struct.pack_into('<I',data,8,0xe0);p.write_bytes(data)
 run('set','tone','0');assert struct.unpack_from('<I',p.read_bytes(),0x64)[0]==0
 run('set','tone','1');assert struct.unpack_from('<I',p.read_bytes(),0x64)[0]==1
 for a in [('read','3'),('read','0xfffc','2'),('set','black','1023'),('set','sigma','63'),('write','0','-1'),('apply','bad'),('read','-4')]:run(*a,ok=False)
 run('curve-default')
 sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[2]/'isp/ltm'))
 from generate_tone_rom import values
 assert list(struct.unpack_from('<1024I',p.read_bytes(),0x1000))==values()
 bad=pathlib.Path(d)/'bad';bad.write_text('0\n'*1023+'1024\n');before=p.read_bytes();run('curve-load',str(bad),ok=False);assert p.read_bytes()==before
 # Emulate asynchronous hardware: pending clears before seq advances.
 with p.open('r+b') as f:
  with mmap.mmap(f.fileno(),0) as bank:
   struct.pack_into('<I',bank,0x24,0xffffffff)
   def complete():
    deadline=time.monotonic()+3
    while struct.unpack_from('<I',bank,0x20)[0]!=3:
     assert time.monotonic()<deadline,'command not submitted'
     time.sleep(.001)
    struct.pack_into('<I',bank,0x0c,1)
    time.sleep(.025)
    struct.pack_into('<I',bank,0x0c,0)
    time.sleep(.025)
    struct.pack_into('<I',bank,0x24,0) # rollover is one increment
   worker=threading.Thread(target=complete);worker.start()
   start=time.monotonic();run('apply','--swap');elapsed=time.monotonic()-start
   worker.join();assert elapsed>=.045,'apply returned before completion'
   assert struct.unpack_from('<I',bank,0x20)[0]==3
 # Sequence changes first, but pending must clear before success.
 with p.open('r+b') as f:
  with mmap.mmap(f.fileno(),0) as bank:
   struct.pack_into('<I',bank,0x20,0)
   def complete_pending():
    deadline=time.monotonic()+3
    while struct.unpack_from('<I',bank,0x20)[0]!=1:
     assert time.monotonic()<deadline,'command not submitted'
     time.sleep(.001)
    struct.pack_into('<I',bank,0x0c,1)
    struct.pack_into('<I',bank,0x24,1)
    time.sleep(.050)
    struct.pack_into('<I',bank,0x0c,0)
   worker=threading.Thread(target=complete_pending);worker.start()
   start=time.monotonic();run('apply');elapsed=time.monotonic()-start
   worker.join();assert elapsed>=.045,'apply returned while pending'
 # A nonpending block with no sequence advance must time out.
 start=time.monotonic();run('apply',ok=False);elapsed=time.monotonic()-start
 assert .95<=elapsed<2.5,elapsed
 data=bytearray(p.read_bytes());struct.pack_into('<I',data,12,1);p.write_bytes(data)
 for a in [('set','gain','128'),('apply',),('curve-default',)]:
  before=p.read_bytes();run(*a,ok=False);assert p.read_bytes()==before
print('PASS host MMIO, curve equivalence, validation and atomic input preflight')
