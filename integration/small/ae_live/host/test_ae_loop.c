#include <ae_core.h>
#include <assert.h>
#include <stdio.h>

static unsigned sc130_ae_test_measure(unsigned light, unsigned exposure, unsigned gain)
{
    return (light * exposure * gain + 0x800U * 16U) / (0x800U * 32U);
} /* end of sc130_ae_test_measure */

int main(void)
{
    struct ae_core ae;
    struct ae_update update = {0};
    unsigned actual_exposure = 0x800U;
    unsigned actual_gain = 0x20U;
    unsigned queued_exposure = actual_exposure;
    unsigned queued_gain = actual_gain;
    unsigned effective_at = 0;
    unsigned light = 30;
    unsigned mean = 0;
    unsigned frame;
    sc130_ae_core_init(&ae, 0x800U, 529U, 0x20U);
    for (frame = 1; frame <= 300; ++frame)
    {
        if (101 == frame)
        {
            light = 15;
        }
        if (201 == frame)
        {
            light = 60;
        }
        if (effective_at == frame)
        {
            actual_exposure = queued_exposure;
            actual_gain = queued_gain;
        }
        mean = sc130_ae_test_measure(light, actual_exposure, actual_gain);
        if (sc130_ae_core_propose(&ae, frame, frame, mean, 1, &update) != AE_CHANGE_NONE)
        {
            queued_exposure = update.exposure;
            queued_gain = update.fine_gain;
            effective_at = frame + 2U;
            sc130_ae_core_commit(&ae, frame, &update);
        }
        if (100 == frame || 200 == frame || 300 == frame)
        {
            assert(mean >= 88U && mean <= 104U);
            printf("frame=%u light=%u mean=%u exposure=0x%04x gain=0x%02x\n",
                   frame,
                   light,
                   mean,
                   actual_exposure,
                   actual_gain);
        }
    }
    return 0;
} /* end of main */
