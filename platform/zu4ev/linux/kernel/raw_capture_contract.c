#include <raw_capture_contract.h>

int sc130_raw_result_valid(unsigned int dma_done, unsigned int flags,
                           unsigned int result_epoch, unsigned int requested_epoch,
                           unsigned int words, unsigned int lines,
                           unsigned int guard_status, unsigned int bytes)
{
    return 1U == dma_done && 1U == flags && result_epoch == requested_epoch
           && 655360U == words && 1024U == lines && 5U == (guard_status & 7U)
           && 2621440U == bytes;
} /* end of sc130_raw_result_valid */
