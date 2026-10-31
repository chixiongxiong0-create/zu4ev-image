/* Boot-only release of an unused PS IIC0 reset; no IIC register/sensor writes. */
#define _POSIX_C_SOURCE 200809L
#define _FILE_OFFSET_BITS 64
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#ifndef IIC_PREPARE_TEST
#include <fcntl.h>
#include <glob.h>
#include <sys/file.h>
#include <sys/mman.h>
#include <unistd.h>
#endif
/* UG1087 CRL_APB; masks also checked against Vitis 2025.1 pmufw/crl_apb.h. */
static int prepare_iic(volatile uint32_t *crl,volatile const uint32_t *isp) {
    uint32_t ref=crl[0x120/4],pll=crl[0x20/4],lock=crl[0x40/4],reset=crl[0x238/4];
    if(isp[0]!=0x49535031u || (isp[0xff00/4]&1u) || (isp[0xff08/4]&1u)) {
        fputs("IIC_PREPARE_REFUSED: expected valid ISP with PS owner/RUN0\n",stderr);return -1;
    }
    if(!(ref&(1u<<24)) || (ref&7u) || !(ref&0x3f00u) || !(lock&1u) || (pll&9u)) {
        fputs("IIC_PREPARE_REFUSED: inherited IOPLL source/clock/divider/lock invalid\n",stderr);return -1;
    }
    printf("IIC_PREPARE ref=%08x pll=%08x lock=%08x reset_before=%08x\n",ref,pll,lock,reset);
    if(reset&0x200u) {
        __sync_synchronize();crl[0x238/4]=reset&~0x200u;__sync_synchronize();
    }
    if(crl[0x238/4]!=(reset&~0x200u) || crl[0x120/4]!=ref) {
        fputs("IIC_PREPARE_FAILED: CRL readback changed unexpectedly\n",stderr);return -1;
    }
    printf("IIC_PREPARE_OK reset_after=%08x; clock and every other reset bit preserved\n",crl[0x238/4]);
    return 0;
}
#ifndef IIC_PREPARE_TEST
int main(int argc,char **argv) {
    if(argc!=2 || strcmp(argv[1],"--boot-before-handoff")) {
        fputs("Usage: ibex_iic_prepare --boot-before-handoff\nRequires exclusive PS ownership and no R5/Linux IIC0 driver.\n",stderr);return 2;
    }
    glob_t drivers={0};
    int found=glob("/sys/bus/platform/devices/*ff020000*/driver",0,NULL,&drivers);
    globfree(&drivers);
    if(found!=GLOB_NOMATCH) {fputs("IIC_PREPARE_REFUSED: driver present or driver discovery failed\n",stderr);return 1;}
    int lock=open("/run/ibex_isp_handoff.lock",O_CREAT|O_RDWR,0600);
    if(lock<0 || flock(lock,LOCK_EX|LOCK_NB)) {perror("handoff lock");return 1;}
    int fd=open("/dev/mem",O_RDWR|O_SYNC);
    if(fd<0) {perror("/dev/mem");close(lock);return 1;}
    volatile const uint32_t *isp=mmap(NULL,65536,PROT_READ,MAP_SHARED,fd,(off_t)0xa0040000ULL);
    volatile uint32_t *crl=mmap(NULL,4096,PROT_READ|PROT_WRITE,MAP_SHARED,fd,(off_t)0xff5e0000ULL);
    if(isp==MAP_FAILED || crl==MAP_FAILED) {perror("map boot guards");close(fd);close(lock);return 1;}
    int result=prepare_iic(crl,isp);
    munmap((void *)isp,65536);munmap((void *)crl,4096);close(fd);close(lock);
    return result?1:0;
}
#endif
