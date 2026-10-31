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
static uint32_t rd(unsigned o) {
  uint32_t v = mm[o / 4];
  __sync_synchronize();
  return v;
}
static void wr(unsigned o, uint32_t v) {
  __sync_synchronize();
  mm[o / 4] = v;
  __sync_synchronize();
}
static int64_t monotonic_ns(void) {
  struct timespec now;
  if (clock_gettime(CLOCK_MONOTONIC, &now)) {
    perror("clock_gettime");
    exit(1);
  }
  return (int64_t)now.tv_sec * 1000000000LL + now.tv_nsec;
}
static void apply_wait(uint32_t command) {
  uint32_t expected = rd(0x24) + 1U;
  int64_t deadline = monotonic_ns() + 1000000000LL;
  wr(0x20, command);
  for (;;) {
    if (!(rd(0x0c) & 1U) && rd(0x24) == expected) {
      printf("applied_seq=%" PRIu32 "\n", expected);
      return;
    }
    if (monotonic_ns() >= deadline)
      die("apply timed out after 1000ms; request may still be pending; inspect "
          "status before retrying");
    struct timespec pause = {.tv_sec = 0, .tv_nsec = 1000000};
    if (nanosleep(&pause, NULL) && errno != EINTR) {
      perror("nanosleep");
      exit(1);
    }
  }
}
static void prepare_lock_directory(int use_default_lock) {
  if (use_default_lock && mkdir("/run/lock", 0755) && errno != EEXIST) {
    perror("create default lock directory /run/lock");
    exit(1);
  }
}
static void stats_supported(void) {
  /* Only legacy-defined registers are touched before checking capability. */
  if (rd(0) != 0x49535031U || !(rd(8) & 0x10U))
    die("RAW10 statistics unsupported by this firmware");
  if (rd(0x200) != 0x41455331U || rd(0x204) != 0x00010000U)
    die("unsupported RAW10 statistics register version");
}
static void stats_read(void) {
  for (unsigned retry = 0; retry < 16; retry++) {
    uint32_t seq = rd(0x214), valid = rd(0x210) & 1U;
    uint32_t frame = rd(0x218), mean = rd(0x21c), count = rd(0x220);
    uint32_t low = rd(0x224), high = rd(0x228), config = rd(0x234);
    uint32_t x = rd(0x238), y = rd(0x23c), w = rd(0x240), h = rd(0x244);
    uint32_t final_seq = rd(0x214), final_valid = rd(0x210) & 1U;
    if (seq != final_seq)
      continue;
    if (!valid || !final_valid)
      die("no valid RAW10 statistics result (not yet published or invalidated)");
    printf("seq=%" PRIu32 " frame=%" PRIu32 " mean=%" PRIu32
           " count=%" PRIu32 " sum=%" PRIu64 " region=%u black=%u"
           " roi=%" PRIu32 ",%" PRIu32 ",%" PRIu32 ",%" PRIu32 "\n",
           seq, frame, mean, count, ((uint64_t)high << 32) | low,
           config & 3U, (config >> 8) & 1023U, x, y, w, h);
    return;
  }
  die("statistics changed during all 16 snapshot attempts; retry");
}
static void help(void) {
  puts("ispctl [--base PHYS] [--dev PATH] [--lock PATH] COMMAND\nDefault base "
       "0xA0040000, /dev/mem; 64KiB mapping; advisory exclusive lock.\nOptions "
       "precede command. Numbers decimal or 0x hexadecimal. Root required for "
       "/dev/mem.\n status                     named "
       "shadow/active/status/counters\n read OFFSET [COUNT]        aligned "
       "32-bit words within 64KiB\n write OFFSET VALUE         raw 32-bit "
       "access; hardware rejects RO/unmapped/invalid\n set mode "
       "ltm|global|raw|identity|0..3\n set tone 0|1 | blc 0|1 | black 0..1022 | gain 0..512 (Q8, "
       "256=1x) | sigma 32|64|128\n apply [--swap]             commit shadows "
       "at safe frame boundary; wait <=1000ms; optional LUT swap\n curve-load "
       "FILE            "
       "exactly 1024 whitespace-separated unsigned values 0..1023\n "
       "curve-default              load factory piecewise 10-bit curve "
       "(white=971)\nCurve commands validate before writing, write INACTIVE "
       "bank, verify every word.\nThey do not apply/swap. Run apply --swap "
       "explicitly afterwards. Pending apply\nrejects set/apply/LUT "
       "operations. Raw accesses intentionally bypass these guards.\nAll "
       "processes controlling this block must share the same lock. Avoid raw "
       "reads\nof undefined offsets on hardware: AXI SLVERR may cause SIGBUS. "
       "No kernel driver required.\n"
       " ae status                 read R5 AE control enable\n"
       " ae enable 0|1             enable or pause R5 AE control\n"
       " stats status              configuration, validity, busy and counters\n"
       " stats read                coherent last completed frame (16 retries)\n"
       " stats set enable 0|1      latch on next RAW SOF\n"
       " stats set region 0..3     center area 1/4,1/2,3/4,full\n"
       " stats set black 0..1023   independent statistics black level");
}
int main(int argc, char **argv) {
  uint64_t base = 0xa0040000ULL;
  const char *dev = "/dev/mem", *lock = "/run/lock/ispctl.lock";
  int use_default_lock = 1;
  int i = 1;
  for (; i < argc && !strncmp(argv[i], "--", 2); i++) {
    if (!strcmp(argv[i], "--help")) {
      help();
      return 0;
    }
    if (i + 1 >= argc)
      die("option requires value");
    if (!strcmp(argv[i], "--base"))
      base = number(argv[++i], INT64_MAX - 65536);
    else if (!strcmp(argv[i], "--dev"))
      dev = argv[++i];
    else if (!strcmp(argv[i], "--lock")) {
      lock = argv[++i];
      use_default_lock = 0;
    } else
      die("unknown option");
  }
  if (i == argc) {
    help();
    return 1;
  }
  const char *c = argv[i++];
  int n = argc - i;
  unsigned off = 0, count = 1;
  uint32_t value = 0, lut[1024];
  int action = 0;
  if (!strcmp(c, "help")) {
    help();
    return 0;
  }
  if (!strcmp(c, "ae")) {
    off = 0x248;
    if (n == 1 && !strcmp(argv[i], "status"))
      action = 1;
    else if (n == 2 && !strcmp(argv[i], "enable")) {
      value = (uint32_t)number(argv[i + 1], 1);
      action = 2;
    } else
      die("invalid AE command; use --help");
  } else if (!strcmp(c, "stats")) {
    if (n == 1 && !strcmp(argv[i], "status"))
      action = 6;
    else if (n == 1 && !strcmp(argv[i], "read"))
      action = 7;
    else if (n == 3 && !strcmp(argv[i], "set")) {
      action = 8;
      if (!strcmp(argv[i + 1], "enable")) {
        off = 0x208; count = 1; value = (uint32_t)number(argv[i + 2], 1);
      } else if (!strcmp(argv[i + 1], "region")) {
        off = 0x208; count = 6; value = (uint32_t)number(argv[i + 2], 3) << 1;
      } else if (!strcmp(argv[i + 1], "black")) {
        off = 0x20c; count = 1023; value = (uint32_t)number(argv[i + 2], 1023);
      } else
        die("unknown statistics setting");
    } else
      die("invalid statistics command; use --help");
  } else if (!strcmp(c, "read") && (n == 1 || n == 2)) {
    off = (unsigned)number(argv[i], 65532);
    count = n == 2 ? (unsigned)number(argv[i + 1], 16384) : 1;
    if ((off & 3) || !count || count > (65536 - off) / 4)
      die("unaligned or out of span");
    action = 1;
  } else if (!strcmp(c, "write") && n == 2) {
    off = (unsigned)number(argv[i], 65532);
    if (off & 3)
      die("unaligned offset");
    value = (uint32_t)number(argv[i + 1], UINT32_MAX);
    action = 2;
  } else if (!strcmp(c, "status") && n == 0)
    action = 3;
  else if (!strcmp(c, "set") && n == 2) {
    const char *s = argv[i], *v = argv[i + 1];
    action = 4;
    if (!strcmp(s, "mode")) {
      off = 0x10;
      const char *names[] = {"ltm", "global", "raw", "identity"};
      int j;
      for (j = 0; j < 4; j++)
        if (!strcmp(v, names[j]))
          break;
      value = j < 4 ? (unsigned)j : (unsigned)number(v, 3);
    } else if (!strcmp(s, "tone")) {
      off = 0x64;
      value = (unsigned)number(v, 1);
    } else if (!strcmp(s, "blc")) {
      off = 0x5c;
      value = (unsigned)number(v, 1);
    } else if (!strcmp(s, "black")) {
      off = 0x14;
      value = (unsigned)number(v, 1022);
    } else if (!strcmp(s, "gain")) {
      off = 0x18;
      value = (unsigned)number(v, 512);
    } else if (!strcmp(s, "sigma")) {
      off = 0x1c;
      unsigned x = (unsigned)number(v, 128);
      if (x != 32 && x != 64 && x != 128)
        die("sigma must be 32,64,128");
      value = x == 32 ? 1 : x == 128 ? 2 : 0;
    } else
      die("unknown setting");
  } else if (!strcmp(c, "apply") &&
             (n == 0 || (n == 1 && !strcmp(argv[i], "--swap")))) {
    action = 4;
    off = 0x20;
    value = n ? 3 : 1;
  } else if ((!strcmp(c, "curve-default") && n == 0) ||
             (!strcmp(c, "curve-load") && n == 1)) {
    action = 5;
    if (n) {
      FILE *f = fopen(argv[i], "r");
      if (!f) {
        perror("curve open");
        return 1;
      }
      char token[128];
      for (unsigned j = 0; j < 1024; j++) {
        if (fscanf(f, "%127s", token) != 1)
          die("curve needs 1024 values");
        lut[j] = (uint32_t)number(token, 1023);
      }
      if (fscanf(f, "%127s", token) == 1)
        die("curve has extra values");
      if (ferror(f))
        die("curve read error");
      fclose(f);
    } else {
      const int x[] = {0, 1, 4, 10, 25, 50, 75, 90, 100},
                y[] = {16, 22, 49, 82, 128, 176, 208, 224, 235};
      for (int j = 0; j < 1024; j++) {
        int z = (j < 971 ? j : 971) * 100, k = 0;
        while (k < 7 && z > 971 * x[k + 1])
          k++;
        int64_t den = 971LL * (x[k + 1] - x[k]) * 219;
        int64_t num = ((y[k] - 16) * 971LL * (x[k + 1] - x[k]) +
                       (z - 971 * x[k]) * (int64_t)(y[k + 1] - y[k])) *
                      1023;
        lut[j] = (uint32_t)((2 * num + den) / (2 * den));
      }
    }
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
  if (S_ISREG(st.st_mode) && ((uint64_t)st.st_size < base + 65536))
    die("backing file smaller than mapping");
  void *p =
      mmap(NULL, 65536, PROT_READ | PROT_WRITE, MAP_SHARED, fd, (off_t)base);
  if (p == MAP_FAILED) {
    perror("mmap");
    return 1;
  }
  mm = p;
  if (!strcmp(c, "ae") && !(rd(8) & 0x20U))
    die("AE control switch unsupported by this firmware");
  if (!strcmp(c, "set") && off == 0x5c && !(rd(8) & 0x40U))
    die("BLC switch unsupported by this firmware");
  if (!strcmp(c, "set") && off == 0x64 && !(rd(8) & 0x80U))
    die("tone switch unsupported by this firmware");
  if (action >= 6) {
    stats_supported();
    if (action == 6) {
      uint32_t control = rd(0x208), status = rd(0x210);
      printf("enable=%u region=%u black=%u valid=%u busy=%u active_enable=%u"
             " bad_frames=%" PRIu32 " overruns=%" PRIu32 "\n",
             control & 1U, (control >> 1) & 3U, rd(0x20c), status & 1U,
             (status >> 1) & 1U, (status >> 2) & 1U, rd(0x22c), rd(0x230));
    } else if (action == 7)
      stats_read();
    else {
      wr(off, (rd(off) & ~count) | value);
      puts("statistics setting written; effective at next RAW SOF");
    }
  }
  if (action == 1)
    for (unsigned j = 0; j < count; j++)
      printf("0x%04x: 0x%08" PRIx32 "\n", off + 4 * j, rd(off + 4 * j));
  if (action == 2)
    wr(off, value);
  if (action == 3) {
    const unsigned offsets[] = {0,  4,  8,  12, 16, 20, 24, 28, 36, 40,
                                44, 48, 52, 56, 60, 64, 72, 76, 80, 88};
    const char *names[] = {"id",
                           "version",
                           "caps",
                           "status",
                           "shadow_mode",
                           "shadow_black",
                           "shadow_gain_q8",
                           "shadow_sigma_encoding",
                           "applied_seq",
                           "frames",
                           "faults",
                           "fifo_level",
                           "active_mode",
                           "active_black",
                           "active_gain_q8",
                           "active_sigma_encoding",
                           "width",
                           "height",
                           "window",
                           "lut_size"};
    for (unsigned j = 0; j < sizeof(offsets) / sizeof(*offsets); j++)
      printf("%-24s 0x%08" PRIx32 "\n", names[j], rd(offsets[j]));
    uint32_t s = rd(12);
    printf("pending=%u active_bank=%u frame_busy=%u\n", s & 1, (s >> 1) & 1,
           (s >> 2) & 1);
    uint32_t caps = rd(8);
    if (caps & 0x40U)
      printf("blc_shadow=%u blc_active=%u\n", rd(0x5c), rd(0x60));
    if (caps & 0x80U)
      printf("tone_shadow=%u tone_active=%u\n", rd(0x64), rd(0x68));
    if (caps & 0x20U)
      printf("ae_enable=%u\n", rd(0x248));
  }
  if (action == 4 || action == 5) {
    if (rd(12) & 1)
      die("apply pending; retry after safe boundary");
    if (action == 4) {
      if (off == 0x20)
        apply_wait(value);
      else
        wr(off, value);
    } else {
      for (unsigned j = 0; j < 1024; j++)
        wr(0x1000 + 4 * j, lut[j]);
      for (unsigned j = 0; j < 1024; j++)
        if (rd(0x1000 + 4 * j) != lut[j])
          die("curve readback mismatch; do not swap");
      puts("inactive curve verified; activate with apply --swap");
    }
  }
  munmap(p, 65536);
  close(fd);
  close(lf);
  return 0;
}
