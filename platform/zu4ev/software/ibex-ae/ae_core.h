#ifndef _RTK_SOFTWARE_R5_AE_AE_CORE_H_
#define _RTK_SOFTWARE_R5_AE_AE_CORE_H_
#include <stdint.h>

/* Exposure register code uses 16 units per two sensor lines. */
struct ae_core
{
    uint32_t last_stats_seq;
    uint32_t last_write_fe;
    uint16_t exposure;
    uint16_t max_exposure;
    uint8_t fine_gain;
    uint8_t initialized;
    uint8_t have_write;
};

enum ae_change
{
    AE_CHANGE_NONE,
    AE_CHANGE_EXPOSURE,
    AE_CHANGE_FINE_GAIN,
    AE_CHANGE_END
};
struct ae_update
{
    enum ae_change kind;
    uint16_t exposure;
    uint8_t fine_gain;
};

extern void
sc130_ae_core_init(struct ae_core *pAe, uint16_t exposure, uint16_t vts, uint8_t fine_gain);
extern enum ae_change sc130_ae_core_propose(struct ae_core *pAe,
                                            uint32_t fe_seq,
                                            uint32_t stats_seq,
                                            uint32_t mean,
                                            int valid,
                                            struct ae_update *pNext);
extern void
sc130_ae_core_commit(struct ae_core *pAe, uint32_t fe_seq, const struct ae_update *pNext);
#endif
