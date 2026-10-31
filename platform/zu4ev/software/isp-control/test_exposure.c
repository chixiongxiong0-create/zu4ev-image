#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "sensor_exposure.h"
struct fake { unsigned regs[65536], calls, fail, writes, write_regs[16]; int mismatch; };
static int io(void *ctx, unsigned reg, unsigned *v, int write_op) {
 struct fake *f=ctx;
 if (++f->calls==f->fail) return 0;
 if(write_op) { f->write_regs[f->writes++]=reg; f->regs[reg]=*v; }
 else { *v=f->regs[reg]; if(f->mismatch && reg==0x3e02 && f->writes) *v^=1; }
 return 1;
}
static void init(struct fake *f) { memset(f,0,sizeof(*f));f->regs[0x320e]=2;f->regs[0x320f]=0x11;f->regs[0x3e03]=0xaa; }
int main(void) {
 struct fake f; struct sensor_exposure s; unsigned invalid[]={0,0x11,0x20e0,65536};
 for(unsigned i=0;i<4;i++) { init(&f);sensor_exposure_init(&s,io,&f);assert(sensor_exposure_set(&s,invalid[i])==SENSOR_EXPOSURE_RANGE);assert(!f.writes); }
 init(&f);sensor_exposure_init(&s,io,&f);
 assert(sensor_exposure_set(&s,0x20d0)==SENSOR_EXPOSURE_OK);
 assert(f.regs[0x3e03]==0xab && f.regs[0x3e01]==0x20 && f.regs[0x3e02]==0xd0);
 assert(f.writes==3);assert(f.write_regs[0]==0x3e03 && f.write_regs[1]==0x3e01 && f.write_regs[2]==0x3e02);assert(sensor_exposure_set(&s,0xf)==SENSOR_EXPOSURE_OK);
 assert(f.writes==5); /* manual mode already set */
 for(unsigned fail=1;fail<=9;fail++) {
  init(&f);f.fail=fail;sensor_exposure_init(&s,io,&f);
  assert(sensor_exposure_set(&s,0x1000)==SENSOR_EXPOSURE_IO);
  unsigned calls=f.calls;assert(sensor_exposure_set(&s,0x1000)==SENSOR_EXPOSURE_UNKNOWN);assert(f.calls==calls);
 }
 init(&f);f.mismatch=1;sensor_exposure_init(&s,io,&f);
 assert(sensor_exposure_set(&s,0x1000)==SENSOR_EXPOSURE_VERIFY);
 assert(sensor_exposure_set(&s,0x1000)==SENSOR_EXPOSURE_UNKNOWN);
 init(&f);f.regs[0x320e]=0;f.regs[0x320f]=4;sensor_exposure_init(&s,io,&f);
 assert(sensor_exposure_set(&s,1)==SENSOR_EXPOSURE_RANGE);assert(!f.writes);
 puts("PASS exposure boundaries, mode preservation, failure latch and readback");
}
