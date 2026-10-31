#ifndef TEST_XIICPS_H
#define TEST_XIICPS_H
#include <stdint.h>
typedef uint8_t u8;
typedef struct
{
    unsigned BaseAddress;
    unsigned InputClockHz;
} XIicPs_Config;
typedef struct
{
    unsigned unused;
} XIicPs;
#define XIICPS_REP_START_OPTION 1U
extern int XIicPs_CfgInitialize(XIicPs *pIic, XIicPs_Config *pConfig, unsigned base);
extern int XIicPs_SetSClk(XIicPs *pIic, unsigned hz);
extern int XIicPs_BusIsBusy(XIicPs *pIic);
extern int XIicPs_SetOptions(XIicPs *pIic, unsigned options);
extern int XIicPs_ClearOptions(XIicPs *pIic, unsigned options);
extern int XIicPs_MasterSendPolled(XIicPs *pIic, u8 *pData, int length, unsigned address);
extern int XIicPs_MasterRecvPolled(XIicPs *pIic, u8 *pData, int length, unsigned address);
extern void XIicPs_Reset(XIicPs *pIic);
#endif
