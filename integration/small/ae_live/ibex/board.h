#ifndef IBEX_AE_BOARD_H
#define IBEX_AE_BOARD_H
#include <stdint.h>
#define AE_SENSOR_BASE 0x52000000u
#define AE_SNAPSHOT_BASE 0x50000000u
#define AE_ISP_BASE 0x51000000u
#define AE_LITE_HZ 100000000u
#define AE_MAILBOX_BASE 0x0023e000u
#define AE_MAGIC 0x49414531u
#define AE_LOG_CAP 512u
enum ae_state { AE_WAITING=1, AE_STARTING, AE_RUNNING, AE_STOPPED, AE_FAULT };
enum ae_fault { AE_NO_FAULT, AE_BAD_ID, AE_BAD_SENSOR, AE_I2C_ERROR,
    AE_I2C_TIMEOUT, AE_NO_FRAMES, AE_NO_STATS, AE_NO_SOF, AE_CROSS_FRAME,
    AE_READBACK, AE_TRAP, AE_BAD_OWNER };
struct ae_mailbox {
    uint32_t magic,version,size,state,heartbeat,fault,irq_count,fe_seq;
    uint32_t sof_seq,stats_seq,stats_frame,mean,exposure,gain,changes,dropped_fe;
    uint32_t records,mcause,mepc,session,signature;
};
struct ae_record {
    uint32_t fe,stats,frame,mean,exposure,gain,kind,proposed;
    uint32_t start_tick,end_tick,sof_before,sof_after,fault;
};
extern volatile struct ae_mailbox *const ae_mailbox;
extern volatile struct ae_record ae_records[AE_LOG_CAP];
void ae_irq_handler(void);
void ae_trap_handler(uint32_t cause,uint32_t pc);
#endif
