#include <assert.h>
#include <stdio.h>
#include "../capture_broker.h"

int main(void)
{
    for(unsigned order=0;order<2;order++) {
        struct capture_broker b;broker_init(&b,8);
        assert(!broker_dequeue(&b,2));
        assert(!broker_dp_hold(&b,2));
        assert(!broker_encoder_hold(&b,2));
        assert(broker_encoder_hold(&b,2)<0);
        assert(!broker_can_queue(&b,2));
        assert(broker_dequeue(&b,2)<0);
        if(order)assert(!broker_dp_release(&b,2));
        else assert(!broker_encoder_release(&b,2));
        assert(!broker_can_queue(&b,2));
        if(order)assert(!broker_encoder_release(&b,2));
        else assert(!broker_dp_release(&b,2));
        assert(broker_can_queue(&b,2));
        assert(broker_encoder_release(&b,2)<0);
        assert(!broker_queue(&b,2));
        assert(broker_encoder_hold(&b,2)<0);
        assert(broker_encoder_hold(&b,16)<0);
    }
    /* Disconnect may release legacy USB, never another reader. */
    struct capture_broker b;broker_init(&b,8);
    assert(!broker_dequeue(&b,3));assert(!broker_latest(&b,3));
    assert(!broker_dp_hold(&b,3));assert(!broker_encoder_hold(&b,3));
    assert(!broker_usb_hold(&b,3));assert(!broker_usb_release(&b,3));
    assert(b.dp[3] && b.encoder[3] && !broker_can_queue(&b,3));
    puts("DP/encoder independent completion, capture exclusion and USB stop: PASS");
    return 0;
}
