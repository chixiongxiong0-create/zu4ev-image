#define IIC_PREPARE_TEST
#include "../ibex_iic_prepare.c"
#include <assert.h>

static uint32_t crl[1024], isp[16384], before[1024];
static void setup(void) {
    memset(crl,0,sizeof(crl));memset(isp,0,sizeof(isp));
    isp[0]=0x49535031;crl[0x120/4]=0x01000500;
    crl[0x20/4]=0x00015a00;crl[0x40/4]=0x1b;
    crl[0x238/4]=0x0001fffc;
}
static void rejected(void) {
    memcpy(before,crl,sizeof(crl));
    assert(prepare_iic(crl,isp)<0);
    assert(!memcmp(before,crl,sizeof(crl)));
}
int main(void) {
    setup();memcpy(before,crl,sizeof(crl));assert(!prepare_iic(crl,isp));
    assert(crl[0x238/4]==0x0001fdfc);
    before[0x238/4]&=~0x200u;assert(!memcmp(before,crl,sizeof(crl)));
    assert(!prepare_iic(crl,isp));assert(!memcmp(before,crl,sizeof(crl)));
    setup();isp[0]=0;rejected();
    setup();isp[0xff00/4]=1;rejected();
    setup();isp[0xff08/4]=1;rejected();
    setup();crl[0x120/4]&=~(1u<<24);rejected();
    setup();crl[0x120/4]|=2;rejected();
    setup();crl[0x120/4]&=~0x3f00u;rejected();
    setup();crl[0x40/4]&=~1u;rejected();
    setup();crl[0x20/4]|=8;rejected();
    setup();crl[0x20/4]|=1;rejected();
    puts("IIC boot guard, only reset-bit release, clock/PLL/owner refusal: PASS");
    return 0;
}
