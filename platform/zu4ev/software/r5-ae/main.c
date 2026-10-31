#include <ae_core.h>
#include <xiicps.h>
#include <xscugic.h>
#include <xil_exception.h>
#include <xil_io.h>
#include <xpm_counter.h>
#include <xpseudo_asm.h>
#include <sleep.h>
#include <xstatus.h>
#include <stdint.h>
#include <string.h>

#define GPIO_BASE 0xFF0A0000U
#define ISP_BASE 0xA0040000U
#define ISP_AE_CONTROL 0x248U
#define IIC_BASE 0xFF020000U
#define SENSOR_ADDR 0x30U
/* irq_concat In4 on pl_ps_irq0[4]. Check against generated xparameters. */
#define FE_IRQ_ID 125U
#define GPIO_DATA5 0x74U
#define GPIO_DATA4 0x70U
#define GPIO_MASK3_LSW 0x18U
#define GPIO_DIR3 0x2C4U
#define GPIO_OEN3 0x2C8U
#define FE_ACK_BIT (1U << 13)
#define SNAP_BIT (1U << 2)
#define SNAP_INDEX_MASK (31U << 8)
#define LOG_CAP 512U
#define AE_SUCCESS 0
#define AE_FAILED (-1)

enum
{
    AE_OK,
    AE_ERR_IIC_INIT,
    AE_ERR_GIC_INIT,
    AE_ERR_SENSOR_READ,
    AE_ERR_SENSOR_MODE,
    AE_ERR_IIC_WRITE,
    AE_ERR_IIC_VERIFY,
    AE_ERR_CROSS_FRAME,
    AE_ERR_SOF_TIMEOUT,
    AE_ERR_NO_FRAMES,
    AE_ERR_STATS_TIMEOUT,
    AE_ERR_IRQ_ACK_TIMEOUT,
    AE_ERR_CONTROL_UNSUPPORTED
};

struct ae_record
{
    uint32_t fe_seq;
    uint32_t stats_seq;
    uint32_t stats_frame;
    uint32_t mean;
    uint32_t current_exposure;
    uint32_t current_gain;
    uint32_t sof_frame_before;
    uint32_t sof_frame_after;
    uint32_t proposed_code;
    uint32_t change_kind;
    uint32_t irq_tick;
    uint32_t iic_start_tick;
    uint32_t high_end_tick;
    uint32_t low_end_tick;
    uint32_t fe_to_sof_pl_cycles;
    uint32_t iic_hz;
    uint32_t fault;
};

/* Kept in R5 TCM for non-invasive JTAG inspection with the ELF symbol. */
volatile struct
{
    uint32_t magic;
    uint32_t version;
    uint32_t write_index;
    uint32_t fault;
    uint32_t irq_count;
    uint32_t last_fe_seq;
    uint32_t iic_hz;
    uint32_t dropped_fe;
} ae_log = {.magic = 0x41453552U, .version = 1U};
volatile struct ae_record ae_records[LOG_CAP];

static XIicPs iic;
static XScuGic gic;
static struct ae_core core;
static volatile uint32_t pending;
static volatile uint32_t irq_tick;
static volatile uint32_t irq_fe;
static uint16_t previous_raw_fe;
static uint32_t extended_fe;
static uint32_t have_raw_fe;
static uint32_t ack_state;
static uint32_t snap_state;

static uint32_t sc130_ae_timer_get(void)
{
    return Xpm_ReadCycleCounterVal();
} /* end of sc130_ae_timer_get */

static void sc130_ae_timer_init(void)
{
    uint32_t pmcr = mfcp(XREG_CP15_PERF_MONITOR_CTRL);
    mtcp(XREG_CP15_PERF_MONITOR_CTRL, pmcr | 0x5U);
    mtcp(XREG_CP15_COUNT_ENABLE_SET, 0x80000000U);
} /* end of sc130_ae_timer_init */

static void sc130_ae_gpio_writeMasked(uint32_t bits, uint32_t value)
{
    Xil_Out32(GPIO_BASE + GPIO_MASK3_LSW, ((~bits & 0xFFFFU) << 16) | (value & bits));
} /* end of sc130_ae_gpio_writeMasked */

static uint32_t sc130_ae_frame_readStatus(void)
{
    uint32_t a;
    uint32_t b;
    unsigned i;
    for (i = 0; i < 8U; ++i)
    {
        a = Xil_In32(GPIO_BASE + GPIO_DATA5);
        b = Xil_In32(GPIO_BASE + GPIO_DATA5);
        if (a == b)
        {
            return a;
        }
    }
    return b;
} /* end of sc130_ae_frame_readStatus */

static uint32_t sc130_ae_frame_decodeGray(uint32_t value)
{
    value ^= value >> 1;
    value ^= value >> 2;
    value ^= value >> 4;
    value ^= value >> 8;
    value ^= value >> 16;
    return value;
} /* end of sc130_ae_frame_decodeGray */

static uint32_t sc130_ae_frame_readSof(void)
{
    return sc130_ae_frame_decodeGray((sc130_ae_frame_readStatus() >> 16) & 0x3FFFU);
} /* end of sc130_ae_frame_readSof */

static uint16_t sc130_ae_frame_readFe(void)
{
    return (uint16_t)sc130_ae_frame_decodeGray(sc130_ae_frame_readStatus() & 0xFFFFU);
} /* end of sc130_ae_frame_readFe */

static uint32_t sc130_ae_snapshot_read(unsigned index)
{
    snap_state ^= SNAP_BIT;
    sc130_ae_gpio_writeMasked(SNAP_INDEX_MASK | SNAP_BIT, ((index & 31U) << 8) | snap_state);
    usleep(1);
    return Xil_In32(GPIO_BASE + GPIO_DATA4);
} /* end of sc130_ae_snapshot_read */

static uint64_t sc130_ae_snapshot_read64(unsigned low_index)
{
    uint32_t lo = sc130_ae_snapshot_read(low_index);
    uint32_t hi = sc130_ae_snapshot_read(low_index + 1U);
    return ((uint64_t)hi << 32) | lo;
} /* end of sc130_ae_snapshot_read64 */

static void sc130_ae_frame_handleIrq(void *pArg)
{
    uint32_t status;
    uint16_t raw_fe;
    unsigned i;
    (void)pArg;
    irq_tick = sc130_ae_timer_get();
    status = sc130_ae_frame_readStatus();
    raw_fe = (uint16_t)sc130_ae_frame_decodeGray(status & 0xFFFFU);
    if (!have_raw_fe)
    {
        extended_fe = raw_fe;
        have_raw_fe = 1;
    }
    else
    {
        extended_fe += (uint16_t)(raw_fe - previous_raw_fe);
    }
    previous_raw_fe = raw_fe;
    irq_fe = extended_fe;
    ++ae_log.irq_count;
    ae_log.last_fe_seq = irq_fe;
    ack_state ^= FE_ACK_BIT;
    sc130_ae_gpio_writeMasked(FE_ACK_BIT, ack_state);
    for (i = 0; i < 1000U && (sc130_ae_frame_readStatus() & 0x40000000U); ++i)
    {
    }
    if (1000U == i)
    {
        ae_log.fault = AE_ERR_IRQ_ACK_TIMEOUT;
        XScuGic_Disable(&gic, FE_IRQ_ID);
        return;
    }
    pending = 1U;
} /* end of sc130_ae_frame_handleIrq */

static int sc130_ae_iic_init(void)
{
    XIicPs_Config cfg = {0};
    cfg.BaseAddress = IIC_BASE;
    cfg.InputClockHz = 100000000U;
    if (XIicPs_CfgInitialize(&iic, &cfg, IIC_BASE) != XST_SUCCESS
        || XIicPs_SetSClk(&iic, 400000U) != XST_SUCCESS)
    {
        return AE_FAILED;
    }
    ae_log.iic_hz = XIicPs_GetSClk(&iic);
    return (ae_log.iic_hz <= 400000U && ae_log.iic_hz >= 100000U) ? AE_SUCCESS : AE_FAILED;
} /* end of sc130_ae_iic_init */

static int sc130_ae_iic_waitIdle(void)
{
    unsigned i;
    for (i = 0; i < 10000U; ++i)
    {
        if (!XIicPs_BusIsBusy(&iic))
        {
            return AE_SUCCESS;
        }
        usleep(10);
    }
    return AE_FAILED;
} /* end of sc130_ae_iic_waitIdle */

static int sc130_ae_sensor_writeReg(uint16_t reg, uint8_t value)
{
    uint8_t bytes[3] = {(uint8_t)(reg >> 8), (uint8_t)reg, value};
    if (AE_SUCCESS != sc130_ae_iic_waitIdle())
    {
        return AE_FAILED;
    }
    return (XST_SUCCESS == XIicPs_MasterSendPolled(&iic, bytes, 3, SENSOR_ADDR)) ? AE_SUCCESS
                                                                                 : AE_FAILED;
} /* end of sc130_ae_sensor_writeReg */

static int sc130_ae_sensor_readReg(uint16_t reg, uint8_t *pValue)
{
    uint8_t addr[2] = {(uint8_t)(reg >> 8), (uint8_t)reg};
    if (AE_SUCCESS != sc130_ae_iic_waitIdle())
    {
        return AE_FAILED;
    }
    XIicPs_SetOptions(&iic, XIICPS_REP_START_OPTION);
    if (XIicPs_MasterSendPolled(&iic, addr, 2, SENSOR_ADDR) != XST_SUCCESS)
    {
        XIicPs_ClearOptions(&iic, XIICPS_REP_START_OPTION);
        XIicPs_Reset(&iic);
        return AE_FAILED;
    }
    XIicPs_ClearOptions(&iic, XIICPS_REP_START_OPTION);
    return (XST_SUCCESS == XIicPs_MasterRecvPolled(&iic, pValue, 1, SENSOR_ADDR)) ? AE_SUCCESS
                                                                                  : AE_FAILED;
} /* end of sc130_ae_sensor_readReg */

static int sc130_ae_stats_read(uint32_t *pSeq, uint32_t *pFrame, uint32_t *pMean)
{
    uint32_t before;
    uint32_t after;
    uint32_t v0;
    uint32_t v1;
    unsigned i;
    if (Xil_In32(ISP_BASE + 0x200U) != 0x41455331U)
    {
        return AE_FAILED;
    }
    for (i = 0; i < 16U; ++i)
    {
        before = Xil_In32(ISP_BASE + 0x214U);
        v0 = Xil_In32(ISP_BASE + 0x210U);
        *pFrame = Xil_In32(ISP_BASE + 0x218U);
        *pMean = Xil_In32(ISP_BASE + 0x21CU);
        after = Xil_In32(ISP_BASE + 0x214U);
        v1 = Xil_In32(ISP_BASE + 0x210U);
        if (before == after && (v0 & v1 & 1U))
        {
            *pSeq = before;
            return AE_SUCCESS;
        }
    }
    return AE_FAILED;
} /* end of sc130_ae_stats_read */

static void sc130_ae_log_record(const struct ae_record *pRecord)
{
    volatile struct ae_record *pSlot = &ae_records[ae_log.write_index % LOG_CAP];
    *pSlot = *pRecord;
    ++ae_log.write_index;
} /* end of sc130_ae_log_record */

static void sc130_ae_fault_stop(unsigned code)
{
    ae_log.fault = code;
    Xil_ExceptionDisableMask(XIL_EXCEPTION_IRQ);
    for (;;)
    {
    }
} /* end of sc130_ae_fault_stop */

int main(void)
{
    XScuGic_Config *pGcfg;
    uint8_t vts_hi;
    uint8_t vts_lo;
    uint8_t exp_hi;
    uint8_t exp_lo;
    uint8_t gain_hi;
    uint8_t gain_lo;
    uint8_t mode;
    uint8_t verify;
    uint32_t last_fe = 0;
    uint32_t last_stats = 0;
    uint32_t stale_stats_frames = 0;
    uint32_t last_irq_activity;
    uint32_t fe;
    uint32_t t_irq;
    uint32_t seq;
    uint32_t frame;
    uint32_t mean;
    uint32_t sof;
    uint32_t pre_sof;
    uint64_t fe_time;
    uint64_t sof_time;
    unsigned i;
    struct ae_update next;
    enum ae_change change;
    struct ae_record r;
    sc130_ae_timer_init();
    if (0U == (Xil_In32(ISP_BASE + 0x08U) & 0x20U))
    {
        sc130_ae_fault_stop(AE_ERR_CONTROL_UNSUPPORTED);
    }
    Xil_Out32(GPIO_BASE + GPIO_DIR3,
              Xil_In32(GPIO_BASE + GPIO_DIR3) | FE_ACK_BIT | SNAP_BIT | SNAP_INDEX_MASK);
    Xil_Out32(GPIO_BASE + GPIO_OEN3,
              Xil_In32(GPIO_BASE + GPIO_OEN3) | FE_ACK_BIT | SNAP_BIT | SNAP_INDEX_MASK);
    sc130_ae_gpio_writeMasked(FE_ACK_BIT | SNAP_BIT | SNAP_INDEX_MASK, 0);
    if (AE_SUCCESS != sc130_ae_iic_init())
    {
        sc130_ae_fault_stop(AE_ERR_IIC_INIT);
    }
    if (AE_SUCCESS != sc130_ae_sensor_readReg(0x320EU, &vts_hi)
        || AE_SUCCESS != sc130_ae_sensor_readReg(0x320FU, &vts_lo)
        || AE_SUCCESS != sc130_ae_sensor_readReg(0x3E01U, &exp_hi)
        || AE_SUCCESS != sc130_ae_sensor_readReg(0x3E02U, &exp_lo)
        || AE_SUCCESS != sc130_ae_sensor_readReg(0x3E08U, &gain_hi)
        || AE_SUCCESS != sc130_ae_sensor_readReg(0x3E09U, &gain_lo)
        || AE_SUCCESS != sc130_ae_sensor_readReg(0x3E03U, &mode))
    {
        sc130_ae_fault_stop(AE_ERR_SENSOR_READ);
    }
    if ((gain_hi & 0xFCU) != 0U || gain_lo < 0x20U || gain_lo > 0x3FU)
    {
        sc130_ae_fault_stop(AE_ERR_SENSOR_MODE);
    }
    if (!(mode & 1U) && AE_SUCCESS != sc130_ae_sensor_writeReg(0x3E03U, mode | 1U))
    {
        sc130_ae_fault_stop(AE_ERR_SENSOR_MODE);
    }
    if (AE_SUCCESS != sc130_ae_sensor_readReg(0x3E03U, &verify) || !(verify & 1U))
    {
        sc130_ae_fault_stop(AE_ERR_SENSOR_MODE);
    }
    sc130_ae_core_init(
            &core, ((uint16_t)exp_hi << 8) | exp_lo, ((uint16_t)vts_hi << 8) | vts_lo, gain_lo);
    pGcfg = XScuGic_LookupConfig(0xF9000000U);
    if (!pGcfg || XScuGic_CfgInitialize(&gic, pGcfg, pGcfg->CpuBaseAddress) != XST_SUCCESS
        || XScuGic_Connect(&gic, FE_IRQ_ID, sc130_ae_frame_handleIrq, 0) != XST_SUCCESS)
    {
        sc130_ae_fault_stop(AE_ERR_GIC_INIT);
    }
    XScuGic_SetPriorityTriggerType(&gic, FE_IRQ_ID, 0xA0U, 0x1U);
    XScuGic_Enable(&gic, FE_IRQ_ID);
    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(
            XIL_EXCEPTION_ID_IRQ_INT, (Xil_ExceptionHandler)XScuGic_InterruptHandler, &gic);
    Xil_ExceptionEnable();
    /* A pending level interrupt is acknowledged only by sc130_ae_frame_handleIrq(). */
    last_irq_activity = sc130_ae_timer_get();
    for (;;)
    {
        seq = 0;
        frame = 0;
        mean = 0;
        memset(&r, 0, sizeof(r));
        if (AE_ERR_IRQ_ACK_TIMEOUT == ae_log.fault)
        {
            sc130_ae_fault_stop(AE_ERR_IRQ_ACK_TIMEOUT);
        }
        if (!pending)
        {
            if ((uint32_t)(sc130_ae_timer_get() - last_irq_activity) > 525000000U)
            {
                sc130_ae_fault_stop(AE_ERR_NO_FRAMES);
            }
            continue;
        }
        Xil_ExceptionDisableMask(XIL_EXCEPTION_IRQ);
        pending = 0;
        fe = irq_fe;
        t_irq = irq_tick;
        Xil_ExceptionEnableMask(XIL_EXCEPTION_IRQ);
        last_irq_activity = sc130_ae_timer_get();
        if (last_fe && (uint32_t)(fe - last_fe) > 1U)
        {
            ae_log.dropped_fe += (uint32_t)(fe - last_fe) - 1U;
        }
        last_fe = fe;
        /* Stop proposing sensor changes while disabled; keep servicing FE. */
        if (0U == (Xil_In32(ISP_BASE + ISP_AE_CONTROL) & 1U))
        {
            stale_stats_frames = 0;
            continue;
        }
        if (AE_SUCCESS != sc130_ae_stats_read(&seq, &frame, &mean) || !seq || seq == last_stats)
        {
            if (++stale_stats_frames > 120U)
            {
                sc130_ae_fault_stop(AE_ERR_STATS_TIMEOUT);
            }
            continue;
        }
        last_stats = seq;
        stale_stats_frames = 0;
        r.fe_seq = fe;
        r.stats_seq = seq;
        r.stats_frame = frame;
        r.mean = mean;
        r.current_exposure = core.exposure;
        r.current_gain = core.fine_gain;
        r.irq_tick = t_irq;
        r.iic_hz = ae_log.iic_hz;
        change = sc130_ae_core_propose(&core, fe, seq, mean, 1, &next);
        if (AE_CHANGE_NONE == change)
        {
            sc130_ae_log_record(&r);
            continue;
        }
        r.proposed_code = AE_CHANGE_EXPOSURE == change ? next.exposure : next.fine_gain;
        r.change_kind = change;
        /* FE can be close to the next SOF. Begin both writes just after SOF. */
        sof = sc130_ae_frame_readSof();
        {
            pre_sof = sof;
            for (i = 0; i < 300U && sof == pre_sof; ++i)
            {
                usleep(50);
                sof = sc130_ae_frame_readSof();
            }
            if (sof == pre_sof)
            {
                r.fault = AE_ERR_SOF_TIMEOUT;
                sc130_ae_log_record(&r);
                sc130_ae_fault_stop(AE_ERR_SOF_TIMEOUT);
            }
        }
        r.sof_frame_before = sof;
        {
            fe_time = sc130_ae_snapshot_read64(18U);
            sof_time = sc130_ae_snapshot_read64(20U);
            r.fe_to_sof_pl_cycles = (uint32_t)(sof_time - fe_time);
        }
        if (sc130_ae_frame_readFe() != (uint16_t)fe
            || 0U == (Xil_In32(ISP_BASE + ISP_AE_CONTROL) & 1U))
        {
            r.change_kind = AE_CHANGE_NONE;
            r.proposed_code = 0;
            sc130_ae_log_record(&r);
            continue;
        }
        r.iic_start_tick = sc130_ae_timer_get();
        if (AE_SUCCESS
            != sc130_ae_sensor_writeReg(AE_CHANGE_EXPOSURE == change ? 0x3E01U : 0x3E09U,
                                        AE_CHANGE_EXPOSURE == change ? (uint8_t)(next.exposure >> 8)
                                                                     : next.fine_gain))
        {
            r.fault = AE_ERR_IIC_WRITE;
            sc130_ae_log_record(&r);
            sc130_ae_fault_stop(AE_ERR_IIC_WRITE);
        }
        r.high_end_tick = sc130_ae_timer_get();
        if (AE_CHANGE_EXPOSURE == change)
        {
            if (AE_SUCCESS != sc130_ae_sensor_writeReg(0x3E02U, (uint8_t)next.exposure))
            {
                r.fault = AE_ERR_IIC_WRITE;
                sc130_ae_log_record(&r);
                sc130_ae_fault_stop(AE_ERR_IIC_WRITE);
            }
        }
        r.low_end_tick = sc130_ae_timer_get();
        r.sof_frame_after = sc130_ae_frame_readSof();
        if (r.sof_frame_after != r.sof_frame_before || sc130_ae_frame_readFe() != (uint16_t)fe)
        {
            r.fault = AE_ERR_CROSS_FRAME;
            sc130_ae_log_record(&r);
            sc130_ae_fault_stop(AE_ERR_CROSS_FRAME);
        }
        if (AE_CHANGE_EXPOSURE == change
            && (AE_SUCCESS != sc130_ae_sensor_readReg(0x3E01U, &verify)
                || verify != (uint8_t)(next.exposure >> 8)
                || AE_SUCCESS != sc130_ae_sensor_readReg(0x3E02U, &verify)
                || verify != (uint8_t)next.exposure))
        {
            r.fault = AE_ERR_IIC_VERIFY;
            sc130_ae_log_record(&r);
            sc130_ae_fault_stop(AE_ERR_IIC_VERIFY);
        }
        if (AE_CHANGE_FINE_GAIN == change
            && (AE_SUCCESS != sc130_ae_sensor_readReg(0x3E09U, &verify)
                || verify != next.fine_gain))
        {
            r.fault = AE_ERR_IIC_VERIFY;
            sc130_ae_log_record(&r);
            sc130_ae_fault_stop(AE_ERR_IIC_VERIFY);
        }
        sc130_ae_core_commit(&core, fe, &next);
        sc130_ae_log_record(&r);
    }
} /* end of main */
