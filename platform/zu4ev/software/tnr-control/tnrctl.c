#define _DEFAULT_SOURCE
#define _FILE_OFFSET_BITS 64
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
static volatile uint32_t *mm;
static void die(const char *s) { fprintf(stderr,"%s\n",s); exit(1); }
static uint64_t number(const char *s, uint64_t max) {
 char *e; errno=0;
 if(!*s || *s=='-' || *s=='+' || *s==' ' || *s=='\t' || *s=='\n') die("invalid unsigned number");
 uint64_t v=strtoull(s,&e,s[0]=='0'&&(s[1]=='x'||s[1]=='X')?16:10);
 if(errno || *e || e==s || v>max) die("number out of range");
 return v;
}
static uint32_t rd(unsigned o) { uint32_t v=mm[o/4]; __sync_synchronize(); return v; }
static void wr(unsigned o,uint32_t v) { __sync_synchronize(); mm[o/4]=v; __sync_synchronize(); }
static int64_t now_ns(void) {
 struct timespec t; if(clock_gettime(CLOCK_MONOTONIC,&t)) { perror("clock_gettime"); exit(1); }
 return (int64_t)t.tv_sec*1000000000LL+t.tv_nsec;
}
static void pause_poll(void) {
 struct timespec t={0,1000000};
 if(nanosleep(&t,NULL)&&errno!=EINTR) { perror("nanosleep"); exit(1); }
}
static void apply_wait(uint32_t command) {
 if(rd(12)&1) die("apply pending; inspect status before retrying");
 if((command&1) && rd(0x18)>=rd(0x1c)) die("motion-low must be less than motion-high");
 uint32_t expected=rd(0x24)+1U;
 int64_t end=now_ns()+1000000000LL;
 wr(0x20,command);
 for(;;) {
  if(!(rd(12)&1) && rd(0x24)==expected) { printf("applied_seq=%" PRIu32 "\n",expected); return; }
  if(now_ns()>=end) die("apply timed out after 1000ms; request may still be pending; inspect status before retrying");
  pause_poll();
 }
}
static void memtest(void) {
 uint32_t s=rd(12);
 if(rd(0x40) || !(s&2) || (s&17)) die("memtest requires active enable=0, calibrated, no pending apply or running test");
 int saw_start=!(s&32);
 int64_t end=now_ns()+10000000000LL;
 wr(0x20,4);
 for(;;) {
  s=rd(12);
  if((s&16)||!(s&32)) saw_start=1;
  if(saw_start && (s&32) && !(s&16)) {
   uint32_t errors=rd(0x50);
   printf("memtest_done=1 errors=%" PRIu32 "\n",errors);
   if(errors) die("memory test failed");
   return;
  }
  if(now_ns()>=end) die("memtest timed out after 10s (or start not observed); inspect status before retrying");
  pause_poll();
 }
}
static void help(void) {
 puts("tnrctl [--base PHYS] [--dev PATH] [--lock PATH] COMMAND\n"
 "Default: 0xA0050000, /dev/mem, /run/lock/tnrctl.lock; 64KiB mapping.\n"
 "Options precede command; numbers decimal or 0x hexadecimal.\n"
 " status | read OFFSET [COUNT] | write OFFSET VALUE\n"
 " set enable 0..1 | set alpha 0..256 | set motion-low 0..254 | set motion-high 1..255\n"
 " apply | clear | enable | bypass | memtest\n"
 "apply/clear/enable/bypass wait up to 1s; memtest waits up to 10s.\n"
 "Raw accesses bypass guards; invalid hardware accesses may cause SIGBUS.\n"
 "All controllers must share this advisory lock. Clear history after upstream LTM changes.");
}
int main(int argc,char **argv) {
 uint64_t base=0xa0050000ULL;
 const char *dev="/dev/mem",*lock="/run/lock/tnrctl.lock";
 int default_lock=1,i=1;
 for(;i<argc&&!strncmp(argv[i],"--",2);i++) {
  if(!strcmp(argv[i],"--help")) { help(); return 0; }
  if(i+1>=argc) die("option requires value");
  if(!strcmp(argv[i],"--base")) base=number(argv[++i],INT64_MAX-65536);
  else if(!strcmp(argv[i],"--dev")) dev=argv[++i];
  else if(!strcmp(argv[i],"--lock")) { lock=argv[++i]; default_lock=0; }
  else die("unknown option");
 }
 if(i==argc) { help(); return 1; }
 const char *c=argv[i++]; int n=argc-i,action=0;
 unsigned off=0,count=1; uint32_t value=0;
 if(!strcmp(c,"help")&&n==0) { help(); return 0; }
 if(!strcmp(c,"status")&&n==0) action=1;
 else if(!strcmp(c,"read")&&(n==1||n==2)) {
  action=2; off=(unsigned)number(argv[i],65532);
  count=n==2?(unsigned)number(argv[i+1],16384):1;
  if((off&3)||!count||count>(65536-off)/4) die("unaligned or out of span");
 } else if(!strcmp(c,"write")&&n==2) {
  action=3; off=(unsigned)number(argv[i],65532);
  if(off&3) die("unaligned offset");
  value=(uint32_t)number(argv[i+1],UINT32_MAX);
 } else if(!strcmp(c,"set")&&n==2) {
  action=4;
  if(!strcmp(argv[i],"enable")) { off=0x10; value=(uint32_t)number(argv[i+1],1); }
  else if(!strcmp(argv[i],"alpha")) { off=0x14; value=(uint32_t)number(argv[i+1],256); }
  else if(!strcmp(argv[i],"motion-low")) { off=0x18; value=(uint32_t)number(argv[i+1],254); }
  else if(!strcmp(argv[i],"motion-high")) { off=0x1c; value=(uint32_t)number(argv[i+1],255); if(!value) die("motion-high must be 1..255"); }
  else die("unknown setting");
 } else if(!strcmp(c,"apply")&&n==0) { action=5; value=1; }
 else if(!strcmp(c,"clear")&&n==0) { action=5; value=2; }
 else if(!strcmp(c,"enable")&&n==0) { action=6; value=1; }
 else if(!strcmp(c,"bypass")&&n==0) { action=6; value=0; }
 else if(!strcmp(c,"memtest")&&n==0) action=7;
 else die("invalid command/arguments; use --help");
 long page=sysconf(_SC_PAGESIZE);
 if(page<=0||base%(uint64_t)page) die("base must be page aligned");
 if(default_lock&&mkdir("/run/lock",0755)&&errno!=EEXIST) { perror("mkdir /run/lock"); return 1; }
 int lf=open(lock,O_CREAT|O_RDWR|O_CLOEXEC,0600);
 if(lf<0) { perror("lock open"); return 1; }
 if(flock(lf,LOCK_EX|LOCK_NB)) { perror("lock busy"); return 1; }
 int fd=open(dev,O_RDWR|O_SYNC|O_CLOEXEC);
 if(fd<0) { perror("device open"); return 1; }
 struct stat st;
 if(fstat(fd,&st)) { perror("fstat"); return 1; }
 if(S_ISREG(st.st_mode)&&(uint64_t)st.st_size<base+65536) die("backing file smaller than mapping");
 void *p=mmap(NULL,65536,PROT_READ|PROT_WRITE,MAP_SHARED,fd,(off_t)base);
 if(p==MAP_FAILED) { perror("mmap"); return 1; }
 mm=p;
 if(action==1) {
  static const char *names[]={"id","version","caps","status","shadow_enable","shadow_alpha","shadow_motion_low","shadow_motion_high","command","applied_seq","frames","motion_pixels","filtered_pixels","faults","ddr_errors","fifo_level","active_enable","active_alpha","active_motion_low","active_motion_high","memtest_errors","width","height","frame_bytes","history_base0","history_base1"};
  for(unsigned j=0;j<sizeof(names)/sizeof(names[0]);j++) printf("%-24s 0x%08" PRIx32 "\n",names[j],rd(j*4));
  uint32_t s=rd(12);
  printf("pending=%u calibrated=%u history_valid=%u busy=%u memtest_busy=%u memtest_done=%u\n",s&1,(s>>1)&1,(s>>2)&1,(s>>3)&1,(s>>4)&1,(s>>5)&1);
 } else if(action==2) {
  for(unsigned j=0;j<count;j++) printf("0x%04x: 0x%08" PRIx32 "\n",off+4*j,rd(off+4*j));
 } else if(action==3) wr(off,value);
 else {
  if(rd(12)&1) die("apply pending; retry after safe boundary");
  if(action==4) wr(off,value);
  else if(action==5) apply_wait(value);
  else if(action==6) {
   if(rd(0x18)>=rd(0x1c)) die("motion-low must be less than motion-high");
   wr(0x10,value); apply_wait(1);
  } else memtest();
 }
 munmap(p,65536); close(fd); close(lf); return 0;
}

