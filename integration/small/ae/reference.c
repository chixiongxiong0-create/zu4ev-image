#include <stdio.h>
#include <stdint.h>
#include "ae_core.h"
int main(void) {
 uint32_t x[14]; struct ae_core prev={0};
 while(scanf("%u",&x[1])==1) {
  for(unsigned i=2;i<14;i++) if(scanf("%u",&x[i])!=1) return 2;
  struct ae_core s={0}; struct ae_update n;
  if(x[7]==0x80000000u) s=prev;
  else {s.last_stats_seq=x[2];s.last_write_fe=x[3];s.exposure=x[4];s.max_exposure=x[5];s.fine_gain=x[6];s.initialized=x[7];s.have_write=x[8];}
  x[2]=s.last_stats_seq;x[3]=s.last_write_fe;x[4]=s.exposure;x[5]=s.max_exposure;x[6]=s.fine_gain;x[7]=s.initialized;x[8]=s.have_write;
  unsigned k=sc130_ae_core_propose(&s,x[9],x[10],x[11],x[12],&n);
  if(x[13] && k) sc130_ae_core_commit(&s,x[9],&n);
  for(unsigned i=1;i<14;i++) printf("%u ",x[i]);
  printf("%u %u %u %u %u %u %u %u %u %u\n",k,n.exposure,n.fine_gain,s.last_stats_seq,s.last_write_fe,s.exposure,s.max_exposure,s.fine_gain,s.initialized,s.have_write);
  prev=s;
 }
 return 0;
}
