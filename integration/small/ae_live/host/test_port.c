/* Compile as one translation unit to inspect the port's private helpers. */
#include <assert.h>
#include <stdio.h>
#define main ae_firmware_main
#include "../main.c"
#undef main

static uint32_t status_word, stats_sequence = 7, ack_stuck;
static uint32_t gpio_mask_write, ticks, irq_disabled;
static uint8_t sensor[65536];
static unsigned write_failure, read_failure;
uint32_t ae_platform_read32(uint32_t address)
{
    if (address == AE_GPIO_BASE + GPIO_DATA5) return status_word;
    if (address == AE_ISP_BASE + 0x200U) return 0x41455331U;
    if (address == AE_ISP_BASE + 0x210U) return 1;
    if (address == AE_ISP_BASE + 0x214U) return stats_sequence;
    if (address == AE_ISP_BASE + 0x218U) return 9;
    if (address == AE_ISP_BASE + 0x21cU) return 96;
    return 0;
}
void ae_platform_write32(uint32_t address, uint32_t value)
{
    if (address == AE_GPIO_BASE + GPIO_MASK3_LSW) {
        gpio_mask_write = value;
        if (!ack_stuck) status_word &= ~0x40000000U;
    }
}
uint32_t ae_platform_ticks(void) { return ++ticks; }
void ae_platform_timer_init(void) { ticks = 0; }
void ae_platform_delay_us(uint32_t us) { ticks += us; }
int ae_platform_iic_init(uint32_t hz, volatile uint32_t *actual)
{ *actual = hz; return 0; }
int ae_platform_sensor_write(uint8_t address, uint16_t reg, uint8_t value)
{ assert(address == 0x30); if (write_failure) return -1; sensor[reg] = value; return 0; }
int ae_platform_sensor_read(uint8_t address, uint16_t reg, uint8_t *value)
{ assert(address == 0x30); if (read_failure) return -1; *value = sensor[reg]; return 0; }
int ae_platform_irq_init(void (*handler)(void *), void *argument)
{ (void)handler; (void)argument; return 0; }
void ae_platform_irq_disable(void) { irq_disabled = 1; }
void ae_platform_irq_enable(void) { irq_disabled = 0; }
static uint32_t gray(uint32_t x) { return x ^ (x >> 1); }
int main(void)
{
    uint32_t seq, frame, mean;
    uint8_t value;
    struct ae_record record = {0};
    assert(sc130_ae_iic_init() == 0 && ae_log.iic_hz == 400000);
    assert(sc130_ae_sensor_writeReg(0x3e09, 0x28) == 0);
    assert(sc130_ae_sensor_readReg(0x3e09, &value) == 0 && value == 0x28);
    write_failure = 1;
    assert(sc130_ae_sensor_writeReg(0x3e09, 0x29) == -1);
    assert(sensor[0x3e09] == 0x28);
    read_failure = 1;
    assert(sc130_ae_sensor_readReg(0x3e09, &value) == -1);
    assert(sc130_ae_stats_read(&seq, &frame, &mean) == 0);
    assert(seq == 7 && frame == 9 && mean == 96);
    status_word = 0x40000000U | gray(65535);
    sc130_ae_frame_handleIrq(0);
    assert(irq_fe == 65535 && pending && ae_log.irq_count == 1);
    assert((gpio_mask_write & FE_ACK_BIT) != 0);
    status_word = 0x40000000U | gray(0);
    sc130_ae_frame_handleIrq(0);
    assert(irq_fe == 65536 && ae_log.irq_count == 2);
    ack_stuck = 1;
    status_word = 0x40000000U | gray(1);
    sc130_ae_frame_handleIrq(0);
    assert(ae_log.fault == AE_ERR_IRQ_ACK_TIMEOUT && irq_disabled);
    ae_log.write_index = LOG_CAP;
    record.mean = 77;
    sc130_ae_log_record(&record);
    assert(ae_records[0].mean == 77 && ae_log.write_index == LOG_CAP + 1);
    puts("AE live helper contract checks passed");
    return 0;
}
