#include <xiicps.h>
#include <xstatus.h>
#include <assert.h>
#include <stdio.h>

extern int sc130_sensor_mode_configureStandby(void);
extern int sc130_sensor_mode_verifyStandby(void);
extern int sc130_sensor_stream_enable(void);

static u8 registers[65536];
static unsigned selected;
static int fail_transfer;

int XIicPs_CfgInitialize(XIicPs *pIic, XIicPs_Config *pConfig, unsigned base)
{
    (void)pIic;
    (void)pConfig;
    (void)base;
    return 0;
} /* end of XIicPs_CfgInitialize */
int XIicPs_SetSClk(XIicPs *pIic, unsigned hz)
{
    (void)pIic;
    (void)hz;
    return 0;
} /* end of XIicPs_SetSClk */
int XIicPs_BusIsBusy(XIicPs *pIic)
{
    (void)pIic;
    return 0;
} /* end of XIicPs_BusIsBusy */
int XIicPs_SetOptions(XIicPs *pIic, unsigned options)
{
    (void)pIic;
    (void)options;
    return 0;
} /* end of XIicPs_SetOptions */
int XIicPs_ClearOptions(XIicPs *pIic, unsigned options)
{
    (void)pIic;
    (void)options;
    return 0;
} /* end of XIicPs_ClearOptions */
void XIicPs_Reset(XIicPs *pIic)
{
    (void)pIic;
} /* end of XIicPs_Reset */
void usleep(unsigned delay)
{
    (void)delay;
} /* end of usleep */
int xil_printf(const char *pFormat, ...)
{
    (void)pFormat;
    return 0;
} /* end of xil_printf */
int XIicPs_MasterSendPolled(XIicPs *pIic, u8 *pData, int length, unsigned address)
{
    (void)pIic;
    (void)address;
    if (fail_transfer)
    {
        return -1;
    }
    selected = ((unsigned)pData[0] << 8) | pData[1];
    if (3 == length)
    {
        registers[selected] = pData[2];
    }
    return XST_SUCCESS;
} /* end of XIicPs_MasterSendPolled */
int XIicPs_MasterRecvPolled(XIicPs *pIic, u8 *pData, int length, unsigned address)
{
    (void)pIic;
    (void)length;
    (void)address;
    if (fail_transfer)
    {
        return -1;
    }
    *pData = registers[selected];
    return XST_SUCCESS;
} /* end of XIicPs_MasterRecvPolled */

int main(void)
{
    assert(0 == sc130_sensor_mode_configureStandby());
    assert(0 == sc130_sensor_mode_verifyStandby());
    assert(0 == sc130_sensor_stream_enable());
    assert(1 == registers[0x0100]);
    fail_transfer = 1;
    assert(-1 == sc130_sensor_stream_enable());
    assert(-1 == sc130_sensor_mode_verifyStandby());
    puts("SENSOR_STATUS_PASS success and transfer failure");
    return 0;
} /* end of main */
