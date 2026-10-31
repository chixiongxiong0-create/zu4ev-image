/* Runtime PS/Ibex handoff. Never stops or starts R5 and never writes PS IIC. */
#define _POSIX_C_SOURCE 200809L
#define _FILE_OFFSET_BITS 64
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/file.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

enum { OWNER=0xff00, STATUS=0xff04, RUN=0xff08 };
enum { QUIESCENT=1, GRANTED=2, BUSY=4, ARMED=8, FAULT=16, BOOT_READY=64 };
static volatile uint32_t *isp;
static uint32_t rd(unsigned offset) {
    uint32_t value=isp[offset/4];__sync_synchronize();return value;
}
static void wr(unsigned offset,uint32_t value) {
    __sync_synchronize();isp[offset/4]=value;__sync_synchronize();
}
static uint64_t now_ms(void) {
    struct timespec now;
    if(clock_gettime(CLOCK_MONOTONIC,&now)) return 0;
    return (uint64_t)now.tv_sec*1000+(unsigned long)now.tv_nsec/1000000;
}
static int wait_status(uint32_t mask,uint32_t expected,const char *what) {
    uint64_t deadline=now_ms()+2000;
    const struct timespec pause={0,1000000};
    do {
        if((rd(STATUS)&mask)==expected) return 0;
        nanosleep(&pause,NULL);
    } while(now_ms()<deadline);
    fprintf(stderr,"Timeout waiting for %s: owner=%08" PRIx32 " run=%08" PRIx32 " status=%08" PRIx32 "\n",
            what,rd(OWNER),rd(RUN),rd(STATUS));
    return -1;
}
static int stop(void) {
    /* A stop request is distinct from the prior session's quiescent value.
     * Duplicate writes while pending are idempotent in the hardware gate. */
    wr(RUN,0);
    uint32_t expected_ack=(rd(RUN)>>1)&1u;
    if(wait_status(QUIESCENT|BUSY|(1u<<9),QUIESCENT|(expected_ack<<9),"complete AE/I2C quiescence")) return -1;
    wr(OWNER,0);
    if(rd(OWNER)&1u) { fputs("Owner reclaim rejected\n",stderr);return -1; }
    if(wait_status(GRANTED|BUSY,0,"sensor mux returned to PS")) return -1;
    puts("PS owns ISP and sensor bus; AE is stopped. PS writers may now resume.");
    return 0;
}
static int iic_idle_preflight(int fd) {
    volatile const uint32_t *crl=mmap(NULL,4096,PROT_READ,MAP_SHARED,fd,(off_t)0xff5e0000ULL);
    if(crl==MAP_FAILED) { perror("map CRL");return -1; }
    uint32_t ref=crl[0x120/4],reset=crl[0x238/4];
    __sync_synchronize();munmap((void *)crl,4096);
    if(!(ref&(1u<<24)) || (reset&(1u<<9))) {
        fputs("IIC0 clock/reset preflight failed; no IIC0 access performed\n",stderr);return -1;
    }
    volatile const uint32_t *iic=mmap(NULL,4096,PROT_READ,MAP_SHARED,fd,(off_t)0xff020000ULL);
    if(iic==MAP_FAILED) { perror("map IIC0");return -1; }
    uint32_t control=iic[0],status=iic[1];
    __sync_synchronize();munmap((void *)iic,4096);
    if((control&0x10u) || (status&0x140u)) {
        fprintf(stderr,"PS IIC0 must be idle with HOLD clear and TX FIFO empty: CR=%08" PRIx32 " SR=%08" PRIx32 "\n",control,status);
        return -1;
    }
    return 0;
}
static int start(int fd) {
    if(rd(OWNER)&1u) { fputs("Ibex already owns ISP; run stop before a new start\n",stderr);return -1; }
    if(rd(0)!=0x49535031u || (rd(0x0c)&1u)) {
        fputs("ISP identity invalid or frame commit pending; finish PS configuration first\n",stderr);return -1;
    }
    if(iic_idle_preflight(fd)) return -1;
    wr(RUN,0);
    uint32_t ack=(rd(RUN)>>1)&1u;
    if(wait_status(QUIESCENT|BOOT_READY|BUSY|(1u<<9),QUIESCENT|BOOT_READY|(ack<<9),"fresh firmware boot and stop acknowledgement")) return -1;
    if(rd(STATUS)&FAULT) { fputs("Firmware fault is latched; reset Ibex and inspect diagnostics\n",stderr);return -1; }
    wr(OWNER,1);
    if(!(rd(OWNER)&1u)) { fputs("ISP grant rejected\n",stderr);return -1; }
    if(wait_status(GRANTED|BUSY,GRANTED,"sensor bus idle and mux grant")) return -1;
    wr(RUN,1);
    if(!(rd(RUN)&1u) || wait_status(ARMED|QUIESCENT,ARMED,"new AE session arm")) return -1;
    puts("Ibex owns ISP and sensor bus; live AE session authorized. USB/DP consumers continue.");
    return 0;
}
int main(int argc,char **argv) {
    int starting=argc==3 && !strcmp(argv[1],"start") && !strcmp(argv[2],"--ps-writers-stopped");
    int stopping=argc==2 && !strcmp(argv[1],"stop");
    int status=argc==2 && !strcmp(argv[1],"status");
    if(!starting && !stopping && !status) {
        fprintf(stderr,"Usage: %s status | start --ps-writers-stopped | stop\n"
                "Start requires initialized running video clocks, completed ISP commit, and all R5/PS IIC/ISP writers stopped.\n",argv[0]);return 2;
    }
    int lock=open("/run/ibex_isp_handoff.lock",O_CREAT|O_RDWR,0600);
    if(lock<0 || flock(lock,LOCK_EX|LOCK_NB)) { perror("handoff lock");return 1; }
    int fd=open("/dev/mem",(status?O_RDONLY:O_RDWR)|O_SYNC);
    if(fd<0) { perror("/dev/mem");close(lock);return 1; }
    isp=mmap(NULL,65536,PROT_READ|(status?0:PROT_WRITE),MAP_SHARED,fd,(off_t)0xa0040000ULL);
    if(isp==MAP_FAILED) { perror("map ISP");close(fd);close(lock);return 1; }
    int result=starting?start(fd):stopping?stop():0;
    if(result) fputs(starting?
        "Start incomplete; inspect status and run stop before resuming any PS writer. Ownership is not forcibly reclaimed.\n":
        "Stop incomplete; keep PS writers stopped until quiescence and sensor grant return are confirmed.\n",stderr);
    uint32_t flags=rd(STATUS);
    printf("owner=%u run=%u stop_request=%u stop_ack=%u quiescent=%u grant=%u busy=%u armed=%u fault=%u restart=%u boot_ready=%u scl=%u sda=%u\n",
        rd(OWNER)&1u,rd(RUN)&1u,(rd(RUN)>>1)&1u,(flags>>9)&1u,
        flags&1u,(flags>>1)&1u,(flags>>2)&1u,(flags>>3)&1u,(flags>>4)&1u,
        (flags>>5)&1u,(flags>>6)&1u,(flags>>7)&1u,(flags>>8)&1u);
    munmap((void *)isp,65536);close(fd);close(lock);
    return result?1:0;
}
