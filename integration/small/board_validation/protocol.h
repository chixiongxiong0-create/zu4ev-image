#ifndef BOARD_VALIDATION_PROTOCOL_H
#define BOARD_VALIDATION_PROTOCOL_H
#include <stdint.h>
#define VALIDATION_BASE 0x0023f000u
#define VALIDATION_MAGIC 0x49564231u
#define VALIDATION_VERSION 0x00010000u
#define COMMAND_TEST 0x54455354u
#define DONE_SIGNATURE 0x600dcf01u
enum { WAIT_VIDEO=1, OBSERVING=2, OWNED=3, TESTING=4, RESTORING=5,
       COMPLETE=6, FAILED=7, TRAPPED=8 };
enum { ERR_SNAPSHOT=1, ERR_ID=2, ERR_PENDING=4, ERR_READBACK=8,
       ERR_RESTORE=16, ERR_OWNER=32, ERR_TRAP=64 };
/* All offsets are byte offsets; PS/JTAG owns command, request and video_ready.
 * CPU owns other words. Write command then request last; wait ack==request.
 * Test command authorizes ONLY uncommitted shadow-black write/read/restore. */
struct validation_mailbox {
  uint32_t magic, version, size, state;                 /* 00..0c */
  uint32_t heartbeat, errors, signature, publish_seq;   /* 10..1c */
  uint32_t command, request, ack, video_ready;         /* 20..2c */
  uint32_t owner, isp_id, isp_version, capabilities;   /* 30..3c */
  uint32_t before, trial, observed, restored;          /* 40..4c */
  uint32_t dirty, mcause, mepc, mtval;                 /* 50..5c */
  uint32_t snapshot[17];                              /* 60..a0, offsets 08..48 */
  uint32_t snapshot_retries, tests;                    /* a4..a8 */
};
#endif
