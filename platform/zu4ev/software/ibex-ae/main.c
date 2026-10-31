#include "board.h"
#include "ae_core.h"

/* Native Ibex adapter: all measurements and sensor responses are live MMIO. */
#ifndef AE_READ32
#define AE_READ32(a) (*(volatile uint32_t *)(uintptr_t)(a))
#define AE_WRITE32(a,v) (*(volatile uint32_t *)(uintptr_t)(a)=(v))
#endif
#define SENSOR(o) AE_READ32(AE_SENSOR_BASE+(o))
#define SNAP(o) AE_READ32(AE_SNAPSHOT_BASE+(o))
#define ISP(o) AE_READ32(AE_ISP_BASE+(o))
volatile struct ae_mailbox *const ae_mailbox=(volatile struct ae_mailbox *)(uintptr_t)AE_MAILBOX_BASE;
volatile struct ae_record ae_records[AE_LOG_CAP];
static struct ae_core core;
static volatile uint32_t irq_fe,irq_pending;
static uint16_t previous_fe;
static uint32_t extended_fe,have_fe;
static void fence(void) { __asm__ volatile("fence iorw,iorw" ::: "memory"); }
static void irq_disable(void) { __asm__ volatile("csrci mstatus,8" ::: "memory"); }
static void irq_enable(void) { __asm__ volatile("csrsi mstatus,8" ::: "memory"); }
static uint32_t ticks(void) { return SENSOR(4); }
static void sensor_write32(uint32_t o,uint32_t v) { AE_WRITE32(AE_SENSOR_BASE+o,v); fence(); }
static int run_requested(void) { return (SENSOR(8)&1u)!=0; }
static void publish_record(const struct ae_record *r) {
    ae_records[ae_mailbox->records%AE_LOG_CAP]=*r;
    fence();
    ++ae_mailbox->records;
}
static void fault_stop(uint32_t fault) {
    irq_disable();
    ae_mailbox->fault=fault;
    ae_mailbox->state=AE_FAULT;
    ae_mailbox->signature=0;
    fence();
    sensor_write32(0x1c,8);
    for (;;) ++ae_mailbox->heartbeat;
}
void ae_trap_handler(uint32_t cause,uint32_t pc) {
    ae_mailbox->mcause=cause;
    ae_mailbox->mepc=pc;
    fault_stop(AE_TRAP);
}
void ae_irq_handler(void) {
    uint32_t pending=SNAP(0x48);
    if(pending&1u) {
        uint16_t raw=(uint16_t)SNAP(0x40);
        if(!have_fe) { extended_fe=raw;have_fe=1; }
        else extended_fe+=(uint16_t)(raw-previous_fe);
        previous_fe=raw;
        irq_fe=extended_fe;
        irq_pending=1;
        ae_mailbox->fe_seq=extended_fe;
        ++ae_mailbox->irq_count;
    }
    /* W1C acknowledges exactly the counters captured by the pending read. */
    AE_WRITE32(AE_SNAPSHOT_BASE+0x48,pending&3u);
    fence();
}
static uint8_t sensor_transfer(uint16_t reg,uint8_t value,int read) {
    sensor_write32(0x14,reg);
    sensor_write32(0x18,value);
    sensor_write32(0x10,0x3001u|(read?2u:0u));
    uint32_t start=ticks();
    for (;;) {
        uint32_t status=SENSOR(8);
        if(status&0xe0u) fault_stop((status&0x40u)?AE_I2C_TIMEOUT:AE_I2C_ERROR);
        if(status&0x10u) return (uint8_t)SENSOR(0x18);
        if((uint32_t)(ticks()-start)>AE_LITE_HZ/50u) fault_stop(AE_I2C_TIMEOUT);
    }
}
static uint8_t sensor_read(uint16_t reg) { return sensor_transfer(reg,0,1); }
static void sensor_write(uint16_t reg,uint8_t value) { (void)sensor_transfer(reg,value,0); }
static void sensor_verify(uint16_t reg,uint8_t value) {
    if(sensor_read(reg)!=value) fault_stop(AE_READBACK);
}
static int statistics(uint32_t *seq,uint32_t *frame,uint32_t *mean) {
    for(unsigned retry=0;retry<16;retry++) {
        uint32_t before=SNAP(8);
        uint32_t valid0=SNAP(0x20);
        *frame=SNAP(0x0c);
        *mean=SNAP(0x10);
        uint32_t after=SNAP(8);
        uint32_t valid1=SNAP(0x20);
        if(before==after && (valid0&valid1&1u)) { *seq=before;return 1; }
    }
    return 0;
}
static void start_session(void) {
    sensor_write32(0x1c,2);
    ae_mailbox->state=AE_STARTING;
    if(ISP(0xff00)!=1 || ISP(0)!=0x49535031u || !(ISP(8)&0x20u)) fault_stop(AE_BAD_ID);
    if(ISP(0x0c)&1u) fault_stop(AE_BAD_OWNER);
    /* Historical board-observed ID, not manufacturer authentication. The PS
     * must already have configured and started this sensor before handoff. */
    if(sensor_read(0x3107)!=0x01 || sensor_read(0x3108)!=0x30 || sensor_read(0x0100)!=1)
        fault_stop(AE_BAD_SENSOR);
    uint16_t vts=(uint16_t)((uint16_t)sensor_read(0x320e)<<8);
    vts|=sensor_read(0x320f);
    uint16_t exposure=(uint16_t)((uint16_t)sensor_read(0x3e01)<<8);
    exposure|=sensor_read(0x3e02);
    uint8_t gain_hi=sensor_read(0x3e08),gain=sensor_read(0x3e09);
    uint8_t mode=sensor_read(0x3e03);
    if(vts<=4 || vts>4099 || exposure<16 || exposure>((uint32_t)vts-4u)*16u ||
       (exposure&15u) || (gain_hi&0xfcu) || gain<0x20 || gain>0x3f) fault_stop(AE_BAD_SENSOR);
    if(!(mode&1u)) { sensor_write(0x3e03,mode|1u);sensor_verify(0x3e03,mode|1u); }
    sc130_ae_core_init(&core,exposure,vts,gain);
    /* AE control is live, independent of the frame-boundary ISP shadow bank. */
    uint32_t control=ISP(0x248);
    AE_WRITE32(AE_ISP_BASE+0x248,control|1u);
    fence();
    if(!(ISP(0x248)&1u)) fault_stop(AE_READBACK);
    ae_mailbox->exposure=exposure;
    ae_mailbox->gain=gain;
    have_fe=0;irq_pending=0;
    uint32_t pending=SNAP(0x48);
    AE_WRITE32(AE_SNAPSHOT_BASE+0x48,pending&3u);
    fence();
    ++ae_mailbox->session;
    ae_mailbox->state=AE_RUNNING;
    ae_mailbox->signature=0x600dae01u;
    irq_enable();
}
static void run_session(void) {
    uint32_t last_fe=0,last_stats=0,stale=0,last_activity=ticks();
    while(run_requested()) {
        ++ae_mailbox->heartbeat;
        if(!irq_pending) {
            if((uint32_t)(ticks()-last_activity)>AE_LITE_HZ) fault_stop(AE_NO_FRAMES);
            continue;
        }
        irq_disable();
        uint32_t fe=irq_fe;
        irq_pending=0;
        irq_enable();
        last_activity=ticks();
        if(last_fe && fe-last_fe>1) ae_mailbox->dropped_fe+=fe-last_fe-1;
        last_fe=fe;
        uint32_t seq,frame,mean;
        if(!statistics(&seq,&frame,&mean) || !seq || seq==last_stats) {
            if(++stale>120) fault_stop(AE_NO_STATS);
            continue;
        }
        stale=0;last_stats=seq;
        ae_mailbox->stats_seq=seq;ae_mailbox->stats_frame=frame;ae_mailbox->mean=mean;
        struct ae_update next;
        enum ae_change kind=sc130_ae_core_propose(&core,fe,seq,mean,1,&next);
        struct ae_record r={.fe=fe,.stats=seq,.frame=frame,.mean=mean,
            .exposure=core.exposure,.gain=core.fine_gain,.kind=kind};
        if(kind!=AE_CHANGE_NONE) {
            uint32_t sof=SNAP(0x44),wait_start=ticks();
            while(SNAP(0x44)==sof) {
                if(!run_requested()) return;
                if((uint32_t)(ticks()-wait_start)>AE_LITE_HZ/50u) fault_stop(AE_NO_SOF);
            }
            r.sof_before=SNAP(0x44);
            if((uint16_t)SNAP(0x40)!=(uint16_t)fe || !run_requested()) continue;
            r.proposed=kind==AE_CHANGE_EXPOSURE?next.exposure:next.fine_gain;
            r.start_tick=ticks();
            /* Once a proposal starts, RUN0 waits for the complete byte group
             * and readback. The gate cannot revoke ISP ownership until ack. */
            if(kind==AE_CHANGE_EXPOSURE) {
                sensor_write(0x3e01,(uint8_t)(next.exposure>>8));
                sensor_write(0x3e02,(uint8_t)next.exposure);
            } else sensor_write(0x3e09,next.fine_gain);
            r.end_tick=ticks();r.sof_after=SNAP(0x44);
            if(r.sof_before!=r.sof_after || (uint16_t)SNAP(0x40)!=(uint16_t)fe) {
                r.fault=AE_CROSS_FRAME;publish_record(&r);fault_stop(AE_CROSS_FRAME);
            }
            if(kind==AE_CHANGE_EXPOSURE) {
                sensor_verify(0x3e01,(uint8_t)(next.exposure>>8));
                sensor_verify(0x3e02,(uint8_t)next.exposure);
            } else sensor_verify(0x3e09,next.fine_gain);
            sc130_ae_core_commit(&core,fe,&next);
            ae_mailbox->exposure=core.exposure;ae_mailbox->gain=core.fine_gain;
            ++ae_mailbox->changes;
        }
        ae_mailbox->sof_seq=SNAP(0x44);
        publish_record(&r);
    }
}
int main(void) {
    irq_disable();
    ae_mailbox->magic=0;fence();
    for(unsigned i=1;i<sizeof(*ae_mailbox)/4;i++) ((volatile uint32_t *)ae_mailbox)[i]=0;
    ae_mailbox->version=1;ae_mailbox->size=sizeof(*ae_mailbox);ae_mailbox->state=AE_WAITING;
    fence();ae_mailbox->magic=AE_MAGIC;
    if(SENSOR(0)!=0x53454e31u) fault_stop(AE_BAD_ID);
    sensor_write32(0x1c,1);
    __asm__ volatile("li t0,0x20000; csrs mie,t0" ::: "t0","memory");
    for (;;) {
        while(!(SENSOR(0x1c)&8u) || !run_requested()) {
            ++ae_mailbox->heartbeat;
            if(!run_requested() && (SENSOR(0x1c)&8u)) sensor_write32(0x1c,4);
        }
        start_session();
        run_session();
        irq_disable();
        fence();sensor_write32(0x1c,4);
        ae_mailbox->state=AE_STOPPED;
    }
}
