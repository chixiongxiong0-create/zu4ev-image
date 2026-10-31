#include <ae_core.h>

#define AE_TARGET 96U
#define AE_DEADBAND 8U

void sc130_ae_core_init(struct ae_core *pAe, uint16_t exposure, uint16_t vts, uint8_t fine_gain)
{
    pAe->last_stats_seq = 0;
    pAe->last_write_fe = 0;
    pAe->exposure = exposure;
    pAe->fine_gain = fine_gain;
    pAe->max_exposure = vts > 4 ? (uint16_t)((vts - 4U) << 4) : 16;
    pAe->initialized = 0;
    pAe->have_write = 0;
} /* end of sc130_ae_core_init */

enum ae_change sc130_ae_core_propose(struct ae_core *pAe,
                                     uint32_t fe_seq,
                                     uint32_t stats_seq,
                                     uint32_t mean,
                                     int valid,
                                     struct ae_update *pOut)
{
    uint32_t next;
    uint32_t lower;
    uint32_t upper;
    pOut->kind = AE_CHANGE_NONE;
    pOut->exposure = pAe->exposure;
    pOut->fine_gain = pAe->fine_gain;
    if (!valid || !stats_seq || stats_seq == pAe->last_stats_seq)
    {
        return AE_CHANGE_NONE;
    }
    pAe->last_stats_seq = stats_seq;
    if (!pAe->initialized)
    {
        pAe->initialized = 1;
        return AE_CHANGE_NONE;
    }
    /* Wait past the documented N+2 transition before using new statistics. */
    if (pAe->have_write && (uint32_t)(fe_seq - pAe->last_write_fe) < 4U)
    {
        return AE_CHANGE_NONE;
    }
    if (mean >= AE_TARGET - AE_DEADBAND && mean <= AE_TARGET + AE_DEADBAND)
    {
        return AE_CHANGE_NONE;
    }
    if (!mean)
    {
        mean = 1;
    }
    /* The sensor guide prefers exposure before gain on darkening, and
     * removes gain before exposure on brightening. Fine gain alone uses
     * 3e09=0x20..0x3f, avoiding an undocumented group hold sequence. */
    if ((mean < AE_TARGET - AE_DEADBAND && pAe->exposure == pAe->max_exposure)
        || (mean > AE_TARGET + AE_DEADBAND && pAe->fine_gain > 0x20U))
    {
        next = (uint32_t)(((uint64_t)pAe->fine_gain * AE_TARGET + mean / 2U) / mean);
        lower = (uint32_t)pAe->fine_gain * 3U / 4U;
        upper = (uint32_t)pAe->fine_gain * 5U / 4U;
        if (next < lower)
        {
            next = lower;
        }
        if (next > upper)
        {
            next = upper;
        }
        if (next < 0x20U)
        {
            next = 0x20U;
        }
        if (next > 0x3fU)
        {
            next = 0x3fU;
        }
        if (next != pAe->fine_gain)
        {
            pOut->fine_gain = (uint8_t)next;
            pOut->kind = AE_CHANGE_FINE_GAIN;
        }
        return pOut->kind;
    }
    next = (uint32_t)(((uint64_t)pAe->exposure * AE_TARGET + mean / 2U) / mean);
    lower = (uint32_t)pAe->exposure * 3U / 4U;
    upper = (uint32_t)pAe->exposure * 5U / 4U;
    if (next < lower)
    {
        next = lower;
    }
    if (next > upper)
    {
        next = upper;
    }
    if (next < 16U)
    {
        next = 16U;
    }
    if (next > pAe->max_exposure)
    {
        next = pAe->max_exposure;
    }
    next = (next + 8U) & ~15U;
    if (next > pAe->max_exposure)
    {
        next = pAe->max_exposure;
    }
    if (next != pAe->exposure)
    {
        pOut->exposure = (uint16_t)next;
        pOut->kind = AE_CHANGE_EXPOSURE;
    }
    return pOut->kind;
} /* end of sc130_ae_core_propose */

void sc130_ae_core_commit(struct ae_core *pAe, uint32_t fe_seq, const struct ae_update *pNext)
{
    pAe->exposure = pNext->exposure;
    pAe->fine_gain = pNext->fine_gain;
    pAe->last_write_fe = fe_seq;
    pAe->have_write = 1;
} /* end of sc130_ae_core_commit */
