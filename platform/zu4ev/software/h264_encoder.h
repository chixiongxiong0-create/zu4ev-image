#ifndef H264_ENCODER_H
#define H264_ENCODER_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
struct h264_encoder;
struct h264_access_unit { const uint8_t *data; size_t size; unsigned index; uint64_t timestamp_ns; bool keyframe; };
struct h264_encoder *h264_encoder_open(const char *,unsigned,unsigned);
struct h264_encoder *h264_encoder_open_nv12(const char *,const char *,unsigned,unsigned);
int h264_encoder_pump_nv12(struct h264_encoder *);
int h264_encoder_capture_fd(struct h264_encoder *);
int h264_encoder_fd(struct h264_encoder *);
int h264_encoder_submit(struct h264_encoder *,const uint8_t *,size_t,uint32_t,uint64_t);
int h264_encoder_next(struct h264_encoder *,struct h264_access_unit *);
int h264_encoder_release(struct h264_encoder *,unsigned);
void h264_encoder_close(struct h264_encoder *);
#endif
