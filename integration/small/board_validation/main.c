#include "protocol.h"
#define MMIO(a) (*(volatile uint32_t *)(uintptr_t)(a))
#define ISP(o) MMIO(0x51000000u+(o))
#define SNAP(o) MMIO(0x50000000u+(o))
static volatile struct validation_mailbox *const m =
    (volatile struct validation_mailbox *)(uintptr_t)VALIDATION_BASE;
static void fence(void) { __asm__ volatile("fence iorw,iorw" ::: "memory"); }
static void snapshot(void) {
  for (unsigned retry=0; retry<8; ++retry) {
    uint32_t seq=SNAP(8);
    m->snapshot[0]=seq;
    for (unsigned i=1; i<17; ++i) m->snapshot[i]=SNAP(8+4*i);
    if (seq==SNAP(8)) return;
    ++m->snapshot_retries;
  }
  m->errors |= ERR_SNAPSHOT;
}
static void test_shadow(void) {
  m->signature=0;
  if (m->dirty) { m->errors |= ERR_RESTORE; m->state=FAILED; return; }
  if (ISP(0xff00)!=1) { m->errors |= ERR_OWNER; m->state=FAILED; return; }
  /* Never change shadow state while a PS commit can still apply. PS must
   * quiesce whole sequences before grant and keep ownership until ack. */
  if (ISP(0x0c)&1) { m->errors |= ERR_PENDING; m->state=FAILED; return; }
  if (m->isp_id!=0x49535031u) { m->errors |= ERR_ID; m->state=FAILED; return; }
  m->state=TESTING;
  m->before=ISP(0x14);
  if (m->before>1022) { m->errors |= ERR_READBACK; m->state=FAILED; return; }
  m->trial=m->before==1022 ? 1021 : m->before+1;
  m->dirty=1; fence();
  ISP(0x14)=m->trial;
  m->observed=ISP(0x14);
  if (m->observed!=m->trial) m->errors |= ERR_READBACK;
  m->state=RESTORING;
  ISP(0x14)=m->before;
  m->restored=ISP(0x14);
  if (m->restored!=m->before) { m->errors |= ERR_RESTORE; m->state=FAILED; return; }
  m->dirty=0;
  ++m->tests;
  if (m->observed==m->trial) { m->signature=DONE_SIGNATURE; m->state=COMPLETE; }
  else m->state=FAILED;
}
int main(void) {
  /* Invalidate publication first; clear stale host authorization on CPU reset.
   * RAM survives reset. Host must wait for magic/version then authorize anew. */
  uint32_t interrupted=m->magic==VALIDATION_MAGIC && m->dirty;
  uint32_t previous=m->before;
  m->magic=0; fence();
  for (unsigned i=1; i<sizeof(*m)/4; ++i) ((volatile uint32_t *)m)[i]=0;
  m->version=VALIDATION_VERSION; m->size=sizeof(*m); m->state=WAIT_VIDEO;
  if (interrupted) {
    m->before=previous; m->dirty=1; m->errors=ERR_RESTORE; m->state=FAILED;
  }
  fence(); m->magic=VALIDATION_MAGIC;
  for (;;) {
    ++m->heartbeat;
    /* Explicit ready assertion prevents a read hanging on stopped video clk.
     * Firmware cannot cancel an outstanding native/CDC transaction. */
    if (m->video_ready!=0x56494431u) continue;
    ++m->publish_seq; fence(); /* odd while group updates */
    snapshot();
    m->owner=ISP(0xff00)&1;
    if (m->owner) {
      m->isp_id=ISP(0); m->isp_version=ISP(4); m->capabilities=ISP(8);
      if (m->isp_id!=0x49535031u) m->errors |= ERR_ID;
    }
    if (m->state==WAIT_VIDEO || m->state==OBSERVING || m->state==OWNED)
      m->state=m->owner ? OWNED : OBSERVING;
    uint32_t request=m->request;
    if (request!=m->ack) {
      fence();
      if (m->command==COMMAND_TEST && m->owner) test_shadow();
      else { m->errors |= ERR_OWNER; m->state=FAILED; }
      fence(); m->ack=request;
    }
    fence(); ++m->publish_seq;
  }
}
