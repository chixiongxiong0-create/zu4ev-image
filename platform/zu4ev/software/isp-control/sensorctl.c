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
#include <unistd.h>
#include <signal.h>
#include <time.h>
#include "sensor_exposure.h"
static volatile uint32_t *gpio;
static unsigned delay_us = 50;
static int resident_timing;
static uint64_t monotonic_ns(void);
static void edge_delay(void) {
  if(!resident_timing) { usleep(delay_us); return; }
  uint64_t until=monotonic_ns()+(uint64_t)delay_us*1000;
  while(monotonic_ns()<until) {}
}
static void die(const char *s) {
  fprintf(stderr, "%s\n", s);
  exit(1);
}
static uint64_t number(const char *s, uint64_t max) {
  char *e;
  errno = 0;
  if (!*s || *s == '-')
    die("invalid unsigned number");
  uint64_t v =
      strtoull(s, &e, s[0] == '0' && (s[1] == 'x' || s[1] == 'X') ? 16 : 10);
  if (errno || *e || v > max)
    die("number out of range");
  return v;
}
static unsigned rd(unsigned off) {
  unsigned v = gpio[off / 4];
  __sync_synchronize();
  return v;
}
static void wr(unsigned off, unsigned v) {
  __sync_synchronize();
  gpio[off / 4] = v;
  __sync_synchronize();
}
/* Only OEN bits 0/1 change. DATA_LSW mask writes only bits 0/1 low. */
static void pin(unsigned bit, int high) {
  unsigned v = rd(0x2c8);
  wr(0x2c8, high ? (v & ~bit) : (v | bit));
  if (!high)
    wr(0x18, 0xfffc0000U);
  edge_delay();
}
static int level(unsigned bit) { return (rd(0x6c) & bit) != 0; }
static int clock_high(void) {
  pin(1, 1);
  for (unsigned i = 0; i < 100; i++) {
    if (level(1))
      return 1;
    usleep(delay_us);
  }
  fprintf(stderr, "I2C clock stretch timeout\n");
  return 0;
}
static int stop(void) {
  pin(1, 0);
  pin(2, 0);
  int ok = clock_high();
  pin(2, 1);
  return ok;
}
static int start(void) {
  pin(2, 1);
  if (!clock_high())
    return 0;
  if (!level(2)) {
    fprintf(stderr, "I2C SDA held low\n");
    return 0;
  }
  pin(2, 0);
  pin(1, 0);
  return 1;
}
static int send_byte(unsigned v) {
  for (int i = 7; i >= 0; i--) {
    pin(1, 0);
    pin(2, (int)((v >> i) & 1));
    if (!clock_high())
      return -1;
    pin(1, 0);
  }
  pin(2, 1);
  if (!clock_high())
    return -1;
  int ack = !level(2);
  pin(1, 0);
  return ack;
}
static int send_checked(unsigned v, const char *stage) {
  int ack = send_byte(v);
  if (ack != 1) {
    fprintf(stderr, "I2C %s: %s\n", stage, ack < 0 ? "clock timeout" : "NACK");
    return 0;
  }
  return 1;
}
static int receive_byte(unsigned *out) {
  unsigned v = 0;
  pin(2, 1);
  for (unsigned i = 0; i < 8; i++) {
    if (!clock_high())
      return 0;
    v = (v << 1) | (unsigned)level(2);
    pin(1, 0);
  }
  pin(2, 1);
  if (!clock_high())
    return 0;
  pin(1, 0);
  *out = v;
  return 1;
}
static int transaction(unsigned reg, unsigned *v, int write_op) {
  int ok = start();
  if (ok)
    ok = send_checked(0x60, "address write");
  if (ok)
    ok = send_checked(reg >> 8, "register high");
  if (ok)
    ok = send_checked(reg & 255, "register low");
  if (write_op) {
    if (ok)
      ok = send_checked(*v, "value");
  } else {
    if (ok)
      ok = start();
    if (ok)
      ok = send_checked(0x61, "address read");
    if (ok)
      ok = receive_byte(v);
  }
  int stopped = stop();
  return ok && stopped;
}
/* A signal requests shutdown; never interrupt a multi-register operation. */
static volatile sig_atomic_t stopping;
static void request_stop(int sig) { (void)sig; stopping=1; }
struct exposure_trace { uint64_t high_begin, low_end; };
static int exposure_io(void *ctx, unsigned reg, unsigned *v, int write_op) {
  struct exposure_trace *trace=ctx;
  if(write_op && reg==0x3e01) trace->high_begin=monotonic_ns();
  int ok=transaction(reg,v,write_op);
  if(ok && write_op && reg==0x3e02) trace->low_end=monotonic_ns();
  return ok;
}
static uint64_t monotonic_ns(void) {
  struct timespec t;
  if(clock_gettime(CLOCK_MONOTONIC,&t)) die("monotonic clock failed");
  return (uint64_t)t.tv_sec*1000000000ULL+(uint64_t)t.tv_nsec;
}
static int serve(void) {
  struct sensor_exposure exposure;
  struct exposure_trace trace={0,0};
  sensor_exposure_init(&exposure,exposure_io,&trace);
  char line[128]; unsigned long long seq=0;
  printf("ready protocol=1 group_hold=unconfirmed edge_delay_us=%u timing=spin\n",delay_us);fflush(stdout);
  while(!stopping && fgets(line,sizeof(line),stdin)) {
    if(!strchr(line,'\n') && !feof(stdin)) {
      int ch;while(!stopping && (ch=getchar())!='\n' && ch!=EOF) {}
      puts("error command-too-long");fflush(stdout);continue;
    }
    char cmd[32],arg[64],extra;unsigned code=0;
    int fields=sscanf(line,"%31s %63s %c",cmd,arg,&extra);
    if(fields==1 && !strcmp(cmd,"quit")) break;
    if(fields!=2 || strcmp(cmd,"exposure")) {
      puts("error expected-exposure-CODE-or-quit");fflush(stdout);continue;
    }
    char *end;errno=0;
    unsigned long parsed=strtoul(arg,&end, !strncmp(arg,"0x",2)||!strncmp(arg,"0X",2)?16:10);
    if(errno || end==arg || *end || arg[0]=='-' || parsed>65535) {
      puts("error invalid-code");fflush(stdout);continue;
    }
    if(stopping) break;
    code=(unsigned)parsed;
    trace.high_begin=trace.low_end=0;
    uint64_t begin=monotonic_ns();
    enum sensor_exposure_result result=sensor_exposure_set(&exposure,code);
    uint64_t finish=monotonic_ns();
    static const char *const names[]={"ok","range","io-failed-state-unknown","verify-failed-state-unknown","state-unknown-restart-required"};
    printf("%s seq=%llu code=0x%04x begin_ns=%" PRIu64 " end_ns=%" PRIu64 " duration_us=%" PRIu64 " pair_begin_ns=%" PRIu64 " pair_end_ns=%" PRIu64 "\n",
      names[result],++seq,code,begin,finish,(finish-begin)/1000,trace.high_begin,trace.low_end);
    fflush(stdout);
  }
  return !ferror(stdin) || stopping;
}
static void prepare_lock_directory(int use_default_lock) {
  if (use_default_lock && mkdir("/run/lock", 0755) && errno != EEXIST) {
    perror("create default lock directory /run/lock");
    exit(1);
  }
}
static void help(void) {
  puts("sensorctl [--base PHYS] [--dev PATH] [--lock PATH] [--delay-us N] "
       "COMMAND\n serve               resident stdin: exposure CODE or quit\n read REG [COUNT]    consecutive 16-bit registers, one-byte "
       "reads, final NACK\n write REG VALUE     register 0..65535, value "
       "0..255\nDefaults: sensor 7-bit address 0x30, GPIO base 0xFF0A0000, "
       "/dev/mem,\n/run/lock/sensorctl.lock, delay 50us (allowed 10..1000). "
       "serve defaults to 10us busy-wait edges (CPU active during IIC); Linux can still preempt.\n"
       "No undocumented group hold; exposure values persist on exit.\n"
       "Numbers decimal or 0x hex.\nOptions precede command. Root required for "
       "real /dev/mem. GPIO bank 3 pins\n0=SCL, 1=SDA use open drain: drive "
       "low or release, never drive high.\nPreserves direction/output-enable "
       "bits outside 0/1; masked data writes affect\nonly 0/1. Restores "
       "original direction/output-enable bits 0/1 on normal exit.\nClock "
       "stretching bounded to 100 polls per edge. ACK/NACK failures abort "
       "and\nattempt STOP. No automatic sensor reset, retries, or bus-recovery "
       "pulses.\nAll GPIO-I2C users must share this advisory lock; do not run "
       "alongside a\nkernel GPIO/I2C driver or other uncoordinated register "
       "users. No writes\nare performed for help/argument validation. A read "
       "toggles GPIO on hardware.");
}
int main(int argc, char **argv) {
  uint64_t base = 0xff0a0000ULL;
  const char *dev = "/dev/mem", *lock = "/run/lock/sensorctl.lock";
  int use_default_lock = 1;
  int explicit_delay = 0;
  int i = 1;
  for (; i < argc && !strncmp(argv[i], "--", 2); i++) {
    if (!strcmp(argv[i], "--help")) {
      help();
      return 0;
    }
    if (i + 1 >= argc)
      die("option requires value");
    if (!strcmp(argv[i], "--base"))
      base = number(argv[++i], INT64_MAX - 4096);
    else if (!strcmp(argv[i], "--dev"))
      dev = argv[++i];
    else if (!strcmp(argv[i], "--lock")) {
      lock = argv[++i];
      use_default_lock = 0;
    } else if (!strcmp(argv[i], "--delay-us")) {
      explicit_delay = 1;
      delay_us = (unsigned)number(argv[++i], 1000);
      if (delay_us < 10)
        die("delay must be 10..1000 us");
    } else
      die("unknown option");
  }
  if (i == argc) {
    help();
    return 1;
  }
  const char *cmd = argv[i++];
  int n = argc - i, write_op = 0, resident = 0;
  unsigned reg = 0, value = 0, count = 1;
  if (!strcmp(cmd, "help")) {
    help();
    return 0;
  }
  if (!strcmp(cmd, "serve") && n == 0) {
    resident = 1;
    resident_timing = 1;
    if(!explicit_delay) delay_us = 10;
  } else if (!strcmp(cmd, "read") && (n == 1 || n == 2)) {
    reg = (unsigned)number(argv[i], 65535);
    if (n == 2)
      count = (unsigned)number(argv[i + 1], 65536);
    if (!count || count > 65536 - reg)
      die("register range overflow");
  } else if (!strcmp(cmd, "write") && n == 2) {
    write_op = 1;
    reg = (unsigned)number(argv[i], 65535);
    value = (unsigned)number(argv[i + 1], 255);
  } else
    die("invalid command/arguments; use --help");
  long page = sysconf(_SC_PAGESIZE);
  if (page <= 0 || base % (uint64_t)page)
    die("base must be page aligned");
  prepare_lock_directory(use_default_lock);
  int lf = open(lock, O_CREAT | O_RDWR | O_CLOEXEC, 0600);
  if (lf < 0) {
    perror("lock open");
    return 1;
  }
  if (flock(lf, LOCK_EX | LOCK_NB)) {
    perror("lock busy");
    return 1;
  }
  int fd = open(dev, O_RDWR | O_SYNC | O_CLOEXEC);
  if (fd < 0) {
    perror("device open");
    return 1;
  }
  struct stat st;
  if (fstat(fd, &st)) {
    perror("fstat");
    return 1;
  }
  if (S_ISREG(st.st_mode) && ((uint64_t)st.st_size < base + 4096))
    die("backing file smaller than mapping");
  void *p =
      mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, (off_t)base);
  if (p == MAP_FAILED) {
    perror("mmap");
    return 1;
  }
  struct sigaction action;
  memset(&action,0,sizeof(action));action.sa_handler=request_stop;
  sigemptyset(&action.sa_mask);
  if(sigaction(SIGINT,&action,NULL) || sigaction(SIGTERM,&action,NULL)) die("signal setup failed");
  gpio = p;
  unsigned old_dir = rd(0x2c4), old_oen = rd(0x2c8);
  wr(0x2c8, old_oen & ~3U);
  wr(0x2c4, old_dir | 3U);
  wr(0x18, 0xfffc0000U);
  usleep(delay_us);
  int ok = 1;
  if (!level(1) || !level(2)) {
    fprintf(stderr, "I2C bus not idle\n");
    ok = 0;
  }
  if (ok && resident) ok = serve();
  for (unsigned j = 0; ok && !resident && !stopping && j < count; j++) {
    ok = transaction(reg + j, &value, write_op);
    if (ok)
      printf("0x%04x: 0x%02x%s\n", reg + j, value, write_op ? " written" : "");
    else
      fprintf(stderr, "transaction failed at register 0x%04x\n", reg + j);
  }
  pin(1, 1);
  pin(2, 1);
  wr(0x2c4, (rd(0x2c4) & ~3U) | (old_dir & 3U));
  wr(0x2c8, (rd(0x2c8) & ~3U) | (old_oen & 3U));
  munmap(p, 4096);
  close(fd);
  close(lf);
  return ok ? 0 : 1;
}
