#define _GNU_SOURCE
#include "h264_encoder.h"
#include "uvc_core.h"
#include <errno.h>
#include <fcntl.h>
#include <glob.h>
#include <linux/videodev2.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>
#ifdef __aarch64__
#include <arm_neon.h>
#endif

#define ENCODER_SLOTS 4u
#define MAX_RAW_SIZE (16u * 1024u * 1024u)
struct encoder_slot { void *data; size_t length; bool busy; };
struct h264_encoder {
    int fd;
    unsigned stride, raw_size, cap_size, nr, nc;
    bool first;
    struct encoder_slot raw[ENCODER_SLOTS], cap[ENCODER_SLOTS];
};
static int encoder_ioctl(int fd,unsigned long op,void *arg)
{
    int result;
    do result=ioctl(fd,op,arg); while(result<0 && errno==EINTR);
    return result;
}
static int encoder_control(struct h264_encoder *e,unsigned id,int value)
{
    struct v4l2_control c={.id=id,.value=value};
    return encoder_ioctl(e->fd,VIDIOC_S_CTRL,&c);
}
int h264_encoder_fd(struct h264_encoder *e) { return e?e->fd:-1; }

/* Close is the cancellation barrier even when STREAMOFF fails. Source capture
 * pages are never submitted to this device: the raw slots are private NV12. */
void h264_encoder_close(struct h264_encoder *e)
{
    if(!e)return;
    if(e->fd>=0) {
        enum v4l2_buf_type type=V4L2_BUF_TYPE_VIDEO_OUTPUT;
        encoder_ioctl(e->fd,VIDIOC_STREAMOFF,&type);
        type=V4L2_BUF_TYPE_VIDEO_CAPTURE;
        encoder_ioctl(e->fd,VIDIOC_STREAMOFF,&type);
        close(e->fd);e->fd=-1;
    }
    for(unsigned i=0;i<ENCODER_SLOTS;i++) {
        if(e->raw[i].data)munmap(e->raw[i].data,e->raw[i].length);
        if(e->cap[i].data)munmap(e->cap[i].data,e->cap[i].length);
    }
    free(e);
}
static int encoder_buffers(struct h264_encoder *e,enum v4l2_buf_type type,
                           struct encoder_slot *slots,unsigned *count)
{
    struct v4l2_requestbuffers request={.count=ENCODER_SLOTS,.type=type,.memory=V4L2_MEMORY_MMAP,
        .flags=type==V4L2_BUF_TYPE_VIDEO_OUTPUT?V4L2_MEMORY_FLAG_NON_COHERENT:0};
    if(encoder_ioctl(e->fd,VIDIOC_REQBUFS,&request)<0)return -1;
    if(type==V4L2_BUF_TYPE_VIDEO_OUTPUT && !(request.flags&V4L2_MEMORY_FLAG_NON_COHERENT)){errno=ENOTSUP;return -1;}
    if(!request.count || request.count>ENCODER_SLOTS){errno=EPROTO;return -1;}
    *count=request.count;
    for(unsigned i=0;i<request.count;i++) {
        struct v4l2_buffer b={.type=type,.memory=V4L2_MEMORY_MMAP,.index=i};
        if(encoder_ioctl(e->fd,VIDIOC_QUERYBUF,&b)<0)return -1;
        unsigned minimum=type==V4L2_BUF_TYPE_VIDEO_OUTPUT?e->raw_size:e->cap_size;
        if(b.length<minimum || b.length>MAX_RAW_SIZE){errno=EPROTO;return -1;}
        slots[i].length=b.length;
        void *data=mmap(NULL,b.length,PROT_READ|PROT_WRITE,MAP_SHARED,e->fd,b.m.offset);
        if(data==MAP_FAILED)return -1;
        slots[i].data=data;
        if(type==V4L2_BUF_TYPE_VIDEO_CAPTURE && encoder_ioctl(e->fd,VIDIOC_QBUF,&b)<0)return -1;
    }
    return 0;
}
static struct h264_encoder *encoder_open_device(const char *path,unsigned fps,unsigned bitrate)
{
    struct h264_encoder *e=calloc(1,sizeof(*e));
    if(!e)return NULL;
    e->fd=-1;e->first=true;
    e->fd=open(path,O_RDWR|O_NONBLOCK|O_CLOEXEC);
    if(e->fd<0)goto fail;
    struct v4l2_capability c={0};
    if(encoder_ioctl(e->fd,VIDIOC_QUERYCAP,&c)<0)goto fail;
    unsigned caps=c.capabilities&V4L2_CAP_DEVICE_CAPS?c.device_caps:c.capabilities;
    if(strncmp((char *)c.driver,"allegro",sizeof(c.driver)) ||
       !(caps&V4L2_CAP_VIDEO_M2M) || !(caps&V4L2_CAP_STREAMING)){errno=ENODEV;goto fail;}
    struct v4l2_format f={.type=V4L2_BUF_TYPE_VIDEO_OUTPUT};
    f.fmt.pix=(struct v4l2_pix_format){.width=SC130_WIDTH,.height=SC130_HEIGHT,
        .pixelformat=V4L2_PIX_FMT_NV12,.field=V4L2_FIELD_NONE,
        .colorspace=V4L2_COLORSPACE_REC709,.ycbcr_enc=V4L2_YCBCR_ENC_709,
        .quantization=V4L2_QUANTIZATION_LIM_RANGE,.xfer_func=V4L2_XFER_FUNC_709};
    if(encoder_ioctl(e->fd,VIDIOC_S_FMT,&f)<0)goto fail;
    if(f.fmt.pix.width!=SC130_WIDTH || f.fmt.pix.height!=SC130_HEIGHT ||
       f.fmt.pix.pixelformat!=V4L2_PIX_FMT_NV12 || f.fmt.pix.bytesperline<SC130_WIDTH ||
       f.fmt.pix.bytesperline>8192){errno=EPROTO;goto fail;}
    e->stride=f.fmt.pix.bytesperline;e->raw_size=f.fmt.pix.sizeimage;
    if(e->raw_size<e->stride*SC130_HEIGHT*3/2 || e->raw_size>MAX_RAW_SIZE){errno=EPROTO;goto fail;}
    memset(&f,0,sizeof(f));f.type=V4L2_BUF_TYPE_VIDEO_CAPTURE;
    f.fmt.pix=(struct v4l2_pix_format){.width=SC130_WIDTH,.height=SC130_HEIGHT,
        .pixelformat=V4L2_PIX_FMT_H264,.sizeimage=SC130_H264_MAX_AU,.field=V4L2_FIELD_NONE};
    if(encoder_ioctl(e->fd,VIDIOC_S_FMT,&f)<0)goto fail;
    if(f.fmt.pix.width!=SC130_WIDTH || f.fmt.pix.height!=SC130_HEIGHT ||
       f.fmt.pix.pixelformat!=V4L2_PIX_FMT_H264 || !f.fmt.pix.sizeimage ||
       f.fmt.pix.sizeimage>SC130_H264_MAX_AU){errno=EPROTO;goto fail;}
    e->cap_size=f.fmt.pix.sizeimage;
    /* Baseline excludes B frames. Level 4.2 is insufficient for 614400
     * macroblocks/s at 1280x1024@120; level 5.1 covers both advertised rates. */
    if(encoder_control(e,V4L2_CID_MPEG_VIDEO_H264_PROFILE,V4L2_MPEG_VIDEO_H264_PROFILE_BASELINE)<0 ||
       encoder_control(e,V4L2_CID_MPEG_VIDEO_H264_LEVEL,V4L2_MPEG_VIDEO_H264_LEVEL_5_1)<0 ||
       encoder_control(e,V4L2_CID_MPEG_VIDEO_FRAME_RC_ENABLE,1)<0 ||
       /* Peak is writable only in VBR. Match it to target before selecting CBR.
        * Bound CPB arithmetic for this firmware driver's 32-bit conversion. */
       encoder_control(e,V4L2_CID_MPEG_VIDEO_BITRATE_MODE,V4L2_MPEG_VIDEO_BITRATE_MODE_VBR)<0 ||
       encoder_control(e,V4L2_CID_MPEG_VIDEO_BITRATE,(int)bitrate)<0 ||
       encoder_control(e,V4L2_CID_MPEG_VIDEO_BITRATE_PEAK,(int)bitrate)<0 ||
       encoder_control(e,V4L2_CID_MPEG_VIDEO_BITRATE_MODE,V4L2_MPEG_VIDEO_BITRATE_MODE_CBR)<0 ||
       encoder_control(e,V4L2_CID_MPEG_VIDEO_H264_CPB_SIZE,(int)(bitrate/8000>5000?5000:bitrate/8000))<0 ||
       encoder_control(e,V4L2_CID_MPEG_VIDEO_GOP_SIZE,(int)fps)<0)goto fail;
    struct v4l2_streamparm p={.type=V4L2_BUF_TYPE_VIDEO_OUTPUT};
    p.parm.output.timeperframe=(struct v4l2_fract){1,fps};
    if(encoder_ioctl(e->fd,VIDIOC_S_PARM,&p)<0)goto fail;
    if(p.parm.output.timeperframe.numerator!=1 || p.parm.output.timeperframe.denominator!=fps){errno=EPROTO;goto fail;}
    if(encoder_buffers(e,V4L2_BUF_TYPE_VIDEO_OUTPUT,e->raw,&e->nr)<0 ||
       encoder_buffers(e,V4L2_BUF_TYPE_VIDEO_CAPTURE,e->cap,&e->nc)<0)goto fail;
    enum v4l2_buf_type type=V4L2_BUF_TYPE_VIDEO_CAPTURE;
    if(encoder_ioctl(e->fd,VIDIOC_STREAMON,&type)<0)goto fail;
    type=V4L2_BUF_TYPE_VIDEO_OUTPUT;
    if(encoder_ioctl(e->fd,VIDIOC_STREAMON,&type)<0)goto fail;
    return e;
fail: {
    int error=errno;h264_encoder_close(e);errno=error;return NULL;
}
}
struct h264_encoder *h264_encoder_open(const char *path,unsigned fps,unsigned bitrate)
{
    if((fps!=60 && fps!=120) || bitrate<1000000 || bitrate>100000000){errno=EINVAL;return NULL;}
    if(path)return encoder_open_device(path,fps,bitrate);
    glob_t devices={0};struct h264_encoder *e=NULL;int error=ENODEV;
    if(glob("/dev/video*",0,NULL,&devices)==0) {
        for(size_t i=0;i<devices.gl_pathc;i++) {
            e=encoder_open_device(devices.gl_pathv[i],fps,bitrate);
            if(e)break;
            if(errno!=ENODEV)error=errno;
        }
    }
    globfree(&devices);if(!e)errno=error;
    return e;
}
/* Read only YUY2; write only encoder-owned NV12. Pair adjacent rows for 4:2:0
 * chroma with rounded averaging. AArch64 deinterleaves 16 pixels per NEON load.
 * Source capture and DP backing storage are never changed. */
static void encoder_convert(uint8_t *dst,unsigned stride,unsigned raw_size,const uint8_t *src)
{
    for(unsigned y=0;y<SC130_HEIGHT;y+=2) {
        const uint8_t *a=src+y*SC130_STRIDE,*b=a+SC130_STRIDE;
        uint8_t *ya=dst+y*stride,*yb=ya+stride;
        uint8_t *uv=dst+SC130_HEIGHT*stride+(y/2)*stride;
        unsigned x=0;
#ifdef __aarch64__
        for(;x+16<=SC130_WIDTH;x+=16) {
            uint8x16x2_t va=vld2q_u8(a+2*x),vb=vld2q_u8(b+2*x);
            vst1q_u8(ya+x,va.val[0]);vst1q_u8(yb+x,vb.val[0]);
            vst1q_u8(uv+x,vrhaddq_u8(va.val[1],vb.val[1]));
        }
#endif
        for(;x<SC130_WIDTH;x++) {
            ya[x]=a[2*x];yb[x]=b[2*x];
            uv[x]=(uint8_t)(((unsigned)a[2*x+1]+b[2*x+1]+1)/2);
        }
        if(stride>SC130_WIDTH) {
            memset(ya+SC130_WIDTH,0,stride-SC130_WIDTH);
            memset(yb+SC130_WIDTH,0,stride-SC130_WIDTH);
            memset(uv+SC130_WIDTH,128,stride-SC130_WIDTH);
        }
    }
    unsigned used=stride*SC130_HEIGHT*3/2;
    if(raw_size>used)memset(dst+used,0,raw_size-used);
}
int h264_encoder_submit(struct h264_encoder *e,const uint8_t *src,size_t length,uint32_t sequence,uint64_t stamp)
{
    if(!e || !src || length<SC130_SIZE){errno=EINVAL;return -1;}
    for(;;) {
        struct v4l2_buffer done={.type=V4L2_BUF_TYPE_VIDEO_OUTPUT,.memory=V4L2_MEMORY_MMAP};
        if(encoder_ioctl(e->fd,VIDIOC_DQBUF,&done)<0) {
            if(errno==EAGAIN)break;
            return -1;
        }
        if(done.index>=e->nr || !e->raw[done.index].busy || (done.flags&V4L2_BUF_FLAG_ERROR)){errno=EPROTO;return -1;}
        e->raw[done.index].busy=false;
    }
    unsigned i;
    for(i=0;i<e->nr && e->raw[i].busy;i++);
    if(i==e->nr)return 0;
    if(e->raw[i].length<e->raw_size){errno=EPROTO;return -1;}
    encoder_convert(e->raw[i].data,e->stride,e->raw_size,src);
    struct v4l2_buffer b={.type=V4L2_BUF_TYPE_VIDEO_OUTPUT,.memory=V4L2_MEMORY_MMAP,
        .index=i,.bytesused=e->raw_size,.field=V4L2_FIELD_NONE,.sequence=sequence};
    b.timestamp.tv_sec=(long)(stamp/1000000000);b.timestamp.tv_usec=(long)(stamp%1000000000/1000);
    if(encoder_ioctl(e->fd,VIDIOC_QBUF,&b)<0)return -1;
    e->raw[i].busy=true;return 1;
}
int h264_encoder_release(struct h264_encoder *e,unsigned index)
{
    if(!e || index>=e->nc || !e->cap[index].busy){errno=EINVAL;return -1;}
    struct v4l2_buffer b={.type=V4L2_BUF_TYPE_VIDEO_CAPTURE,.memory=V4L2_MEMORY_MMAP,.index=index};
    if(encoder_ioctl(e->fd,VIDIOC_QBUF,&b)<0)return -1;
    e->cap[index].busy=false;return 0;
}
/* Require Annex B with no inaccessible single-planar data_offset prefix. The
 * matching kernel must apply patch0010 (Allegro P-frame payload normalization). */
static bool encoder_annex_b(const uint8_t *data,size_t size,bool first)
{
    unsigned mask=0;bool seen=false;
    for(size_t i=0;i+3<size;i++) {
        if(data[i]==0 && data[i+1]==0 && data[i+2]==1) {
            unsigned type=data[i+3]&31;
            if(type==7)mask|=1;
            if(type==8)mask|=2;
            if(type==5)mask|=4;
            /* The rest of the AU cannot change this predicate. In particular,
             * do not byte-scan an entire uncached coded DMA buffer. */
            if(!first || mask==7)return true;
            seen=true;i+=2;
        } else if(!seen && data[i]!=0)return false;
    }
    return seen && (!first || mask==7);
}
int h264_encoder_next(struct h264_encoder *e,struct h264_access_unit *au)
{
    if(!e || !au){errno=EINVAL;return -1;}
    struct v4l2_buffer b={.type=V4L2_BUF_TYPE_VIDEO_CAPTURE,.memory=V4L2_MEMORY_MMAP};
    if(encoder_ioctl(e->fd,VIDIOC_DQBUF,&b)<0)return errno==EAGAIN?0:-1;
    if(b.index>=e->nc || e->cap[b.index].busy){errno=EPROTO;return -1;}
    e->cap[b.index].busy=true;
    if(!b.bytesused || b.bytesused>e->cap[b.index].length || b.bytesused>SC130_H264_MAX_AU ||
       (b.flags&V4L2_BUF_FLAG_ERROR) || (e->first && !(b.flags&V4L2_BUF_FLAG_KEYFRAME)) ||
       !encoder_annex_b(e->cap[b.index].data,b.bytesused,e->first ||
                       (b.flags&V4L2_BUF_FLAG_KEYFRAME))){errno=EPROTO;return -1;}
    e->first=false;
    *au=(struct h264_access_unit){.data=e->cap[b.index].data,.size=b.bytesused,.index=b.index,
        .timestamp_ns=(uint64_t)b.timestamp.tv_sec*1000000000+(uint64_t)b.timestamp.tv_usec*1000,
        .keyframe=!!(b.flags&V4L2_BUF_FLAG_KEYFRAME)};
    return 1;
}
