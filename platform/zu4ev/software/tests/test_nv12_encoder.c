#include <assert.h>
#include <stdarg.h>
#include <stdio.h>
#define ioctl nv_test_ioctl
#define open nv_test_open
#define close nv_test_close
#define mmap nv_test_mmap
#define munmap nv_test_munmap
#include "../h264_encoder.c"
#undef ioctl
#undef open
#undef close
#undef mmap
#undef munmap
static int source=-1,completed=-1;
static unsigned returns,queued,stop_seen,closed_encoder,cap_unmapped;
static bool fail_queue;
int nv_test_open(const char *p,int flags,...)
{ (void)flags;return !strcmp(p,"/enc") ? 9 : (!strcmp(p,"/nv")?10:-1); }
int nv_test_close(int fd)
{
    if(fd==9){assert(stop_seen);closed_encoder++;}
    if(fd==10)assert(closed_encoder);
    return 0;
}
void *nv_test_mmap(void *p,size_t n,int prot,int flags,int fd,off_t offset)
{ (void)p;(void)prot;(void)flags;(void)offset;assert(fd==9);return calloc(1,n); }
int nv_test_munmap(void *p,size_t n)
{ (void)n;assert(closed_encoder);cap_unmapped++;free(p);return 0; }
int nv_test_ioctl(int fd,unsigned long op,...)
{
    va_list ap;va_start(ap,op);void *arg=va_arg(ap,void *);va_end(ap);
    if(fd==10) {
        if(op==SC130_NV12_GETBUF) {
            struct sc130_nv12_buffer *b=arg;
            b->fd=20+b->index;b->size=1280*1024*3/2;b->stride=1280;b->width=1280;b->height=1024;return 0;
        }
        if(op==SC130_NV12_START)return 0;
        if(op==SC130_NV12_STOP){stop_seen++;return 0;}
        if(op==SC130_NV12_DQBUF) {
            if(source<0){errno=EAGAIN;return -1;}
            *(struct sc130_nv12_frame *)arg=(struct sc130_nv12_frame){.index=source,.sequence=source,.timestamp_ns=1000000000ull+source*10000000ull};
            source=-1;return 0;
        }
        if(op==SC130_NV12_QBUF){assert(*(uint32_t *)arg<4);returns++;return 0;}
        assert(0);
    }
    assert(fd==9);
    if(op==VIDIOC_QUERYCAP){struct v4l2_capability *c=arg;strcpy((char *)c->driver,"allegro");c->capabilities=V4L2_CAP_VIDEO_M2M|V4L2_CAP_STREAMING;return 0;}
    if(op==VIDIOC_S_FMT){struct v4l2_format *f=arg;f->fmt.pix.bytesperline=1280;f->fmt.pix.sizeimage=f->type==V4L2_BUF_TYPE_VIDEO_OUTPUT?1280*1024*3/2:65536;return 0;}
    if(op==VIDIOC_S_CTRL || op==VIDIOC_S_PARM || op==VIDIOC_STREAMON || op==VIDIOC_STREAMOFF)return 0;
    if(op==VIDIOC_REQBUFS){struct v4l2_requestbuffers *b=arg;assert(b->memory==(b->type==V4L2_BUF_TYPE_VIDEO_OUTPUT?V4L2_MEMORY_DMABUF:V4L2_MEMORY_MMAP));b->count=4;return 0;}
    if(op==VIDIOC_QUERYBUF){struct v4l2_buffer *b=arg;assert(b->type==V4L2_BUF_TYPE_VIDEO_CAPTURE);b->length=65536;return 0;}
    if(op==VIDIOC_QBUF){struct v4l2_buffer *b=arg;if(b->type==V4L2_BUF_TYPE_VIDEO_OUTPUT){assert(b->memory==V4L2_MEMORY_DMABUF&&b->m.fd==(int)(20+b->index));if(fail_queue){errno=EIO;return -1;}queued++;}return 0;}
    if(op==VIDIOC_DQBUF){struct v4l2_buffer *b=arg;assert(b->memory==V4L2_MEMORY_DMABUF);if(completed<0){errno=EAGAIN;return -1;}b->index=completed;completed=-1;return 0;}
    assert(0);return -1;
}
int main(void)
{
    struct h264_encoder *e=h264_encoder_open_nv12("/enc","/nv",120,20000000);assert(e);
    assert(h264_encoder_capture_fd(e)==10);
    assert(h264_encoder_submit(e,NULL,0,0,0)==-1 && errno==EINVAL);
    for(unsigned i=0;i<4;i++)assert(!e->raw[i].data);
    source=0;assert(h264_encoder_pump_nv12(e)==1);assert(queued==1&&returns==0&&e->raw[0].busy);
    assert(h264_encoder_pump_nv12(e)==0&&returns==0); // no premature release
    source=1;assert(h264_encoder_pump_nv12(e)==1&&returns==0);
    completed=0;assert(h264_encoder_pump_nv12(e)==0&&returns==1&&!e->raw[0].busy&&e->raw[1].busy);
    source=2;fail_queue=true;assert(h264_encoder_pump_nv12(e)==-1&&returns==1);
    h264_encoder_close(e);assert(stop_seen&&closed_encoder&&cap_unmapped==4);
    fail_queue=false;
    e=h264_encoder_open_nv12("/enc","/nv",60,20000000);assert(e);
    source=0;assert(h264_encoder_pump_nv12(e)==1);
    unsigned before=returns;
    source=1;assert(h264_encoder_pump_nv12(e)==0&&returns==before+1&&!e->raw[1].busy);
    h264_encoder_close(e);
    puts("NV12 DMA-BUF import, no raw mmap/conversion, VCU DQBUF release, queue-failure cancellation: PASS");
    return 0;
}
