#include <xfsbl_hw.h>
#include <xfsbl_hooks.h>
#include <xil_printf.h>
#include <camera_pipeline.h>
extern int sc130_power_up(unsigned mask);
extern int sc130_sensor_mode_configureStandby(void);
extern int sc130_sensor_mode_verifyStandby(void);
extern int sc130_sensor_stream_enable(void);
static unsigned Sc130PlLoads;
static unsigned Sc130Ready;
u32 Sc130AfterBitstream(void)
{
    ++Sc130PlLoads;
    xil_printf("SINGLE_PL count=%d\r\n", Sc130PlLoads);
    if (Sc130PlLoads != 1U || !sc130_power_up(0x00800000U))
    {
        return XFSBL_FAILURE;
    }
    if (!camera_pipeline_hold() || 0 != sc130_sensor_mode_configureStandby()
        || 0 != sc130_sensor_mode_verifyStandby() || !camera_pipeline_start()
        || 0 != sc130_sensor_stream_enable())
    {
        return XFSBL_FAILURE;
    }
    Sc130Ready = 1;
    xil_printf("SENSOR_READY SINGLE_PL count=1\r\n");
    return XFSBL_SUCCESS;
} /* end of Sc130AfterBitstream */
u32 Sc130BeforeHandoff(void)
{
    return (1U == Sc130PlLoads && Sc130Ready) ? XFSBL_SUCCESS : XFSBL_FAILURE;
} /* end of Sc130BeforeHandoff */
