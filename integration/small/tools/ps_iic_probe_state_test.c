/* Exercise real guarded state transactions against a tiny IIC register model. */
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
static uint32_t ps_iic_test_read(unsigned off);
static void ps_iic_test_write(unsigned off,uint32_t value);
#define PS_IIC_PROBE_TEST
#define main probe_main
#include "ps_iic_probe.c"
#undef main
#include <assert.h>

static uint8_t fifo[3],sensor_stream;
static unsigned fifo_size,state_writes,transactions;
static int bad_readback,nack;
static uint32_t ps_iic_test_read(unsigned off)
{
    if(off==ISR) return nack?4:COMPLETE;
    if(off==SR) return RX_VALID;
    if(off==DATA) return bad_readback?(sensor_stream^1):sensor_stream;
    return 0;
}
static void ps_iic_test_write(unsigned off,uint32_t value)
{
    if(off==CR && (value&CLEAR_FIFO)) fifo_size=0;
    if(off==DATA) { assert(fifo_size<3); fifo[fifo_size++]=(uint8_t)value; }
    if(off==ADDR) {
        assert(value==0x30); ++transactions;
        if(fifo_size==3) {
            assert(fifo[0]==1 && fifo[1]==0 && fifo[2]<=1);
            ++state_writes; sensor_stream=fifo[2];
        }
    }
}
static void reset_model(uint8_t stream)
{
    fifo_size=state_writes=transactions=0;
    sensor_stream=stream; bad_readback=nack=0; interrupted=0;
}
int main(void)
{
    reset_model(1);
    assert(sensor_state(0,1,0x31,1)==-1 && transactions==0);
    assert(sensor_state(0,2,0x30,1)==-1 && transactions==0);
    assert(sensor_state(0,1,0x30,2)==-1 && transactions==0);
    assert(sensor_state(0,1,0x30,1)==0 && state_writes==1 && sensor_stream==0);
    reset_model(0);
    assert(sensor_state(1,1,0x30,0)==0 && state_writes==1 && sensor_stream==1);
    reset_model(0);
    assert(sensor_state(0,1,0x30,0)==0 && transactions==0);
    reset_model(1);
    assert(sensor_state(1,1,0x30,1)==0 && transactions==0);
    reset_model(1); bad_readback=1;
    assert(sensor_state(0,1,0x30,1)==-1 && state_writes==1);
    reset_model(1); nack=1;
    assert(sensor_state(0,1,0x30,1)==-1 && state_writes==1 && transactions==1);
    puts("PASS: exact ID/state guards, standby/on, no-op, readback failure and NACK without retry.");
    return 0;
}
