#ifndef SC130_NV12_CAPTURE_H
#define SC130_NV12_CAPTURE_H
#include <linux/types.h>
#include <linux/ioctl.h>
/* Fixed-width ABI; no kernel DMA addresses are exposed. */
struct sc130_nv12_buffer {
    __u32 index;
    __s32 fd;
    __u32 size, stride, width, height;
};
struct sc130_nv12_frame {
    __u32 index, sequence;
    __u64 timestamp_ns;
};
#define SC130_NV12_GETBUF _IOWR('N', 0, struct sc130_nv12_buffer)
#define SC130_NV12_START  _IO('N', 1)
#define SC130_NV12_STOP   _IO('N', 2)
#define SC130_NV12_DQBUF  _IOR('N', 3, struct sc130_nv12_frame)
#define SC130_NV12_QBUF   _IOW('N', 4, __u32)
#endif
