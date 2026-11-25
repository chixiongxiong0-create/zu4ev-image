/* Board-only fault fixture. Never link this into the production bridge.
 * Suppress one whole encoded AU before the gadget sees it, then synthesize
 * its failed completion. This tests decoder resynchronization over real USB;
 * it does not reproduce or diagnose a controller transfer failure. */
#define _GNU_SOURCE
#include <sys/ioctl.h>
#include <sys/syscall.h>
#include <linux/videodev2.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
static int loss_ioctl(int fd,unsigned long op,...);
#define ioctl loss_ioctl
#include "../platform_bridge.c"
#undef ioctl
static int loss_ioctl(int fd,unsigned long op,...)
{
    static unsigned output_count;
    static int pending_fd=-1;
    static struct v4l2_buffer lost;
    va_list args;va_start(args,op);void *arg=va_arg(args,void *);va_end(args);
    if(op==VIDIOC_QBUF) {
        struct v4l2_buffer *b=arg;
        if(b->type==V4L2_BUF_TYPE_VIDEO_OUTPUT && ++output_count==180) {
            lost=*b;pending_fd=fd;
            fprintf(stderr,"FIXTURE suppressed encoded AU number=180 bytes=%u slot=%u\n",b->bytesused,b->index);
            return 0;
        }
    }
    if(op==VIDIOC_DQBUF && fd==pending_fd) {
        struct v4l2_buffer *b=arg;
        if(b->type==V4L2_BUF_TYPE_VIDEO_OUTPUT) {
            *b=lost;b->flags|=V4L2_BUF_FLAG_ERROR;b->bytesused=0;
            pending_fd=-1;return 0;
        }
    }
    return (int)syscall(SYS_ioctl,fd,op,arg);
}
