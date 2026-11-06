#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <errno.h>
#include <string.h>
#include <time.h>
#include <fcntl.h>
#include <unistd.h>
#include <glob.h>
#include <poll.h>
#include <sys/ioctl.h>
#include <linux/videodev2.h>
#include "h264_encoder.h"
static uint64_t ns(void) {
    struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);
    return (uint64_t)t.tv_sec*1000000000ull+t.tv_nsec;
}
static int layout(void) {
    glob_t paths={0};int ret=1;
    if(glob("/dev/video*",0,NULL,&paths))return 1;
    for(size_t i=0;i<paths.gl_pathc;i++) {
        int fd=open(paths.gl_pathv[i],O_RDWR|O_CLOEXEC);
        if(fd<0)continue;
        struct v4l2_capability c={0};
        if(ioctl(fd,VIDIOC_QUERYCAP,&c)<0 || strcmp((char *)c.driver,"allegro")){close(fd);continue;}
        struct v4l2_format f={.type=V4L2_BUF_TYPE_VIDEO_OUTPUT};
        f.fmt.pix.width=1280;f.fmt.pix.height=1024;f.fmt.pix.pixelformat=V4L2_PIX_FMT_NV12;
        if(ioctl(fd,VIDIOC_S_FMT,&f)<0){perror("NV12 S_FMT");close(fd);break;}
        struct v4l2_requestbuffers b={.type=f.type,.count=4,.memory=V4L2_MEMORY_DMABUF};
        if(ioctl(fd,VIDIOC_REQBUFS,&b)<0){perror("DMABUF REQBUFS");close(fd);break;}
        printf("VCU_LAYOUT device=%s width=%u height=%u stride=%u size=%u dmabuf_slots=%u\n",paths.gl_pathv[i],f.fmt.pix.width,f.fmt.pix.height,f.fmt.pix.bytesperline,f.fmt.pix.sizeimage,b.count);
        ret=0;close(fd);break;
    }
    globfree(&paths);return ret;
}
int main(int argc,char **argv) {
    if(argc==2 && !strcmp(argv[1],"--layout-only"))return layout();
    if(argc!=3){fprintf(stderr,"usage: %s --layout-only | FRAMES OUTPUT.h264\n",argv[0]);return 2;}
    char *end;unsigned long limit=strtoul(argv[1],&end,10);
    if(*end||!limit||limit>12000)return 2;
    FILE *out=fopen(argv[2],"wb");if(!out){perror("output");return 1;}
    struct h264_encoder *e=h264_encoder_open_nv12(NULL,"/dev/sc130-nv12",120,20000000);
    if(!e){perror("NV12 VCU open");fclose(out);return 1;}
    unsigned count=0;size_t bytes=0;uint64_t start=ns(),deadline=start+30000000000ull;int result=1;
    while(count<limit && ns()<deadline) {
        if(h264_encoder_pump_nv12(e)<0){perror("NV12 pump");goto done;}
        struct h264_access_unit au;
        int ready=h264_encoder_next(e,&au);
        if(ready<0){perror("coded DQBUF");goto done;}
        if(ready) {
            if(fwrite(au.data,1,au.size,out)!=au.size){perror("coded write");goto done;}
            bytes+=au.size;count++;
            if(h264_encoder_release(e,au.index)<0){perror("coded release");goto done;}
        } else {
            struct pollfd f[2]={{h264_encoder_fd(e),POLLIN,0},{h264_encoder_capture_fd(e),POLLIN,0}};
            if(poll(f,2,50)<0 && errno!=EINTR){perror("poll");goto done;}
        }
    }
    if(count==limit){printf("NV12_VCU_PROBE_PASS frames=%u bytes=%zu wall_ms=%.3f\n",count,bytes,(ns()-start)/1e6);result=0;}
    else fprintf(stderr,"NV12_VCU_PROBE_TIMEOUT frames=%u\n",count);
done:
    h264_encoder_close(e);if(fclose(out))result=1;return result;
}
