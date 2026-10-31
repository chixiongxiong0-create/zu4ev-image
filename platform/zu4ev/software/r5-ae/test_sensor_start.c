#include <xfsbl_hw.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

extern u32 Sc130AfterBitstream(void);
extern u32 Sc130BeforeHandoff(void);
static int fail_step;
static int calls;
int xil_printf(const char *pFormat, ...)
{
    (void)pFormat;
    return 0;
} /* end of xil_printf */
int sc130_power_up(unsigned mask)
{
    (void)mask;
    return 1;
} /* end of sc130_power_up */
int camera_pipeline_hold(void)
{
    return 1;
} /* end of camera_pipeline_hold */
int camera_pipeline_start(void)
{
    return 1;
} /* end of camera_pipeline_start */
int sc130_sensor_mode_configureStandby(void)
{
    ++calls;
    return 1 == fail_step ? -1 : 0;
} /* end of sc130_sensor_mode_configureStandby */
int sc130_sensor_mode_verifyStandby(void)
{
    ++calls;
    return 2 == fail_step ? -1 : 0;
} /* end of sc130_sensor_mode_verifyStandby */
int sc130_sensor_stream_enable(void)
{
    ++calls;
    return 3 == fail_step ? -1 : 0;
} /* end of sc130_sensor_stream_enable */
int main(int argc, char **ppArgv)
{
    fail_step = argc > 1 ? atoi(ppArgv[1]) : 0;
    if (0 == fail_step)
    {
        assert(XFSBL_SUCCESS == Sc130AfterBitstream());
        assert(XFSBL_SUCCESS == Sc130BeforeHandoff());
        assert(3 == calls);
    }
    else
    {
        assert(XFSBL_FAILURE == Sc130AfterBitstream());
        assert(XFSBL_FAILURE == Sc130BeforeHandoff());
        assert(fail_step == calls);
    }
    puts("SENSOR_START_STATUS_PASS");
    return 0;
} /* end of main */
