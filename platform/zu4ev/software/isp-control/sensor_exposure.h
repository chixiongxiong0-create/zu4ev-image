#ifndef SENSOR_EXPOSURE_H
#define SENSOR_EXPOSURE_H
enum sensor_exposure_result { SENSOR_EXPOSURE_OK, SENSOR_EXPOSURE_RANGE, SENSOR_EXPOSURE_IO, SENSOR_EXPOSURE_VERIFY, SENSOR_EXPOSURE_UNKNOWN };
/* Caller owns the bus exclusively for this whole operation. Callback reads
 * and writes one byte, returning 1 only on ACK and successful STOP. No group
 * hold or frame atomicity is implied. After IO/verification failure, inspect
 * the sensor before reinitializing this state; no rollback is attempted. */
struct sensor_exposure { int (*io)(void *, unsigned, unsigned *, int); void *ctx; int unknown; };
static inline void sensor_exposure_init(struct sensor_exposure *s, int (*io)(void *, unsigned, unsigned *, int), void *ctx) { s->io=io;s->ctx=ctx;s->unknown=0; }
static inline enum sensor_exposure_result sensor_exposure_set(struct sensor_exposure *s, unsigned code) {
 unsigned hi,lo,mode,v,check;
 if(s->unknown) return SENSOR_EXPOSURE_UNKNOWN;
 if(!code || code>65535 || (code>=16 && (code&15))) return SENSOR_EXPOSURE_RANGE;
 if(!s->io(s->ctx,0x320e,&hi,0) || !s->io(s->ctx,0x320f,&lo,0)) goto failed;
 unsigned vts=(hi<<8)|lo;
 if(vts<=4 || (code>>4)>vts-4) return SENSOR_EXPOSURE_RANGE;
 if(!s->io(s->ctx,0x3e03,&mode,0)) goto failed;
 if(!(mode&1)) { v=mode|1; if(!s->io(s->ctx,0x3e03,&v,1)) goto failed; }
 v=code>>8;if(!s->io(s->ctx,0x3e01,&v,1)) goto failed;
 v=code&255;if(!s->io(s->ctx,0x3e02,&v,1)) goto failed;
 if(!s->io(s->ctx,0x3e03,&check,0)) goto failed;
 if(check!=(mode|1)) goto mismatch;
 if(!s->io(s->ctx,0x3e01,&check,0)) goto failed;
 if(check!=(code>>8)) goto mismatch;
 if(!s->io(s->ctx,0x3e02,&check,0)) goto failed;
 if(check!=(code&255)) goto mismatch;
 return SENSOR_EXPOSURE_OK;
failed:
 s->unknown=1;return SENSOR_EXPOSURE_IO;
mismatch:
 s->unknown=1;return SENSOR_EXPOSURE_VERIFY;
}
#endif
