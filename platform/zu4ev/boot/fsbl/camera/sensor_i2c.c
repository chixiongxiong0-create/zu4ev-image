#include <xiicps.h>
#include <xil_printf.h>
#include <sleep.h>
#include <xstatus.h>
#include <sc130_table.h>

#define SENSOR_IIC_BASE 0xff020000U
#define SENSOR_ADDR 0x30U
#define SENSOR_SUCCESS 0
#define SENSOR_FAILED (-1)

static XIicPs iic;
static int iic_ready;

static int sc130_sensor_iic_init(void)
{
    XIicPs_Config cfg = {0};
    cfg.BaseAddress = SENSOR_IIC_BASE;
    cfg.InputClockHz = 100000000U;
    if (XIicPs_CfgInitialize(&iic, &cfg, SENSOR_IIC_BASE) != XST_SUCCESS
        || XIicPs_SetSClk(&iic, 400000U) != XST_SUCCESS)
    {
        return SENSOR_FAILED;
    }
    iic_ready = 1;
    return SENSOR_SUCCESS;
} /* end of sc130_sensor_iic_init */

static int sc130_sensor_iic_waitIdle(void)
{
    unsigned i;
    for (i = 0; i < 10000U; ++i)
    {
        if (!XIicPs_BusIsBusy(&iic))
        {
            return SENSOR_SUCCESS;
        }
        usleep(10);
    }
    return SENSOR_FAILED;
} /* end of sc130_sensor_iic_waitIdle */

static int sc130_sensor_reg_read(unsigned reg, unsigned *pValue)
{
    u8 addr[2] = {(u8)(reg >> 8), (u8)reg};
    u8 data = 0;
    if (!iic_ready || SENSOR_SUCCESS != sc130_sensor_iic_waitIdle())
    {
        return SENSOR_FAILED;
    }
    XIicPs_SetOptions(&iic, XIICPS_REP_START_OPTION);
    if (XIicPs_MasterSendPolled(&iic, addr, 2, SENSOR_ADDR) != XST_SUCCESS)
    {
        XIicPs_ClearOptions(&iic, XIICPS_REP_START_OPTION);
        XIicPs_Reset(&iic);
        return SENSOR_FAILED;
    }
    XIicPs_ClearOptions(&iic, XIICPS_REP_START_OPTION);
    if (XIicPs_MasterRecvPolled(&iic, &data, 1, SENSOR_ADDR) != XST_SUCCESS)
    {
        return SENSOR_FAILED;
    }
    *pValue = data;
    return SENSOR_SUCCESS;
} /* end of sc130_sensor_reg_read */

static int sc130_sensor_reg_write(unsigned reg, unsigned value)
{
    u8 bytes[3] = {(u8)(reg >> 8), (u8)reg, (u8)value};
    unsigned reset = 255;
    unsigned stream = 255;
    int ok = iic_ready && SENSOR_SUCCESS == sc130_sensor_iic_waitIdle()
             && XST_SUCCESS == XIicPs_MasterSendPolled(&iic, bytes, 3, SENSOR_ADDR);
    if (!ok && 0x0103 == reg && 1 == value)
    {
        usleep(10000);
        ok = SENSOR_SUCCESS == sc130_sensor_reg_read(0x0103, &reset)
             && SENSOR_SUCCESS == sc130_sensor_reg_read(0x0100, &stream) && 0 == reset
             && (0 == stream || 1 == stream);
    }
    if (!ok)
    {
        xil_printf("I2C_WRITE_FAIL reg=%04x\r\n", reg);
    }
    return ok ? SENSOR_SUCCESS : SENSOR_FAILED;
} /* end of sc130_sensor_reg_write */
#ifndef DP_SENSOR_HTS
#  define DP_SENSOR_HTS 780U
#endif
#ifndef DP_SENSOR_VTS
#  define DP_SENSOR_VTS 529U
#endif

int sc130_sensor_mode_configureStandby(void)
{
    unsigned id0;
    unsigned id1;
    unsigned count;
    unsigned i;
    unsigned value;
    unsigned lanes;
    unsigned raw;
    unsigned clock;
    unsigned hts_hi;
    unsigned hts_lo;
    unsigned vts_hi;
    unsigned vts_lo;
    if (SENSOR_SUCCESS != sc130_sensor_iic_init() || SENSOR_SUCCESS != sc130_sensor_iic_waitIdle())
    {
        xil_printf("I2C_BUS_NOT_IDLE\r\n");
        return SENSOR_FAILED;
    }
    if (SENSOR_SUCCESS != sc130_sensor_reg_read(0x3107, &id0)
        || SENSOR_SUCCESS != sc130_sensor_reg_read(0x3108, &id1))
    {
        xil_printf("SENSOR_READ_FAIL\r\n");
        return SENSOR_FAILED;
    }
    xil_printf("SENSOR_ID_CANDIDATES %02x %02x\r\n", id0, id1);
    count = sizeof(sensor_table) / sizeof(sensor_table[0]);
    for (i = 0; i < count; ++i)
    {
        value = sensor_table[i].value;
        switch (sensor_table[i].address)
        {
        case 0x320c:
            value = DP_SENSOR_HTS >> 8;
            break;
        case 0x320d:
            value = DP_SENSOR_HTS & 255;
            break;
        case 0x320e:
            value = DP_SENSOR_VTS >> 8;
            break;
        case 0x320f:
            value = DP_SENSOR_VTS & 255;
            break;
        default:
            break;
        }
        if (SENSOR_SUCCESS != sc130_sensor_reg_write(sensor_table[i].address, value))
        {
            (void)sc130_sensor_reg_write(0x0100, 0);
            return SENSOR_FAILED;
        }
        if (sensor_table[i].delay_ms)
        {
            usleep(1000U * sensor_table[i].delay_ms);
        }
    }
    if (SENSOR_SUCCESS != sc130_sensor_reg_write(0x0100, 0))
    {
        return SENSOR_FAILED;
    }
    if (SENSOR_SUCCESS != sc130_sensor_reg_read(0x3018, &lanes)
        || SENSOR_SUCCESS != sc130_sensor_reg_read(0x3031, &raw)
        || SENSOR_SUCCESS != sc130_sensor_reg_read(0x3030, &clock)
        || SENSOR_SUCCESS != sc130_sensor_reg_read(0x320c, &hts_hi)
        || SENSOR_SUCCESS != sc130_sensor_reg_read(0x320d, &hts_lo)
        || SENSOR_SUCCESS != sc130_sensor_reg_read(0x320e, &vts_hi)
        || SENSOR_SUCCESS != sc130_sensor_reg_read(0x320f, &vts_lo))
    {
        return SENSOR_FAILED;
    }
    if (lanes != 0x30 || raw != 0x0a || clock != 0x02 || ((hts_hi << 8) | hts_lo) != DP_SENSOR_HTS
        || ((vts_hi << 8) | vts_lo) != DP_SENSOR_VTS)
    {
        xil_printf("SENSOR_MODE_MISMATCH lanes=%02x raw=%02x hts=%d vts=%d\r\n",
                   lanes,
                   raw,
                   (hts_hi << 8) | hts_lo,
                   (vts_hi << 8) | vts_lo);
        return SENSOR_FAILED;
    }
    xil_printf("SENSOR_MODE_OK clock3030=%02x HTS=%d VTS=%d\r\n",
               clock,
               (hts_hi << 8) | hts_lo,
               (vts_hi << 8) | vts_lo);
#ifdef DP_SENSOR_PATTERN
    /* SC130GS application guide V1.9, p28 table 4-12. Diagnostic only. */
    if (SENSOR_SUCCESS != sc130_sensor_reg_write(0x4501, 0xc8)
        || SENSOR_SUCCESS != sc130_sensor_reg_write(0x3400, 0x52)
        || SENSOR_SUCCESS != sc130_sensor_reg_write(0x5001, 0x04))
    {
        return SENSOR_FAILED;
    }
    xil_printf("SENSOR_INCREMENTAL_PATTERN\r\n");
#endif
    xil_printf("SENSOR_STANDBY_READY writes=%d\r\n", count);
    return SENSOR_SUCCESS;
} /* end of sc130_sensor_mode_configureStandby */

int sc130_sensor_stream_enable(void)
{
    return sc130_sensor_reg_write(0x0100, 1);
} /* end of sc130_sensor_stream_enable */

int sc130_sensor_mode_verifyStandby(void)
{
    unsigned i;
    unsigned value;
    const unsigned regs[] = {0x0100,
                             0x3018,
                             0x3030,
                             0x3031,
                             0x3208,
                             0x3209,
                             0x320a,
                             0x320b,
                             0x320c,
                             0x320d,
                             0x320e,
                             0x320f};
    const unsigned expected[] = {0,
                                 0x30,
                                 2,
                                 0x0a,
                                 5,
                                 0,
                                 4,
                                 0,
                                 DP_SENSOR_HTS >> 8,
                                 DP_SENSOR_HTS & 255,
                                 DP_SENSOR_VTS >> 8,
                                 DP_SENSOR_VTS & 255};
    for (i = 0; i < sizeof(regs) / sizeof(regs[0]); ++i)
    {
        if (SENSOR_SUCCESS != sc130_sensor_reg_read(regs[i], &value) || value != expected[i])
        {
            xil_printf("SENSOR_STANDBY_VERIFY_FAIL reg=%04x\r\n", regs[i]);
            return SENSOR_FAILED;
        }
    }
    xil_printf("SENSOR_STANDBY_VERIFY_OK\r\n");
    return SENSOR_SUCCESS;
} /* end of sc130_sensor_mode_verifyStandby */
