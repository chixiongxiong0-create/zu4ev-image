/* Host integration test: execute the real entry point with emulated mappings.
 * Link with --wrap={open,flock,mmap,munmap,close}; no /dev/mem is opened.
 * An unsafe preflight must not even map the IIC peripheral.
 */
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/types.h>

int probe_main(int argc,char **argv);
static uint32_t crl[1024],iic[1024];
static unsigned iic_accesses,crl_reads;
int __wrap_open(const char *path,int flags,...)
{ (void)path; (void)flags; return 7; }
int __wrap_flock(int fd,int operation)
{ (void)fd; (void)operation; return 0; }
int __wrap_close(int fd) { (void)fd; return 0; }
int __wrap_munmap(void *addr,size_t length)
{ (void)addr; (void)length; return 0; }
void *__wrap_mmap(void *addr,size_t length,int prot,int flags,int fd,off_t off)
{
    (void)addr; (void)length; (void)flags; (void)fd;
    if((uint64_t)off==0xff5e0000ULL) {
        assert(prot==PROT_READ); ++crl_reads; return crl;
    }
    assert((uint64_t)off==0xff020000ULL);
    ++iic_accesses; return iic;
}
static void run(uint32_t clock,uint32_t reset,unsigned expected_accesses,int expected_rc)
{
    char *args[]={"probe-test","--clock-confirmed","probe",NULL};
    crl[0x120/4]=clock; crl[0x238/4]=reset;
    iic_accesses=0; crl_reads=0;
    assert(probe_main(3,args)==expected_rc);
    assert(crl_reads==1);
    assert(iic_accesses==expected_accesses);
}
int main(void)
{
    run(0,0,0,2);
    run(0x01000500,0x0001fffc,0,2); /* Actual stalled-board reset state. */
    run(0,0x200,0,2);
    /* Passed preflight reaches IIC snapshot, then rejects uninitialized CR. */
    run(0x01000500,0x0001fdfc,1,1);
    puts("PASS: unsafe preflights never map/access IIC; safe preflight reaches IIC.");
    return 0;
}
