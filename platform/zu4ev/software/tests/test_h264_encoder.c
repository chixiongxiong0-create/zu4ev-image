#include <assert.h>
#include <stdarg.h>
#include <stdio.h>
#define ioctl encoder_test_ioctl
#define open encoder_test_open
#define close encoder_test_close
#define mmap encoder_test_mmap
#define munmap encoder_test_munmap
#include "../h264_encoder.c"
#undef ioctl
#undef open
#undef close
#undef mmap
#undef munmap

static unsigned selected_fps,selected_level,raw_queued,cap_queued,closed,unmapped;
static unsigned selected_rc,selected_mode,selected_bitrate;
static unsigned selected_peak,selected_cpb;
static int raw_done=-1,cap_done=-1,fail_queue,fail_stop,fail_first_open;
static unsigned reply_size,reply_flags;
static bool cancelled;
static bool reject_cached_input;
int encoder_test_open(const char *path,int flags,...)
{ (void)flags;assert(!strcmp(path,"/dev/encoder-test"));if(fail_first_open){errno=ENOENT;return -1;}cancelled=false;return 9; }
int encoder_test_close(int fd) { assert(fd==9);closed++;cancelled=true;return 0; }
void *encoder_test_mmap(void *addr,size_t length,int prot,int flags,int fd,off_t offset)
{ (void)addr;(void)prot;(void)flags;(void)offset;assert(fd==9);return calloc(1,length); }
int encoder_test_munmap(void *p,size_t length)
{ (void)length;assert(cancelled);unmapped++;free(p);return 0; }
int encoder_test_ioctl(int fd,unsigned long op,...)
{
    assert(fd==9);va_list args;va_start(args,op);void *arg=va_arg(args,void *);va_end(args);
    if(op==VIDIOC_QUERYCAP) {
        struct v4l2_capability *c=arg;strcpy((char *)c->driver,"allegro");
        c->capabilities=V4L2_CAP_VIDEO_M2M|V4L2_CAP_STREAMING;return 0;
    }
    if(op==VIDIOC_S_FMT) {
        struct v4l2_format *f=arg;
        if(f->type==V4L2_BUF_TYPE_VIDEO_OUTPUT){f->fmt.pix.bytesperline=1312;f->fmt.pix.sizeimage=1312*1536;}
        else f->fmt.pix.sizeimage=1311104;
        return 0;
    }
    if(op==VIDIOC_S_CTRL) {
        struct v4l2_control *c=arg;
        if(c->id==V4L2_CID_MPEG_VIDEO_H264_LEVEL)selected_level=(unsigned)c->value;
        if(c->id==V4L2_CID_MPEG_VIDEO_FRAME_RC_ENABLE)selected_rc=(unsigned)c->value;
        if(c->id==V4L2_CID_MPEG_VIDEO_BITRATE_MODE)selected_mode=(unsigned)c->value;
        if(c->id==V4L2_CID_MPEG_VIDEO_BITRATE)selected_bitrate=(unsigned)c->value;
        if(c->id==V4L2_CID_MPEG_VIDEO_BITRATE_PEAK){assert(selected_mode==V4L2_MPEG_VIDEO_BITRATE_MODE_VBR);selected_peak=(unsigned)c->value;}
        if(c->id==V4L2_CID_MPEG_VIDEO_H264_CPB_SIZE)selected_cpb=(unsigned)c->value;
        return 0;
    }
    if(op==VIDIOC_S_PARM){selected_fps=((struct v4l2_streamparm *)arg)->parm.output.timeperframe.denominator;return 0;}
    if(op==VIDIOC_REQBUFS){
        struct v4l2_requestbuffers *r=arg;
        if(reject_cached_input && r->type==V4L2_BUF_TYPE_VIDEO_OUTPUT)r->flags=0;
        r->count=4;return 0;
    }
    if(op==VIDIOC_QUERYBUF) {
        struct v4l2_buffer *b=arg;b->length=b->type==V4L2_BUF_TYPE_VIDEO_OUTPUT?1312*1536:1314816;return 0;
    }
    if(op==VIDIOC_STREAMON)return 0;
    if(op==VIDIOC_STREAMOFF){if(fail_stop){errno=EIO;return -1;}return 0;}
    if(op==VIDIOC_QBUF) {
        struct v4l2_buffer *b=arg;
        if(fail_queue){errno=EIO;return -1;}
        if(b->type==V4L2_BUF_TYPE_VIDEO_OUTPUT){assert(b->bytesused==1312*1536);raw_queued++;}
        else cap_queued++;
        return 0;
    }
    if(op==VIDIOC_DQBUF) {
        struct v4l2_buffer *b=arg;
        int *done=b->type==V4L2_BUF_TYPE_VIDEO_OUTPUT?&raw_done:&cap_done;
        if(*done<0){errno=EAGAIN;return -1;}
        b->index=(unsigned)*done;*done=-1;b->bytesused=reply_size;b->flags=reply_flags;
        b->timestamp.tv_sec=7;b->timestamp.tv_usec=123;return 0;
    }
    assert(0);errno=EINVAL;return -1;
}
static void conversion_test(void)
{
    uint8_t *source=malloc(SC130_SIZE),*copy=malloc(SC130_SIZE);
    const unsigned stride=1312,size=stride*1536+64;
    uint8_t *storage=malloc(size+32);assert(source && copy && storage);
    for(unsigned i=0;i<SC130_SIZE;i++)source[i]=(uint8_t)((i*13+i/SC130_STRIDE*7)%256);
    memcpy(copy,source,SC130_SIZE);memset(storage,0xa5,size+32);
    encoder_convert(storage+16,stride,size,source);
    assert(!memcmp(copy,source,SC130_SIZE));
    for(unsigned i=0;i<16;i++)assert(storage[i]==0xa5 && storage[size+16+i]==0xa5);
    uint8_t *dest=storage+16;
    for(unsigned y=0;y<SC130_HEIGHT;y++)for(unsigned x=0;x<SC130_WIDTH;x++)
        assert(dest[y*stride+x]==source[y*SC130_STRIDE+2*x]);
    for(unsigned y=0;y<SC130_HEIGHT;y+=2)for(unsigned x=0;x<SC130_WIDTH;x++)
        assert(dest[SC130_HEIGHT*stride+y/2*stride+x]==(uint8_t)(((unsigned)source[y*SC130_STRIDE+2*x+1]+source[(y+1)*SC130_STRIDE+2*x+1]+1)/2));
    for(unsigned y=0;y<SC130_HEIGHT;y++)for(unsigned x=SC130_WIDTH;x<stride;x++)assert(dest[y*stride+x]==0);
    for(unsigned y=0;y<SC130_HEIGHT/2;y++)for(unsigned x=SC130_WIDTH;x<stride;x++)assert(dest[SC130_HEIGHT*stride+y*stride+x]==128);
    for(unsigned i=stride*1536;i<size;i++)assert(!dest[i]);
    free(source);free(copy);free(storage);
}
int main(void)
{
    conversion_test();
    const uint8_t idr[]={0,0,0,1,0x67,0x42,0,0,1,0x68,0xce,0,0,1,0x65,0x88};
    const uint8_t pframe[]={0,0,0,1,0x41,0x9a};
    assert(encoder_annex_b(idr,sizeof(idr),true));
    assert(!encoder_annex_b(pframe,sizeof(pframe),true));
    assert(encoder_annex_b(pframe,sizeof(pframe),false));
    assert(!h264_encoder_open("/dev/encoder-test",30,20000000) && errno==EINVAL);
    fail_first_open=1;assert(!h264_encoder_open("/dev/encoder-test",120,20000000) && errno==ENOENT);fail_first_open=0;
    struct h264_encoder *e=h264_encoder_open("/dev/encoder-test",120,20000000);assert(e);
    assert(selected_fps==120 && selected_level==V4L2_MPEG_VIDEO_H264_LEVEL_5_1 && cap_queued==4);
    assert(selected_rc==1 && selected_mode==V4L2_MPEG_VIDEO_BITRATE_MODE_CBR && selected_bitrate==20000000);
    assert(selected_peak==selected_bitrate && selected_cpb==2500);
    uint8_t *source=calloc(1,SC130_SIZE);assert(source);
    for(unsigned i=0;i<4;i++)assert(h264_encoder_submit(e,source,SC130_SIZE,i,100+i)==1);
    assert(raw_queued==4 && !h264_encoder_submit(e,source,SC130_SIZE,4,200));
    raw_done=1;assert(h264_encoder_submit(e,source,SC130_SIZE,4,200)==1);
    raw_done=1;fail_queue=1;assert(h264_encoder_submit(e,source,SC130_SIZE,5,200)<0 && !e->raw[1].busy);fail_queue=0;
    assert(h264_encoder_submit(e,source,1,5,200)<0);
    struct h264_access_unit au;assert(!h264_encoder_next(e,&au));
    memcpy(e->cap[2].data,idr,sizeof(idr));cap_done=2;reply_size=sizeof(idr);reply_flags=V4L2_BUF_FLAG_KEYFRAME;
    assert(h264_encoder_next(e,&au)==1 && au.index==2 && au.size==sizeof(idr) && au.timestamp_ns==7000123000ull);
    fail_queue=1;assert(h264_encoder_release(e,2)<0 && e->cap[2].busy);fail_queue=0;
    assert(!h264_encoder_release(e,2));assert(h264_encoder_release(e,2)<0);
    /* Later flagged keyframes must also be independently decodable. */
    memcpy(e->cap[3].data,pframe,sizeof(pframe));cap_done=3;reply_size=sizeof(pframe);reply_flags=V4L2_BUF_FLAG_KEYFRAME;
    assert(h264_encoder_next(e,&au)<0 && errno==EPROTO);
    assert(!h264_encoder_release(e,3));
    memcpy(e->cap[0].data,pframe,sizeof(pframe));cap_done=0;reply_size=sizeof(pframe);reply_flags=V4L2_BUF_FLAG_PFRAME;
    assert(h264_encoder_next(e,&au)==1 && !au.keyframe && au.index==0);
    cap_done=0;assert(h264_encoder_next(e,&au)<0 && errno==EPROTO);
    fail_stop=1;h264_encoder_close(e);assert(closed==1 && unmapped==8);
    fail_stop=0;e=h264_encoder_open("/dev/encoder-test",60,20000000);assert(e);
    memcpy(e->cap[0].data,pframe,sizeof(pframe));cap_done=0;reply_size=sizeof(pframe);reply_flags=V4L2_BUF_FLAG_KEYFRAME;
    assert(h264_encoder_next(e,&au)<0 && errno==EPROTO);h264_encoder_close(e);
    reject_cached_input=true;
    assert(!h264_encoder_open("/dev/encoder-test",120,20000000) && errno==ENOTSUP);
    free(source);
    puts("H264 private NV12 conversion, 120/level5.1, queue bounds, AnnexB/IDR and cancellation: PASS");
    return 0;
}
