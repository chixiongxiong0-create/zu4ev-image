#include <ae_core.h>
#include <assert.h>
#include <stdio.h>

int main(void)
{
    struct ae_core ae;
    struct ae_update n;
    sc130_ae_core_init(&ae, 0x0800, 529, 0x20);
    assert(AE_CHANGE_NONE == sc130_ae_core_propose(&ae, 1, 1, 40, 1, &n));
    assert(AE_CHANGE_EXPOSURE == sc130_ae_core_propose(&ae, 2, 2, 40, 1, &n));
    assert(0x0a00 == n.exposure);
    sc130_ae_core_commit(&ae, 2, &n);
    assert(AE_CHANGE_NONE == sc130_ae_core_propose(&ae, 3, 3, 40, 1, &n));
    assert(AE_CHANGE_NONE == sc130_ae_core_propose(&ae, 4, 4, 40, 1, &n));
    assert(AE_CHANGE_NONE == sc130_ae_core_propose(&ae, 5, 5, 40, 1, &n));
    assert(AE_CHANGE_NONE == sc130_ae_core_propose(&ae, 6, 6, 96, 1, &n));
    ae.exposure = ae.max_exposure;
    assert(AE_CHANGE_FINE_GAIN == sc130_ae_core_propose(&ae, 7, 7, 50, 1, &n));
    assert(0x28 == n.fine_gain);
    sc130_ae_core_commit(&ae, 7, &n);
    assert(AE_CHANGE_FINE_GAIN == sc130_ae_core_propose(&ae, 11, 11, 180, 1, &n));
    assert(0x20 == n.fine_gain);
    sc130_ae_core_commit(&ae, 11, &n);
    assert(AE_CHANGE_EXPOSURE == sc130_ae_core_propose(&ae, 15, 15, 180, 1, &n));
    assert(AE_CHANGE_NONE == sc130_ae_core_propose(&ae, 16, 15, 180, 1, &n));
    assert(AE_CHANGE_NONE == sc130_ae_core_propose(&ae, 17, 16, 0, 0, &n));
    puts("AE_CORE_PASS exposure priority, fine gain, N+2 holdoff, deadband");
    return 0;
} /* end of main */
