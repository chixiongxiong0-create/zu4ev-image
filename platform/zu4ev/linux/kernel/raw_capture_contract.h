#ifndef _RTK_LINUX_KERNEL_RAW_CAPTURE_CONTRACT_H_
#define _RTK_LINUX_KERNEL_RAW_CAPTURE_CONTRACT_H_

extern int sc130_raw_result_valid(unsigned int dma_done, unsigned int flags,
                                  unsigned int result_epoch, unsigned int requested_epoch,
                                  unsigned int words, unsigned int lines,
                                  unsigned int guard_status, unsigned int bytes);
#endif
