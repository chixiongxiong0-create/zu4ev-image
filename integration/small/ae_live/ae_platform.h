#ifndef AE_PLATFORM_H
#define AE_PLATFORM_H
#include <stdint.h>
/* Intentionally mandatory: supplied only after the hardware map is implemented. */
#include "ae_board_config.h"
uint32_t ae_platform_read32(uint32_t address);
void ae_platform_write32(uint32_t address, uint32_t value);
uint32_t ae_platform_ticks(void);
void ae_platform_timer_init(void);
void ae_platform_delay_us(uint32_t microseconds);
int ae_platform_iic_init(uint32_t requested_hz, volatile uint32_t *actual_hz);
int ae_platform_sensor_write(uint8_t address, uint16_t reg, uint8_t value);
int ae_platform_sensor_read(uint8_t address, uint16_t reg, uint8_t *value);
int ae_platform_irq_init(void (*handler)(void *), void *argument);
void ae_platform_irq_disable(void);
void ae_platform_irq_enable(void);
#endif
