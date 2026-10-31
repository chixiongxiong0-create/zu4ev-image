/* Exercise the real bit-bang edge timeout without touching /dev/mem. */
#define main sensorctl_program_main
#include "sensorctl.c"
#undef main
#include <assert.h>
int main(void) {
  uint32_t backing[1024] = {0};
  gpio = backing;
  backing[0x2c8 / 4] = 0xa5a50003U;
  delay_us = 10;
  assert(clock_high() == 0);
  assert(backing[0x2c8 / 4] == 0xa5a50002U);
  backing[0x6c / 4] = 1;
  assert(clock_high() == 1);
  backing[0x6c / 4] = 3;
  assert(send_byte(0x60) == 0); /* Released SDA is high: NACK. */
  backing[0x6c / 4] = 1;
  assert(send_byte(0x60) == 1); /* SDA is low: ACK. */
  puts("PASS bounded stretch timeout and real ACK/NACK sampling");
  return 0;
}
