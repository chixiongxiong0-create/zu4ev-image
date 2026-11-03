#include <assert.h>
#include <stdarg.h>
#include <stdio.h>
#define ioctl bridge_test_ioctl
#define close bridge_test_close
#define munmap bridge_test_munmap
#define main bridge_program_main
#include "../platform_bridge.c"
#undef main
#undef ioctl
#undef close
#undef munmap

static struct platform *current;
static unsigned ready_aus,next_calls,release_calls,submit_calls,qbuf_calls,encoder_closed;
static bool fail_qbuf,fail_stop,output_cancelled,submit_busy,submit_fail;
static int completion=-1;
static unsigned completion_flags;
static unsigned keyframe_mask=1;
static uint8_t encoded[4][32];
static uint8_t source[SC130_SIZE],output[4][64];
static unsigned sizes[4]={6,9,12,15};
struct h264_encoder *h264_encoder_open(const char *path,unsigned fps,unsigned bitrate)
{ (void)path;assert(fps==120 && bitrate==20000000);return (struct h264_encoder *)(uintptr_t)1; }
int h264_encoder_fd(struct h264_encoder *e) { return e?8:-1; }
void h264_encoder_close(struct h264_encoder *e) { if(e)encoder_closed++; }
int h264_encoder_next(struct h264_encoder *e,struct h264_access_unit *au)
{
    assert(e);next_calls++;
    if(!ready_aus)return 0;
    unsigned i=3-ready_aus;ready_aus--;
    *au=(struct h264_access_unit){encoded[i],sizes[i],i,9000+i,!!(keyframe_mask&(1u<<i))};return 1;
}
int h264_encoder_release(struct h264_encoder *e,unsigned index)
{ assert(e && index<4);release_calls++;return 0; }
int h264_encoder_submit(struct h264_encoder *e,const uint8_t *data,size_t size,uint32_t seq,uint64_t stamp)
{
    (void)seq;(void)stamp;assert(e && data==source && size==SC130_SIZE);
    assert(current && current->broker.encoder[2] && current->broker.dp[2]);
    submit_calls++;if(submit_fail){errno=EIO;return -1;}return submit_busy?0:1;
}
int bridge_test_close(int fd){assert(fd==4);output_cancelled=true;return 0;}
int bridge_test_munmap(void *data,size_t length)
{ (void)data;(void)length;assert(!fail_stop || output_cancelled);return 0; }
int bridge_test_ioctl(int fd,unsigned long op,...)
{
    assert(fd==4);va_list args;va_start(args,op);void *arg=va_arg(args,void *);va_end(args);
    if(op==VIDIOC_QBUF) {
        struct v4l2_buffer *b=arg;assert(b->memory==V4L2_MEMORY_MMAP && b->index<4);
        if(fail_qbuf){errno=EIO;return -1;}
        unsigned au=output[b->index][0]-0x60;
        assert(au<4 && b->bytesused==sizes[au]);assert(!memcmp(output[b->index],encoded[au],b->bytesused));
        qbuf_calls++;return 0;
    }
    if(op==VIDIOC_STREAMON)return 0;
    if(op==VIDIOC_STREAMOFF){if(fail_stop){errno=EIO;return -1;}output_cancelled=true;return 0;}
    if(op==VIDIOC_REQBUFS)return 0;
    if(op==VIDIOC_DQBUF) {
        if(completion<0){errno=EAGAIN;return -1;}
        struct v4l2_buffer *b=arg;b->index=(unsigned)completion;b->flags=completion_flags;completion=-1;return 0;
    }
    assert(0);errno=EINVAL;return -1;
}
static struct platform setup(void)
{
    struct platform p={.cap={.fd=3,.on=true,.count=8},
        .out={.fd=4,.type=V4L2_BUF_TYPE_VIDEO_OUTPUT,.count=4,.h264=true,.on=true},
        .encoder=(struct h264_encoder *)(uintptr_t)1,.bitrate=20000000};
    broker_init(&p.broker,8);assert(!broker_dequeue(&p.broker,2));assert(!broker_latest(&p.broker,2));
    assert(!broker_dp_hold(&p.broker,2));p.cap.b[2]=(struct mapped){source,sizeof(source)};
    p.meta[2].sequence=10;p.meta[2].bytesused=SC130_SIZE;
    for(unsigned i=0;i<4;i++){p.out.b[i]=(struct mapped){output[i],sizeof(output[i])};memset(encoded[i],0x60+i,sizeof(encoded[i]));}
    uvc_session_init_h264(&p.session,true,1);p.session.streaming=true;
    policy_init(&p.usb,4,120);
    ready_aus=next_calls=release_calls=submit_calls=qbuf_calls=encoder_closed=0;
    fail_qbuf=fail_stop=output_cancelled=submit_busy=submit_fail=false;completion=-1;completion_flags=0;
    keyframe_mask=1;
    for(unsigned i=0;i<16;i++)p.usb_source[i]=-1;
    return p;
}
int main(void)
{
    memset(source,0x35,sizeof(source));
    struct platform p=setup();current=&p;ready_aus=3;
    assert(!usb_send(&p,1000000000ull));
    assert(qbuf_calls==3 && release_calls==3 && p.encoded==3 && p.sent==3 && submit_calls==1);
    for(unsigned i=0;i<3;i++)assert(p.usb.slot[i].state==USB_IN_FLIGHT && p.usb.slot[i].sequence==i);
    assert(p.broker.dp[2] && !p.broker.encoder[2] && !p.broker.usb[2] && source[0]==0x35);
    /* Completing a later USB slot does not release raw DP memory. */
    completion=1;assert(!usb_complete(&p));assert(p.usb.slot[1].state==FREE && p.broker.dp[2]);
    for(unsigned i=0;i<4;i++)p.usb.slot[i].state=USB_IN_FLIGHT;
    unsigned calls=next_calls;assert(!usb_send(&p,1000000001ull));assert(next_calls==calls);
    /* Cadence remains anchored despite a slightly late frame. */
    p=setup();current=&p;
    uint64_t period=(1000000000ull+60)/120,base=1000000000ull;
    assert(!usb_send(&p,base));assert(p.usb.next_ns==base+period);
    p.meta[2].sequence++;
    assert(!usb_send(&p,base+period+100));assert(p.usb.next_ns==base+2*period);
    p.meta[2].sequence++;
    assert(!usb_send(&p,base+2*period+50));assert(submit_calls==3 && p.usb.next_ns==base+3*period);
    submit_busy=true;p.meta[2].sequence++;assert(!usb_send(&p,base+3*period+50));
    assert(!p.broker.encoder[2] && p.usb_sent_sequence==12);
    submit_busy=false;submit_fail=true;assert(usb_send(&p,base+3*period+50)<0 && errno==EIO);
    assert(!p.broker.encoder[2] && p.broker.dp[2]);
    p=setup();current=&p;ready_aus=3;fail_qbuf=true;p.h264_need_idr=true;
    assert(usb_send(&p,base)<0 && p.sent==0 && release_calls==1);
    assert(p.h264_need_idr && !p.h264_recoveries);
    usb_stop(&p,true);assert(p.broker.dp[2] && p.cap.on && encoder_closed==1 && !p.encoder);
    usb_stop(&p,true);assert(encoder_closed==1 && p.broker.dp[2]);
    p=setup();current=&p;p.usb.slot[0].state=USB_IN_FLIGHT;completion=0;completion_flags=V4L2_BUF_FLAG_ERROR;
    assert(!usb_complete(&p) && p.h264_need_idr && p.usb_errors==1 && p.broker.dp[2]);
    assert(p.out.fd==4 && p.out.on && p.encoder && !encoder_closed && !output_cancelled);
    p.usb.slot[1].state=USB_IN_FLIGHT;completion=1;
    assert(!usb_complete(&p) && p.usb_errors==2 && p.h264_need_idr);
    ready_aus=3;keyframe_mask=4;
    assert(!usb_send(&p,base));
    assert(release_calls==3 && qbuf_calls==1 && p.sent==1 && !p.h264_need_idr);
    assert(p.h264_recovery_drops==2 && p.h264_recoveries==1 && !encoder_closed);
    completion=0;assert(!usb_complete(&p) && p.h264_need_idr && p.usb_errors==3);
    ready_aus=1;assert(!usb_send(&p,base+1) && !p.h264_need_idr && p.h264_recoveries==2);
    p.h264_need_idr=true;
    fail_stop=true;usb_stop(&p,true);
    assert(output_cancelled && p.out.fd==-1 && p.broker.dp[2] && p.cap.on && encoder_closed==1);
    assert(!p.h264_need_idr);
    puts("H264 ordered variable-size UVC, cadence, backpressure, failure cancellation and raw DP: PASS");
    return 0;
}
