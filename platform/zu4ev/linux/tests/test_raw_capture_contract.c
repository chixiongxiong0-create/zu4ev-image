#include <assert.h>
#include <stdio.h>
#include <raw_capture_contract.h>

int main(void)
{
    assert(sc130_raw_result_valid(1, 1, 7, 7, 655360, 1024, 5, 2621440));
    assert(!sc130_raw_result_valid(0, 1, 7, 7, 655360, 1024, 5, 2621440));
    assert(!sc130_raw_result_valid(1, 4, 7, 7, 655360, 1024, 5, 2621440));
    assert(!sc130_raw_result_valid(1, 1, 7, 8, 655360, 1024, 5, 2621440));
    assert(!sc130_raw_result_valid(1, 1, 7, 7, 655359, 1024, 5, 2621440));
    assert(!sc130_raw_result_valid(1, 1, 7, 7, 655360, 1023, 5, 2621440));
    assert(!sc130_raw_result_valid(1, 1, 7, 7, 655360, 1024, 7, 2621440));
    assert(!sc130_raw_result_valid(1, 1, 7, 7, 655360, 1024, 4, 2621440));
    assert(!sc130_raw_result_valid(1, 1, 7, 7, 655360, 1024, 5, 2621424));
    puts("RAW_CAPTURE_CONTRACT_PASS");
    return 0;
}
