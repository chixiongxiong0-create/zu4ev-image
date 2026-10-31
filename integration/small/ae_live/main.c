#include "ae_platform.h"
#include <ae_core.h>
#include <stdint.h>
#include <string.h>

#define GPIO_BASE AE_GPIO_BASE
#define ISP_BASE AE_ISP_BASE
#define ISP_AE_CONTROL 0x248U
#define IIC_BASE AE_IIC_BASE
#define SENSOR_ADDR 0x30U
/* irq_concat In4 on pl_ps_irq0[4]. Check against generated xparameters. */
#define FE_IRQ_ID AE_FE_IRQ_ID
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



static struct ae_core core;
static volatile uint32_t pending;
static volatile uint32_t irq_tick;
static volatile uint32_t irq_fe;
static uint16_t previous_raw_fe;
static uint32_t extended_fe;
static uint32_t have_raw_fe;
static uint32_t ack_state;
static uint32_t snap_state;

static uint32_t sc130_ae_timer_get(void) { return ae_platform_ticks(); }
static void sc130_ae_timer_init(void) { ae_platform_timer_init(); }

static void sc130_ae_gpio_writeMasked(uint32_t bits, uint32_t value)
{
    ae_platform_write32(GPIO_BASE + GPIO_MASK3_LSW, ((~bits & 0xFFFFU) << 16) | (value & bits));
} /* end of sc130_ae_gpio_writeMasked */

static uint32_t sc130_ae_frame_readStatus(void)
{
    uint32_t a;
    uint32_t b;
    unsigned i;
    for (i = 0; i < 8U; ++i)
    {
        a = ae_platform_read32(GPIO_BASE + GPIO_DATA5);
        b = ae_platform_read32(GPIO_BASE + GPIO_DATA5);
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
    ae_platform_delay_us(1);
    return ae_platform_read32(GPIO_BASE + GPIO_DATA4);
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
        ae_platform_irq_disable();
        return;
    }
    pending = 1U;
} /* end of sc130_ae_frame_handleIrq */

static int sc130_ae_iic_init(void)
{
    if (ae_platform_iic_init(400000U, &ae_log.iic_hz)) return AE_FAILED;
    return ae_log.iic_hz >= 100000U && ae_log.iic_hz <= 400000U ? AE_SUCCESS : AE_FAILED;
}
static int sc130_ae_sensor_writeReg(uint16_t reg, uint8_t value)
{ return ae_platform_sensor_write(SENSOR_ADDR, reg, value); }
static int sc130_ae_sensor_readReg(uint16_t reg, uint8_t *value)
{ return ae_platform_sensor_read(SENSOR_ADDR, reg, value); }

static int sc130_ae_stats_read(uint32_t *pSeq, uint32_t *pFrame, uint32_t *pMean)
{
    uint32_t before;
    uint32_t after;
    uint32_t v0;
    uint32_t v1;
    unsigned i;
    if (ae_platform_read32(ISP_BASE + 0x200U) != 0x41455331U)
    {
        return AE_FAILED;
    }
    for (i = 0; i < 16U; ++i)
    {
        before = ae_platform_read32(ISP_BASE + 0x214U);
        v0 = ae_platform_read32(ISP_BASE + 0x210U);
        *pFrame = ae_platform_read32(ISP_BASE + 0x218U);
        *pMean = ae_platform_read32(ISP_BASE + 0x21CU);
        after = ae_platform_read32(ISP_BASE + 0x214U);
        v1 = ae_platform_read32(ISP_BASE + 0x210U);
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
    ae_platform_irq_disable();
    for (;;)
    {
    }
} /* end of sc130_ae_fault_stop */

int main(void)
{

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
    if (0U == (ae_platform_read32(ISP_BASE + 0x08U) & 0x20U))
    {
        sc130_ae_fault_stop(AE_ERR_CONTROL_UNSUPPORTED);
    }
    ae_platform_write32(GPIO_BASE + GPIO_DIR3,
              ae_platform_read32(GPIO_BASE + GPIO_DIR3) | FE_ACK_BIT | SNAP_BIT | SNAP_INDEX_MASK);
    ae_platform_write32(GPIO_BASE + GPIO_OEN3,
              ae_platform_read32(GPIO_BASE + GPIO_OEN3) | FE_ACK_BIT | SNAP_BIT | SNAP_INDEX_MASK);
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
    if (ae_platform_irq_init(sc130_ae_frame_handleIrq, 0))
        sc130_ae_fault_stop(AE_ERR_GIC_INIT);
    ae_platform_irq_enable();
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
            if ((uint32_t)(sc130_ae_timer_get() - last_irq_activity) > AE_NO_FRAME_TIMEOUT_TICKS)
            {
                sc130_ae_fault_stop(AE_ERR_NO_FRAMES);
            }
            continue;
        }
        ae_platform_irq_disable();
        pending = 0;
        fe = irq_fe;
        t_irq = irq_tick;
        ae_platform_irq_enable();
        last_irq_activity = sc130_ae_timer_get();
        if (last_fe && (uint32_t)(fe - last_fe) > 1U)
        {
            ae_log.dropped_fe += (uint32_t)(fe - last_fe) - 1U;
        }
        last_fe = fe;
        /* Stop proposing sensor changes while disabled; keep servicing FE. */
        if (0U == (ae_platform_read32(ISP_BASE + ISP_AE_CONTROL) & 1U))
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
                ae_platform_delay_us(50);
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
            || 0U == (ae_platform_read32(ISP_BASE + ISP_AE_CONTROL) & 1U))
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


