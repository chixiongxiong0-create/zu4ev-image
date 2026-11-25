#include "../uvc_core.h"
#include <assert.h>
#include <endian.h>
#include <stdio.h>
#include <string.h>
static unsigned le32(const uint8_t *p)
{ return p[0] | p[1]<<8 | p[2]<<16 | (unsigned)p[3]<<24; }
int main(void)
{
    struct uvc_session s;
    struct uvc_request_data d;
    struct usb_ctrlrequest r={.bRequestType=0x21,.bRequest=1,
        .wValue=htole16(0x200),.wIndex=htole16(1),.wLength=htole16(34)};
    uvc_session_init_h264(&s,true,1);
    assert(s.h264 && le32(s.probe+18)==SC130_H264_MAX_AU);
    assert(le32(s.probe+4)==83333);
    assert(le32(s.probe+22)==8192 && le32(s.commit+22)==8192);
    r.bRequestType=0xa1;r.bRequest=0x83;
    assert(uvc_handle_setup(&s,&r,&d)==0 && d.length==34);
    assert(le32(d.data+4)==166667 && le32(d.data+18)==SC130_H264_MAX_AU);
    assert(le32(d.data+22)==8192);
    r.bRequest=0x82;
    assert(uvc_handle_setup(&s,&r,&d)==0 && le32(d.data+4)==83333);
    r.bRequestType=0x21;r.bRequest=1;
    assert(uvc_handle_setup(&s,&r,&d)==0);
    memcpy(d.data,s.probe,34); d.length=34;
    d.data[4]=0x0b;d.data[5]=0x8b;d.data[6]=2;d.data[7]=0; /* 166667 */
    assert(uvc_handle_data(&s,&d)==0 && s.fps==60);
    s.superspeed=true;assert(uvc_session_start(&s)==0);
    uvc_session_stop(&s,true);
    assert(s.h264 && !s.committed && !s.streaming && !s.superspeed);
    assert(le32(s.probe+18)==SC130_H264_MAX_AU);
    uvc_session_init(&s,true,1);assert(!s.h264);
    assert(le32(s.probe+22)==49152);
    uvc_session_init_h264(&s,false,1);
    assert(le32(s.probe+4)==166667);
    assert(uvc_handle_setup(&s,&r,&d)==0);
    memcpy(d.data,s.probe,34); d.length=34;
    d.data[4]=0x85;d.data[5]=0x45;d.data[6]=1;d.data[7]=0; /* 83333 */
    assert(uvc_handle_data(&s,&d)<0 && !s.committed);
    puts("TEST_PASS H264 34-byte probe, 60/120, disconnect preserves format");
}
