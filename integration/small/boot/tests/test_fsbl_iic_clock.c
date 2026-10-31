#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
static uint32_t registers[1024],saved[1024];
static uint32_t read_register(uintptr_t addr) {assert(addr>=0xff5e0000u && addr<0xff5e1000u);return registers[(addr-0xff5e0000u)/4];}
static void write_register(uintptr_t addr,uint32_t value) {assert(addr==0xff5e0120u || addr==0xff5e0238u);registers[(addr-0xff5e0000u)/4]=value;}
#define FSBL_IIC_CLOCK_TEST
#define Xil_In32 read_register
#define Xil_Out32 write_register
#define xil_printf printf
#define usleep(x) ((void)(x))
#include "../sc130_iic_clock.c"
static void setup(void) {memset(registers,0,sizeof(registers));registers[0x20/4]=0x15a00;registers[0x40/4]=0x1b;registers[0x120/4]=0x1000500;registers[0x238/4]=0x1fffc;}
static void reject(void) {memcpy(saved,registers,sizeof(saved));assert(sc130_iic_clock_prepare()!=0);assert(!memcmp(saved,registers,sizeof(saved)));}
int main(void) {
    setup();memcpy(saved,registers,sizeof(saved));assert(!sc130_iic_clock_prepare());
    saved[0x120/4]=0x01010f00;saved[0x238/4]=0x1fdfc;assert(!memcmp(saved,registers,sizeof(saved)));
    assert(!sc130_iic_clock_prepare());assert(!memcmp(saved,registers,sizeof(saved)));
    setup();registers[0x20/4]=0x15900;reject();
    setup();registers[0x20/4]|=8;reject();
    setup();registers[0x20/4]&=~0x10000u;reject();
    setup();registers[0x20/4]|=1u<<20;reject();
    setup();registers[0x28/4]=1u<<31;reject();
    setup();registers[0x40/4]&=~1u;reject();
    setup();registers[0x238/4]&=~0x200u;reject();
    puts("FSBL IOPLL guards, 1500/15=100MHz, reset/readback, unrelated-bit preservation: PASS");
    return 0;
}
