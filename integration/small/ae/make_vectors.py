"""Build reference vectors including stable actual R5 frame records; no hardware writes."""
from pathlib import Path
import struct, subprocess, json, random
b=Path(__file__).resolve().parents[1]; repo=b.parents[1]; out=repo/'build/ibex_small/ae';out.mkdir(parents=True,exist_ok=True)
def wsl(p):
 s=str(p.resolve()).replace('\\','/');return '/mnt/'+s[0].lower()+s[2:]
ref=out/'reference'
subprocess.run(['wsl','-d','Ubuntu-24.04','--','gcc','-std=c11','-O2','-I'+wsl(b/'ae'),wsl(b/'ae/ae_core.c'),wsl(b/'ae/reference.c'),'-o',wsl(ref)],check=True)
cases=[]; kinds=[]; real=[]
def add(state,fe,seq,mean,valid=1,commit=1,label='boundary',record=None):
 cases.append([len(cases)+1,*state,fe&0xffffffff,seq&0xffffffff,mean,valid,commit]);kinds.append(label);real.append(record)
# Explicit state is [last_stats,last_write,exp,maxexp,gain,initialized,have_write].
for exp,maxexp,gain in [(16,8400,32),(1600,8400,32),(8400,8400,32),(8400,8400,63),(800,8400,63)]:
 for mean in [0,1,64,87,88,96,104,105,255,1023,0xffffffff]:
  add([9,1,exp,maxexp,gain,1,1],10,10,mean)
# Invalid, duplicate, init, holdoff boundaries and wrap-around.
for valid,seq,init,delta in [(0,11,1,4),(1,0,1,4),(1,9,1,4),(1,10,0,4),(1,10,1,0),(1,10,1,1),(1,10,1,3),(1,10,1,4)]:
 add([9,0xfffffffe,1600,8400,40,init,1],(0xfffffffe+delta)&0xffffffff,seq,32,valid)
# Multi-step policy sequences use previous reference state, then emit explicit input state.
for initial_exp,initial_gain in [(1600,32),(8400,63),(16,63),(8400,32)]:
 for step in range(32):
  st=[0,0,initial_exp,8400,initial_gain,0,0] if step==0 else [0,0,0,0,0,0x80000000,0]
  add(st,step+1,step+1,[20,20,20,20,20,96,200,200,200,200,0,105,87,88,104,255][step%16],label='sequence')
# Captured records are stable only in [after_index-512, before_index).
live=repo/'build/ibex_small/ae_live'
if (live/'core.bin').exists():
 before=struct.unpack('<8I',(live/'ae_log_before.bin').read_bytes());after=struct.unpack('<8I',(live/'ae_log_after.bin').read_bytes())
 assert before[0]==0x41453552 and before[3]==after[3]==0
 rows=list(struct.iter_unpack('<17I',(live/'ae_records.bin').read_bytes()))
 core=(live/'core.bin').read_bytes();maxexp=struct.unpack_from('<H',core,10)[0]
 core_last_write=struct.unpack_from('<I',core,4)[0];core_have_write=core[14]
 first=max(0,after[2]-512); end=before[2]; last_seq=None; last_write=None; first_fe=None
 for index in range(first,end):
  r=rows[index%512];fe,seq,frame,mean,exp,gain=r[:6]
  if not seq or r[16]: continue
  if first_fe is None: first_fe=fe;last_write=core_last_write;assert ((fe-last_write)&0xffffffff)<0x80000000
  st=[last_seq if last_seq is not None else (seq-1)&0xffffffff,last_write,exp,maxexp,gain,1,core_have_write]
  if (fe-first_fe)&0xffffffff >=4:
   add(st,fe,seq,mean,label='live_r5',record={'ring_index':index,'fe':fe,'stats_seq':seq,'frame':frame,'mean':mean,'kind':r[9],'code':r[8],'exp':exp,'gain':gain})
  last_seq=seq
  if r[9]:last_write=fe
else:
 for row in json.loads((b/'ae/live_fixture.json').read_text()):
  x=row['input'];add(x[1:8],x[8],x[9],x[10],x[11],x[12],label='live_r5',record=row['r5_record'])
lines=''.join(' '.join(map(str,x))+'\n' for x in cases)
r=subprocess.run(['wsl','-d','Ubuntu-24.04','--',wsl(ref)],input=lines,text=True,encoding="utf-8",errors="replace",capture_output=True,check=True)
res=[]
for i,line in enumerate(r.stdout.splitlines()):
 vals=list(map(int,line.split()));assert len(vals)==23
 inp=vals[:13];expected=vals[13:]
 if real[i]:
  rr=real[i];assert expected[0]==rr['kind'],(rr,expected)
  if rr['kind']:assert expected[1 if rr['kind']==1 else 2]==rr['code'],(rr,expected)
 res.append({'input':inp,'expected':expected,'label':kinds[i],'r5_record':real[i]})
assert len(res)==len(cases)
(out/'vectors.json').write_text(json.dumps(res,indent=2))
# Flat hex for SV: each record 13 input + 10 expected words.
(b/'ae/vectors.mem').write_text(''.join(f'{v:08x}\n' for row in res for v in row['input']+row['expected']))
(b/'ae/vector_count.svh').write_text(f'localparam int AE_CASES = {len(res)};\n')
summary={'cases':len(res),'live_r5_cases':sum(x['label']=='live_r5' for x in res),'sequence_cases':sum(x['label']=='sequence' for x in res),'source':'Unmodified R5 ae_core.c native reference plus actual stable R5 ring proposals'}
(out/'vector_summary.json').write_text(json.dumps(summary,indent=2));print(json.dumps(summary))
