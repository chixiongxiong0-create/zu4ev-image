/* Early FSBL only. Board PS ref=33.333333 MHz; no PLL programming is done. */
#include <stdint.h>
#ifndef FSBL_IIC_CLOCK_TEST
#include <xil_io.h>
#include <xil_printf.h>
#include <sleep.h>
#endif
/* Masks from 2025.1 zynqmp_pmufw/src/crl_apb.h and UG1087 CRL_APB. */
int sc130_iic_clock_prepare(void) {
    const uintptr_t base=0xff5e0000u;
    uint32_t control=Xil_In32(base+0x20),fraction=Xil_In32(base+0x28);
    uint32_t lock=Xil_In32(base+0x40),ref=Xil_In32(base+0x120),reset=Xil_In32(base+0x238);
    /* PSS_REF -> integer IOPLL, FBDIV=90, DIV2=1: 33.333333*90/2=1500MHz.
     * Reject changed PLL source, bypass, reset, fraction or missing lock. */
    if((control&0x07717f09u)!=0x00015a00u || (fraction&0x80000000u) || !(lock&1u)) {
        xil_printf("IIC0_CLOCK_REFUSED pll=%08x frac=%08x lock=%08x\r\n",control,fraction,lock);return -1;
    }
    /* Divide IOPLL by 15 and 1 => 100MHz, matching XIicPs InputClockHz. */
    uint32_t next=(ref&~0x013f3f07u)|0x01010f00u;
    if(!(reset&0x200u) && ref!=next) {
        xil_printf("IIC0_CLOCK_REFUSED live controller with unexpected ref=%08x\r\n",ref);return -1;
    }
    if(ref!=next) Xil_Out32(base+0x120,next);
    if(Xil_In32(base+0x120)!=next || Xil_In32(base+0x238)!=reset) return -1;
    if(reset&0x200u) Xil_Out32(base+0x238,reset&~0x200u);
    if(Xil_In32(base+0x238)!=(reset&~0x200u)) return -1;
    usleep(10);
    xil_printf("IIC0_CLOCK_OK pll=%08x frac=%08x lock=%08x ref=%08x reset=%08x hz=100000000\r\n",
               control,fraction,lock,next,reset&~0x200u);
    return 0;
}
