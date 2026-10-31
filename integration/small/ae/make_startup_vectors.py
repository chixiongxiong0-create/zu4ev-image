from pathlib import Path
import struct,json,subprocess
b=Path(__file__).resolve().parents[1];repo=b.parents[1];out=repo/'build/ibex_small/ae';p=repo/'build/ibex_small/ae_startup'
base=json.loads((out/'vectors.json').read_text());base=[x for x in base if x['label']!='startup_r5']
before=struct.unpack('<8I',(p/'ae_log_before.bin').read_bytes());after=struct.unpack('<8I',(p/'ae_log_after.bin').read_bytes());raw=list(struct.iter_unpack('<17I',(p/'ae_records.bin').read_bytes()));core=struct.unpack('<IIHHBBBx',(p/'core.bin').read_bytes())
assert before[3]==after[3]==0 and max(0,after[2]-512)==0,'Need complete startup prefix for exact state'
records=raw[:before[2]];maxexp=core[3];lines=[]
for i,r in enumerate(records):
 assert r[16]==0
 st=[0,0,r[4],maxexp,r[5],0,0] if i==0 else [0,0,0,0,0,0x80000000,0]
 x=[len(base)+i+1,*st,r[0],r[1],r[3],1,int(r[9]!=0)]
 lines.append(' '.join(map(str,x)))
ref='/mnt/'+str(out.resolve())[0].lower()+str((out/'reference').resolve())[2:].replace('\\','/')
r=subprocess.run(['wsl','-d','Ubuntu-24.04','--',ref],input='\n'.join(lines)+'\n',text=True,encoding='utf-8',errors='replace',capture_output=True,check=True)
startup=[];direct=0;cancelled=0;changes=0
for rec,line in zip(records,r.stdout.splitlines()):
 v=list(map(int,line.split()));assert len(v)==23
 inp,exp=v[:13],v[13:];assert inp[3]==rec[4] and inp[5]==rec[5],('state differs from R5',inp,rec)
 cancel=rec[9]==0 and rec[6]!=0 and rec[11]==0
 if not cancel:
  assert exp[0]==rec[9],('decision mismatch',inp,exp,rec)
  if rec[9]:assert exp[1 if rec[9]==1 else 2]==rec[8]
  direct+=1
 else:cancelled+=1
 changes+=rec[9]!=0
 meta={'fe':rec[0],'stats_seq':rec[1],'frame':rec[2],'mean':rec[3],'kind':rec[9],'code':rec[8],'guard_cancelled':cancel,'iic_start_tick':rec[11],'high_end_tick':rec[12],'low_end_tick':rec[13],'fault':rec[16]}
 startup.append({'input':inp,'expected':exp,'label':'startup_r5','r5_record':meta})
assert len(startup)==len(records)
allrows=base+startup
(out/'vectors.json').write_text(json.dumps(allrows,indent=2)+'\n')
(b/'ae/startup_fixture.json').write_text(json.dumps(startup,indent=2)+'\n')
(b/'ae/vectors.mem').write_text(''.join(f'{v:08x}\n' for row in allrows for v in row['input']+row['expected']))
(b/'ae/vector_count.svh').write_text(f'localparam int AE_CASES = {len(allrows)};\n')
summary={'cases':len(allrows),'startup_cases':len(startup),'startup_direct_observable':direct,'startup_guard_cancelled':cancelled,'startup_actual_commits':changes,'r5_fault':after[3]}
(out/'startup_vector_summary.json').write_text(json.dumps(summary,indent=2));print(json.dumps(summary))
