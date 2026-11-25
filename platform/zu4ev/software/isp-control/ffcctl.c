#define _POSIX_C_SOURCE 200809L
#define _FILE_OFFSET_BITS 64
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
static volatile uint32_t *mmio;
static void die(const char *s){fprintf(stderr,"ffcctl: %s\n",s);exit(1);}
static unsigned rd(unsigned a){unsigned v=mmio[a/4];__sync_synchronize();return v;}
static void wr(unsigned a,unsigned v){__sync_synchronize();mmio[a/4]=v;__sync_synchronize();}
static unsigned long long ms(void){struct timespec t;if(clock_gettime(CLOCK_MONOTONIC,&t))die("clock");return (unsigned long long)t.tv_sec*1000+t.tv_nsec/1000000;}
static void pause_ms(void){struct timespec t={0,1000000};nanosleep(&t,NULL);}
static void apply(unsigned enable){unsigned seq=rd(0x3014);wr(0x3008,2|enable);unsigned long long end=ms()+2000;while(ms()<end){if(!(rd(0x300c)&2)&&rd(0x3014)!=seq)return;pause_ms();}die("apply timed out; table remains pending, inspect video source");}
int main(int argc,char **argv){
 if(argc<2 || !strcmp(argv[1],"--help")){
  puts("ffcctl status | capture FILE | measure FILE | load MAP | disable\nStop Ibex using ibex_isp_handoff stop first. Requires FFC hardware.\nMap: FFC_MAP1 width height pedestal then ordered packed hex nodes.\nCapture: frozen 32-frame RAW cell sums before FFC. No automatic ownership change.");return argc<2?2:0;
 }
 int measure=!strcmp(argv[1],"measure");
 int status=!strcmp(argv[1],"status"),capture=!strcmp(argv[1],"capture"),load=!strcmp(argv[1],"load"),disable=!strcmp(argv[1],"disable");
 if(!((status||disable)&&argc==2)&&!((capture||measure||load)&&argc==3))die("invalid arguments");
 unsigned values[2048],mw=0,mh=0,ped=0,count=0;
 if(load){
  FILE*f=fopen(argv[2],"r");if(!f)die("open map");char tag[32];
  if(fscanf(f,"%31s %u %u %u",tag,&mw,&mh,&ped)!=4 || strcmp(tag,"FFC_MAP1") || mw!=1280 || mh!=1024 || ped>1023)die("invalid map header");
  count=(mw/32+1)*(mh/32+1);
  for(unsigned i=0;i<count;i++)if(fscanf(f,"%x",&values[i])!=1 || values[i]>0xffffff || !(values[i]>>10))die("invalid/truncated map");
  char extra;if(fscanf(f," %c",&extra)==1)die("trailing map data");fclose(f);
 }
 mkdir("/run/lock",0755);
 int hand=open("/run/ibex_isp_handoff.lock",O_CREAT|O_RDWR,0600);
 if(hand<0 || flock(hand,LOCK_EX|LOCK_NB))die("ownership lock busy");
 int lock=open("/run/lock/ispctl.lock",O_CREAT|O_RDWR,0600);
 if(lock<0 || flock(lock,LOCK_EX|LOCK_NB))die("ISP lock busy");
 int fd=open("/dev/mem",O_RDWR|O_SYNC);if(fd<0)die("open /dev/mem");
 mmio=mmap(NULL,65536,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0xa0040000ULL);
 if(mmio==MAP_FAILED)die("mmap");
 // Ownership CSRs remain accessible when Ibex owns the peripheral. Never read
 // the protected FFC or ISP window until a complete stop/reclaim has succeeded.
 if((rd(0xff00)&1) || (rd(0xff08)&1) || (rd(0xff04)&6))die("Ibex not stopped/reclaimed; run ibex_isp_handoff stop");
 if(rd(0)!=0x49535031 || rd(0x3000)!=0x46464331)die("hardware identity mismatch");
 unsigned geometry=rd(0x3020),nodes=rd(0x301c),step=rd(0x3024);
 unsigned width=geometry&65535,height=geometry>>16;
 if(width!=1280 || height!=1024 || step!=32 || nodes!=((33u<<16)|41u))die("unsupported geometry");
 if(status)printf("FFC enable=%u pending=%u bank=%u seq=%u uploaded=%u pedestal=%u stats=%u frames=%u\n",rd(0x300c)&1,(rd(0x300c)>>1)&1,(rd(0x300c)>>2)&1,rd(0x3014),rd(0x3018),rd(0x3010),rd(0x3044),rd(0x3048));
 if(disable){if(rd(0x300c)&2)die("pending apply");apply(0);puts("FFC_DISABLED");}
 if(capture||measure){
  if(rd(0x3044)&1)die("statistics already busy");
  wr(0x3050,measure?1:0);wr(0x3040,1);
  unsigned long long end=ms()+5000;unsigned state=0;
  do {state=rd(0x3044);if(state&6)break;pause_ms();}while(ms()<end);
  if(state!=2 || rd(0x3048)!=32 || rd(0x304c)!=32768)die("RAW batch failed or timed out; no calibration published");
  FILE*f=fopen(argv[2],"wx");if(!f)die("capture output exists or cannot be created");
  fprintf(f,"FFC_STATS1 %u %u %u %u %u\n",width,height,step,rd(0x3048),rd(0x304c));
  for(unsigned i=0;i<(width/step)*(height/step);i++)fprintf(f,"%u\n",rd(0x6000+4*i));
  if(fclose(f))die("capture output write");
  puts("FFC_CAPTURE_PASS frames=32 raw_samples_per_cell=32768");
 }
 if(load){
  if(rd(0x300c)&2 || rd(0x3018)!=0)die("pending or incomplete upload; disable first before retrying");
  for(unsigned i=0;i<count;i++){wr(0x4000+4*i,values[i]);if(rd(0x4000+4*i)!=values[i] || rd(0x3018)!=i+1)die("coefficient readback mismatch; active table unchanged");}
  wr(0x3010,ped);apply(1);puts("FFC_LOAD_PASS verified coefficients and frame-boundary apply");
 }
 munmap((void*)mmio,65536);close(fd);close(lock);close(hand);return 0;
}
