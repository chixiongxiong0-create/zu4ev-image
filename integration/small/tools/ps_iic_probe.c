/* Temporary, exclusive-owner PS IIC0 probe. No GPIO or clock/reset writes.
 * Register definitions and short polled transaction ordering follow AMD's
 * embeddedsw/XilinxProcessorIPLib/drivers/iicps/src/xiicps_{hw,master,xfer}.
 * The existing FSBL clock divisor is preserved. Linux/R5 must not own IIC0.
 * Read-only CRL preflight precedes every IIC0 access. Also verify via PSU/DAP that IIC0's reference
 * clock is enabled and its reset released. An MMIO load into a gated block
 * can hang the CPU/interconnect: software deadlines/signals cannot stop it.
 * Probe/mode-probe read only sensor registers; explicit state commands write
 * only 0x0100, guarded by the historical board-observed ID 0x0130.
 * ISR (W1C), FIFO contents and sensor address pointer cannot be restored.
 */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/file.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

enum { CR=0, SR=4, ADDR=8, DATA=12, ISR=16, SIZE=20,
       IMR=32, IER=36, IDR=40 };
enum { HOLD=0x10, CLEAR_FIFO=0x40, DIVISORS=0xff00,
       MASTER_7BIT_ACK=0x0e, READ=1, BUS_ACTIVE=0x100,
       RX_VALID=0x20, TX_VALID=0x40, COMPLETE=1,
       IRQ_ALL=0x2ff, IRQ_ERRORS=0x2ec };
static volatile uint32_t *mmio;
static volatile sig_atomic_t interrupted;
static uint32_t saved_cr, saved_imr, saved_size, base_cr;

static int preflight(int fd)
{
    volatile const uint32_t *crl=mmap(NULL,4096,PROT_READ,MAP_SHARED,fd,
                                    (off_t)0xff5e0000ULL);
    if(crl==MAP_FAILED) { perror("mmap CRL_APB preflight"); return -1; }
    uint32_t ref=crl[0x120/4];
    __sync_synchronize();
    uint32_t reset=crl[0x238/4];
    __sync_synchronize();
    printf("PREFLIGHT CRL_APB IIC0_REF_CTRL[ff5e0120]=%08" PRIx32
           " RST_LPD_IOU2[ff5e0238]=%08" PRIx32 " CLKACT=%u IIC0_RESET=%u\n",
           ref,reset,!!(ref&(1U<<24)),!!(reset&(1U<<9)));
    fflush(stdout);
    munmap((void *)crl,4096);
    if(!(ref&(1U<<24)) || (reset&(1U<<9))) {
        fprintf(stderr,"Refusing IIC0 MMIO: reference clock disabled or IIC0 reset asserted. "
                "No IIC0 access or clock/reset writes performed.\n");
        return -1;
    }
    return 0;
}

static void on_signal(int sig) { interrupted=sig; }
static uint32_t rd(unsigned off)
{
#ifdef PS_IIC_PROBE_TEST
    return ps_iic_test_read(off);
#else
    uint32_t v=mmio[off/4]; __sync_synchronize(); return v;
#endif
}
static void wr(unsigned off,uint32_t value)
{
#ifdef PS_IIC_PROBE_TEST
    ps_iic_test_write(off,value);
#else
    __sync_synchronize(); mmio[off/4]=value; __sync_synchronize();
#endif
}
static uint64_t now_ms(void)
{
    struct timespec t;
    if(clock_gettime(CLOCK_MONOTONIC,&t)) return 0;
    return (uint64_t)t.tv_sec*1000U+(uint64_t)t.tv_nsec/1000000U;
}
static void snapshot(const char *tag)
{
    printf("%s CR=%08" PRIx32 " SR=%08" PRIx32 " ISR=%08" PRIx32
           " IMR=%08" PRIx32 " SIZE=%08" PRIx32 "\n",
           tag,rd(CR),rd(SR),rd(ISR),rd(IMR),rd(SIZE));
    fflush(stdout);
}
/* Each phase is bounded by elapsed wall time, including bus-idle cleanup. */
static int wait_bits(unsigned off,uint32_t mask,uint32_t expected,
                     const char *phase,int check_errors,int check_signal)
{
    uint64_t deadline=now_ms()+200;
    const struct timespec pause={0,50000};
    do {
        uint32_t irq=rd(ISR);
        if(check_errors && (irq&IRQ_ERRORS)) {
            fprintf(stderr,"%s: IIC error ISR=%08" PRIx32
                    " (NACK=%u ARB_LOST=%u TIMEOUT=%u)\n",phase,irq,
                    !!(irq&4),!!(irq&0x200),!!(irq&8));
            snapshot("ERROR"); return -1;
        }
        if(check_signal && interrupted) {
            fprintf(stderr,"%s: interrupted by signal %d\n",phase,interrupted);
            return -1;
        }
        if((rd(off)&mask)==expected) return 0;
        nanosleep(&pause,NULL);
    } while(now_ms()<deadline);
    fprintf(stderr,"%s: timeout after 200 ms\n",phase);
    snapshot("TIMEOUT"); return -1;
}
static int send_bytes(const uint8_t *bytes,unsigned n,int hold)
{
    if(wait_bits(SR,BUS_ACTIVE,0,"before TX",0,1)) return -1;
    wr(CR,base_cr|CLEAR_FIFO|(hold?HOLD:0));
    wr(ISR,IRQ_ALL);
    for(unsigned i=0;i<n;i++) wr(DATA,bytes[i]);
    wr(ADDR,0x30); /* Writing ADDR starts transfer; never restore this register. */
    return wait_bits(ISR,COMPLETE,COMPLETE,"TX",1,1);
}
static int sensor_read(uint16_t reg,uint8_t *value)
{
    uint8_t address[2]={(uint8_t)(reg>>8),(uint8_t)reg};
    if(send_bytes(address,2,1)) return -1;
    /* Keep bus held across direction change and repeated START. */
    wr(CR,base_cr|READ|HOLD|CLEAR_FIFO);
    wr(ISR,IRQ_ALL);
    wr(SIZE,1);
    wr(ADDR,0x30);
    wr(CR,base_cr|READ); /* One byte only: permit final NACK and STOP. */
    if(wait_bits(SR,RX_VALID,RX_VALID,"RX byte",1,1)) return -1;
    *value=(uint8_t)rd(DATA);
    if(wait_bits(ISR,COMPLETE,COMPLETE,"RX completion",1,1) ||
       wait_bits(SR,BUS_ACTIVE,0,"RX STOP",1,1)) return -1;
    printf("sensor[0x%04x]=0x%02x\n",reg,*value); fflush(stdout);
    return 0;
}
/* 0x0130 is a historical board observation, not manufacturer authentication. */
static int sensor_state(int requested,uint8_t id_hi,uint8_t id_lo,uint8_t stream)
{
    if(id_hi!=0x01 || id_lo!=0x30 || stream>1) {
        fprintf(stderr,"Refusing state write: requires board-observed ID 0x0130 and stream 0/1.\n");
        return -1;
    }
    if(stream==(uint8_t)requested) {
        puts("Sensor already in requested state; no register write needed.");
        return 0;
    }
    const uint8_t bytes[3]={1,0,(uint8_t)requested};
    printf("Explicit state command: writing sensor 0x0100=%d only.\n",requested);
    fflush(stdout);
    if(send_bytes(bytes,3,0) || wait_bits(SR,BUS_ACTIVE,0,"write STOP",1,1) ||
       sensor_read(0x0100,&stream) || stream!=(uint8_t)requested) {
        fprintf(stderr,"state change failed or readback mismatch; no retry performed.\n");
        return -1;
    }
    return 0;
}
static int restore(void)
{
    /* Release our HOLD and discard our FIFO; do not reset clocks/controller. */
    wr(CR,base_cr|CLEAR_FIFO);
    int failed=wait_bits(SR,BUS_ACTIVE,0,"cleanup STOP",0,0);
    wr(ISR,IRQ_ALL);
    wr(SIZE,saved_size);
    wr(CR,saved_cr);
    wr(IDR,IRQ_ALL);
    wr(IER,(~saved_imr)&IRQ_ALL);
    snapshot("RESTORED");
    if(rd(CR)!=saved_cr || (rd(IMR)&IRQ_ALL)!=(saved_imr&IRQ_ALL)) {
        fprintf(stderr,"controller CR/IMR restoration readback mismatch\n");
        failed=-1;
    }
    puts("Restored CR, IMR, transfer size. ISR/FIFO/address pointer are not restorable.");
    return failed;
}
int main(int argc,char **argv)
{
    int confirmed=argc>=2 && !strcmp(argv[1],"--clock-confirmed");
    int stream_on=argc==3 && !strcmp(argv[2],"stream-on");
    int standby=argc==3 && !strcmp(argv[2],"standby");
    int mode_probe=argc==3 && !strcmp(argv[2],"mode-probe");
    int calibration_probe=argc==3 && !strcmp(argv[2],"calibration-probe");
    if(!confirmed || argc>3 || (argc==3 && !stream_on && !standby && !mode_probe && !calibration_probe && strcmp(argv[2],"probe"))) {
        fprintf(stderr,"Usage: %s --clock-confirmed [probe|mode-probe|calibration-probe|standby|stream-on]\n"
                "Before ANY IIC0 MMIO, independently confirm through PSU/DAP:\n"
                "CRL_APB 0xff5e0120 bit24=1, 0xff5e0238 bit9=0, source clock live.\n"
                "A bus-stalled MMIO read cannot be stopped by software timeout.\n"
                "Exclusive IIC0 owner required. Probe reads SC130 0x30 ID/stream;\n"
                "mode-probe additionally reads only 3018/3031/3208..320f.\n"
                "calibration-probe reads 320e/320f/3e00..3e03/3e08/3e09.\n"
                "standby/stream-on write only 0x0100=0/1, then verify, requiring\n"
                "historical board-observed ID 0130 (not manufacturer authentication).\n",argv[0]);
        return argc==2 && !strcmp(argv[1],"--help") ? 0 : 2;
    }
    int lock=open("/tmp/ps_iic_probe.lock",O_CREAT|O_RDWR|O_CLOEXEC|O_NOFOLLOW,0600);
    if(lock<0 || flock(lock,LOCK_EX|LOCK_NB)) { perror("probe lock"); return 2; }
    int fd=open("/dev/mem",O_RDWR|O_SYNC|O_CLOEXEC);
    if(fd<0) { perror("/dev/mem"); close(lock); return 2; }
    if(preflight(fd)) { close(fd); close(lock); return 2; }
    mmio=mmap(NULL,4096,PROT_READ|PROT_WRITE,MAP_SHARED,fd,(off_t)0xff020000ULL);
    if(mmio==MAP_FAILED) { perror("mmap IIC0"); close(fd); close(lock); return 2; }
    struct sigaction sa={0}; sa.sa_handler=on_signal; sigemptyset(&sa.sa_mask);
    sigaction(SIGINT,&sa,NULL); sigaction(SIGTERM,&sa,NULL);
    puts("PREFLIGHT-PASSED: beginning IIC0 MMIO; concurrent clock/reset changes remain a race; software timeout/signals cannot cancel bus stalls.");
    fflush(stdout);
    snapshot("BEFORE");
    saved_cr=rd(CR); saved_imr=rd(IMR); saved_size=rd(SIZE);
    int result=1;
    if((rd(SR)&(BUS_ACTIVE|RX_VALID|TX_VALID)) || (saved_cr&(HOLD|0x20)) ||
       !(saved_cr&DIVISORS) || !(saved_cr&2)) {
        fprintf(stderr,"Refusing uninitialized/busy controller or pending FIFO; no writes performed.\n");
        goto out;
    }
    base_cr=(saved_cr&DIVISORS)|MASTER_7BIT_ACK;
    wr(IDR,IRQ_ALL);
    uint8_t id_hi=0,id_lo=0,stream=0;
    if(sensor_read(0x3107,&id_hi) || sensor_read(0x3108,&id_lo) ||
       sensor_read(0x0100,&stream)) goto cleanup;
    /* Invalid identity or stream value must never trigger a blind write. */
    if((id_hi==0 && id_lo==0) || (id_hi==255 && id_lo==255) || stream>1) {
        fprintf(stderr,"Implausible chip ID/stream; refusing further sensor operations.\n"); goto cleanup;
    }
    if(mode_probe) {
        static const uint16_t regs[]={0x3018,0x3031,0x3208,0x3209,0x320a,
                                      0x320b,0x320c,0x320d,0x320e,0x320f};
        static const uint8_t expected[]={0x30,0x0a,0x05,0x00,0x04,
                                         0x00,0x03,0x0c,0x02,0x11};
        for(unsigned i=0;i<sizeof(regs)/sizeof(regs[0]);++i) {
            uint8_t value;
            if(sensor_read(regs[i],&value)) goto cleanup;
            printf("mode[0x%04x] FSBL_expected=0x%02x %s\n",regs[i],expected[i],
                   value==expected[i]?"match":"MISMATCH");
            fflush(stdout);
        }
    }
    if(calibration_probe) {
        static const uint16_t regs[]={0x320e,0x320f,0x3e00,0x3e01,
                                      0x3e02,0x3e03,0x3e08,0x3e09};
        for(unsigned i=0;i<sizeof(regs)/sizeof(regs[0]);++i) {
            uint8_t value;
            if(sensor_read(regs[i],&value)) goto cleanup;
        }
    }
    if((stream_on || standby) && sensor_state(stream_on?1:0,id_hi,id_lo,stream))
        goto cleanup;
    result=0;
cleanup:
    if(restore()) result=1;
out:
    munmap((void *)mmio,4096); close(fd); close(lock);
    return result;
}
