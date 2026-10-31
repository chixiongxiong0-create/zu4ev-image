#define ioctl mock_ioctl
#define main platform_bridge_main
#include "../platform_bridge.c"
#undef main
#undef ioctl
#include <stdarg.h>
#include <assert.h>
static int operation, fail_queue, fail_stop, fail_start, completed;
int mock_ioctl(int fd,unsigned long req,...)
{
    va_list ap;va_start(ap,req);void *arg=va_arg(ap,void*);va_end(ap);
    assert(fd==(req==VIDIOC_EXPBUF?0:4));
    if(req==VIDIOC_QBUF) {
        struct v4l2_buffer *b=arg;
        assert(b->memory==V4L2_MEMORY_DMABUF && b->m.fd==42);
        assert(b->index<4 && b->bytesused==SC130_SIZE && b->length==SC130_SIZE);
        if(fail_queue){errno=EIO;return -1;}return 0;
    }
    if(req==VIDIOC_DQBUF) {
        struct v4l2_buffer *b=arg;assert(b->memory==V4L2_MEMORY_DMABUF);
        if(operation++){errno=EAGAIN;return -1;}
        b->index=(unsigned)completed;b->flags=V4L2_BUF_FLAG_ERROR;return 0;
    }
    if(req==VIDIOC_EXPBUF){((struct v4l2_exportbuffer*)arg)->fd=42;return 0;}
    if(req==VIDIOC_STREAMON){if(fail_start){errno=EIO;return -1;}return 0;}
    if(req==VIDIOC_STREAMOFF){if(fail_stop){errno=EIO;return -1;}return 0;}
    if(req==VIDIOC_REQBUFS){assert(((struct v4l2_requestbuffers*)arg)->memory==V4L2_MEMORY_DMABUF);return 0;}
    assert(0);return -1;
}
static struct platform setup(void)
{
    struct platform p={.profile=true,.out={.fd=4,.on=true,.shared=true,.count=4,.type=V4L2_BUF_TYPE_VIDEO_OUTPUT}};
    for(unsigned i=0;i<16;i++){p.usb_source[i]=-1;p.exported[i]=-1;}
    p.exported[2]=42;broker_init(&p.broker,8);
    assert(!broker_dequeue(&p.broker,2));assert(!broker_latest(&p.broker,2));
    assert(!broker_dp_hold(&p.broker,2));policy_init(&p.usb,4,120);
    p.session.streaming=true;p.meta[2].sequence=10;operation=fail_queue=fail_stop=fail_start=completed=0;
    return p;
}
int main(void)
{
    struct platform p=setup();
    /* No source/destination CPU mappings: sending must only submit the FD. */
    assert(!usb_send(&p,now_ns()));assert(p.broker.usb[2] && p.usb_source[0]==2);
    assert(!p.copy_wall.count && p.qbuf_cost.count==1);
    assert(!broker_dequeue(&p.broker,3));assert(!broker_latest(&p.broker,3));
    assert(!broker_dp_release(&p.broker,2));assert(!broker_can_queue(&p.broker,2));
    assert(!usb_complete(&p));assert(!p.broker.usb[2] && broker_can_queue(&p.broker,2));
    assert(p.returned==1 && p.usb_error_kind[USB_ERR_BUFFER]==1);
    operation=0;assert(usb_complete(&p)<0 && errno==EPROTO);
    p=setup();fail_queue=1;assert(usb_send(&p,now_ns())<0);
    assert(!p.broker.usb[2] && p.usb_source[0]==-1 && p.broker.dp[2]);
    p=setup();assert(!usb_send(&p,now_ns()));usb_stop(&p,true);
    assert(!p.broker.usb[2] && p.broker.dp[2] && p.broker.latest==2);
    assert(!p.out.count && !p.out.on);
    p=setup();assert(!usb_send(&p,now_ns()));fail_stop=1;usb_stop(&p,true);
    assert(p.out.fd==-1 && !p.broker.usb[2] && p.broker.dp[2]);
    p=setup();p.exported[2]=-1;p.out.on=false;
    assert(!usb_send(&p,now_ns()));assert(p.exported[2]==42 && p.out.on);
    p=setup();p.out.on=false;fail_start=1;assert(usb_send(&p,now_ns())<0);
    assert(p.broker.usb[2]);usb_stop(&p,true);assert(!p.broker.usb[2]);
    p=setup();assert(!usb_send(&p,now_ns()));
    assert(!broker_dequeue(&p.broker,3));assert(!broker_latest(&p.broker,3));
    p.exported[3]=42;p.meta[3].sequence=11;p.usb.next_ns=0;
    assert(!usb_send(&p,now_ns()));assert(p.broker.usb[2] && p.broker.usb[3]);
    completed=1;assert(!usb_complete(&p));assert(p.broker.usb[2] && !p.broker.usb[3]);
    operation=0;completed=0;assert(!usb_complete(&p));assert(!p.broker.usb[2] && p.broker.dp[2]);
    puts("shared USB FD queue, no CPU copy, completion/error/stop ownership: PASS");
    return 0;
}

