#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define RAW_WIDTH 1280U
#define RAW_HEIGHT 1024U
#define RAW_BYTES (RAW_WIDTH * RAW_HEIGHT * 2U)

int main(int argc, char **ppArgv)
{
    FILE *pFile;
    uint64_t sum = 0;
    uint64_t left = 0;
    uint64_t right = 0;
    unsigned int minValue = 1023;
    unsigned int maxValue = 0;
    unsigned int invalid = 0;
    unsigned int i;
    int lo;
    int hi;
    unsigned int value;
    if (2 != argc)
    {
        fprintf(stderr, "usage: raw10check FILE\n");
        return 2;
    }
    pFile = fopen(ppArgv[1], "rb");
    if (NULL == pFile)
    {
        perror("open");
        return 1;
    }
    for (i = 0; i < RAW_WIDTH * RAW_HEIGHT; ++i)
    {
        lo = fgetc(pFile);
        hi = fgetc(pFile);
        if (EOF == lo || EOF == hi)
        {
            fprintf(stderr, "truncated frame at sample %u\n", i);
            fclose(pFile);
            return 1;
        }
        value = (unsigned int)lo | ((unsigned int)hi << 8);
        if (value > 1023U)
        {
            ++invalid;
        }
        if (value < minValue)
        {
            minValue = value;
        }
        if (value > maxValue)
        {
            maxValue = value;
        }
        sum += value;
        if ((i % RAW_WIDTH) < RAW_WIDTH / 2U)
        {
            left += value;
        }
        else
        {
            right += value;
        }
    }
    if (EOF != fgetc(pFile) || ferror(pFile))
    {
        fprintf(stderr, "extra data or read failure\n");
        fclose(pFile);
        return 1;
    }
    fclose(pFile);
    printf("size=%u min=%u max=%u mean=%.2f left=%.2f right=%.2f invalid=%u\n",
           RAW_BYTES, minValue, maxValue, (double)sum / (RAW_WIDTH * RAW_HEIGHT),
           (double)left / (RAW_WIDTH * RAW_HEIGHT / 2U),
           (double)right / (RAW_WIDTH * RAW_HEIGHT / 2U), invalid);
    return 0U == invalid ? 0 : 1;
} /* end of main */
