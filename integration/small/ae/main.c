#include <stdint.h>
#include "ae_core.h"
#define INPUT ((volatile uint32_t *)0x0023f000u)
#define OUTPUT ((volatile uint32_t *)0x0023f800u)
static inline void barrier(void) { __asm__ volatile("fence rw,rw" ::: "memory"); }
static inline uint32_t cycles(void) { uint32_t n; __asm__ volatile("csrr %0,mcycle":"=r"(n)); return n; }
void *memset(void *p,int v,unsigned n) { unsigned char *b=p; while(n--) *b++=(unsigned char)v; return p; }
int main(void) {
 uint32_t last=0;
 OUTPUT[0]=0; OUTPUT[15]=0x41454942u; barrier();
 for(;;) {
  uint32_t v=INPUT[0], in[14];
  if(!v || (v&1u) || v==last) continue;
  barrier();
  for(unsigned i=1;i<14;i++) in[i]=INPUT[i];
  barrier();
  if(INPUT[0]!=v) continue;
  struct ae_core s={0}; struct ae_update next;
  s.last_stats_seq=in[2]; s.last_write_fe=in[3];
  s.exposure=(uint16_t)in[4]; s.max_exposure=(uint16_t)in[5];
  s.fine_gain=(uint8_t)in[6]; s.initialized=(uint8_t)in[7]; s.have_write=(uint8_t)in[8];
  uint32_t start=cycles();
  enum ae_change kind=sc130_ae_core_propose(&s,in[9],in[10],in[11],(int)in[12],&next);
  if(in[13] && kind!=AE_CHANGE_NONE) sc130_ae_core_commit(&s,in[9],&next);
  uint32_t elapsed=cycles()-start;
  OUTPUT[0]=v|1u; barrier();
  OUTPUT[1]=in[1]; OUTPUT[2]=kind; OUTPUT[3]=next.exposure; OUTPUT[4]=next.fine_gain;
  OUTPUT[5]=s.last_stats_seq; OUTPUT[6]=s.last_write_fe;
  OUTPUT[7]=s.exposure; OUTPUT[8]=s.max_exposure; OUTPUT[9]=s.fine_gain;
  OUTPUT[10]=s.initialized; OUTPUT[11]=s.have_write; OUTPUT[12]=elapsed; OUTPUT[13]=v;
  barrier(); OUTPUT[0]=v; barrier(); last=v;
 }
}
