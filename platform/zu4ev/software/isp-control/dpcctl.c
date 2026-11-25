#define _POSIX_C_SOURCE 200809L
#define _FILE_OFFSET_BITS 64
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

enum {
    ID=0x3100, APPLY=0x3108, STATUS=0x310c, BEGIN=0x3110, APPLY_SEQ=0x3114,
    UPLOADED=0x3118, ACTIVE_COUNT=0x311c, FRAME_SEQ=0x3120, REPAIRED=0x3124,
    FAULTS=0x3128, GEOMETRY=0x312c, CAPACITY=0x3130, MAX_RUN=0x3134,
    PROBE_CFG=0x3140, PROBE_START=0x3144, PROBE_STATUS=0x3148,
    PROBE_COUNT0=0x314c, PROBE_COUNT1=0x3150, PROBE_SEQ=0x3154,
    MAP_BASE=0x8000, PROBE_BASE=0xa000, MAX_ENTRIES=1024
};

static volatile uint32_t *mmio;

static void die(const char *message)
{
    fprintf(stderr, "dpcctl: %s\n", message);
    exit(1);
}

static void bus_fault(int sig)
{
    static const char message[] = "dpcctl: ISP bus fault; check hardware version and ownership\n";
    (void)sig;
    ssize_t written=write(STDERR_FILENO,message,sizeof(message)-1);
    (void)written;
    _exit(1);
}

static uint32_t rd(unsigned address)
{
    uint32_t v = mmio[address/4];
    __sync_synchronize();
    return v;
}

static void wr(unsigned address, uint32_t value)
{
    __sync_synchronize();
    mmio[address/4] = value;
    __sync_synchronize();
}

static unsigned number(const char *s, unsigned limit)
{
    char *end;
    if (*s<'0' || *s>'9') die("expected unsigned decimal number");
    errno=0;
    unsigned long v=strtoul(s,&end,10);
    if (errno || *end || v>limit) die("number out of range");
    return (unsigned)v;
}

static unsigned field(FILE *f, unsigned limit)
{
    char word[40];
    if (fscanf(f,"%39s",word)!=1) die("truncated map");
    return number(word,limit);
}

static unsigned load_file(const char *path, uint32_t *entries, unsigned *width, unsigned *height)
{
    FILE *f=fopen(path,"r");
    char word[40];
    if (!f) die("cannot open map");
    if (fscanf(f,"%39s",word)!=1 || strcmp(word,"DPC_MAP1")) die("invalid map header");
    *width=field(f,2048);
    *height=field(f,1024);
    if (*width<2 || (*width&1) || !*height) die("invalid map geometry");
    unsigned n=field(f,MAX_ENTRIES),prev_y=0,prev_end=0;
    for (unsigned i=0;i<n;i++) {
        unsigned x=field(f,*width-1),y=field(f,*height-1),len=field(f,32);
        if (!len || x+len>*width || len==*width ||
            (i && (y<prev_y || (y==prev_y && x<=prev_end))))
            die("run crosses row, has no donor, is unsorted, overlaps or touches another run");
        entries[i]=x|(y<<11)|((len-1)<<21);
        prev_y=y;
        prev_end=x+len;
    }
    if (fscanf(f,"%39s",word)!=EOF || ferror(f)) die("trailing or unreadable map data");
    fclose(f);
    return n;
}

static unsigned long long milliseconds(void)
{
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC,&t)) die("clock_gettime");
    return (unsigned long long)t.tv_sec*1000+t.tv_nsec/1000000;
}

static void wait_ms(void)
{
    const struct timespec t={0,1000000};
    (void)nanosleep(&t,NULL);
}

static void apply(unsigned enable)
{
    if (rd(STATUS)&2) die("an apply is already pending");
    uint32_t seq=rd(APPLY_SEQ);
    wr(APPLY,2|enable);
    unsigned long long deadline=milliseconds()+2000;
    while (milliseconds()<deadline) {
        unsigned state=rd(STATUS);
        if (!(state&2) && rd(APPLY_SEQ)!=seq && (state&1)==enable) return;
        wait_ms();
    }
    die("apply timed out; inspect live video and pending status");
}

static void survey(const char *path, unsigned w, unsigned h, unsigned corrected,
                   unsigned low, unsigned threshold, unsigned frames)
{
    uint8_t *hits=calloc((size_t)w*h,1);
    if (!hits) die("cannot allocate survey counters");
    if (rd(PROBE_STATUS)&1) die("candidate capture is busy");
    wr(PROBE_CFG,threshold|(low<<16)|(corrected<<17));
    for (unsigned frame=0;frame<frames;frame++) {
        unsigned seq=rd(PROBE_SEQ),state;
        wr(PROBE_START,1);
        unsigned long long deadline=milliseconds()+2000;
        do {
            state=rd(PROBE_STATUS);
            if (state&14) break;
            wait_ms();
        } while (milliseconds()<deadline);
        if (state&4) die("candidate RAM overflow; adjust threshold/exposure; survey discarded");
        if (state!=2 || rd(PROBE_SEQ)!=seq+1u) die("candidate frame failed or timed out; survey discarded");
        for (unsigned lane=0;lane<2;lane++) {
            unsigned count=rd(lane?PROBE_COUNT1:PROBE_COUNT0),prev=0;
            if (count>1024) die("invalid candidate count");
            for (unsigned i=0;i<count;i++) {
                uint32_t word=rd(PROBE_BASE+4096*lane+4*i);
                unsigned x=word&2047,y=word>>11;
                if (x>=w || y>=h || (x&1)!=lane || (i && word<=prev))
                    die("invalid candidate coordinate or order");
                hits[(size_t)y*w+x]++;
                prev=word;
            }
        }
    }
    FILE *f=fopen(path,"wx");
    if (!f) die("cannot create survey output (must be a new file)");
    fprintf(f,"DPC_SURVEY1 %u %u %u %s %s %u\n",w,h,frames,
            corrected?"corrected":"raw",low?"low":"high",threshold);
    unsigned records=0;
    for (unsigned y=0;y<h;y++) for (unsigned x=0;x<w;x++) {
        unsigned n=hits[(size_t)y*w+x];
        if (n) { fprintf(f,"%u %u %u\n",x,y,n); records++; }
    }
    fprintf(f,"END %u\n",records);
    if (fclose(f)) die("survey output write failed");
    free(hits);
    printf("DPC_SURVEY_PASS frames=%u candidates=%u\n",frames,records);
}

int main(int argc, char **argv)
{
    if (argc<2 || !strcmp(argv[1],"--help")) {
        puts("dpcctl status | load MAP | disable | survey FILE raw|corrected high|low THRESHOLD FRAMES\n"
             "Requires matching DPC hardware and PS ownership (ibex_isp_handoff stop).\n"
             "Map: DPC_MAP1 width height run_count followed by x y length (decimal).\n"
             "Survey: threshold 0..1023, frames 1..255; no automatic repair-map changes.");
        return argc<2?2:0;
    }
    int status=!strcmp(argv[1],"status"),load=!strcmp(argv[1],"load"),
        disable=!strcmp(argv[1],"disable"),capture=!strcmp(argv[1],"survey");
    if (!(((status||disable)&&argc==2)||(load&&argc==3)||(capture&&argc==7))) die("invalid arguments");
    unsigned n=0,mw=0,mh=0,corrected=0,low=0,threshold=0,frames=0;
    uint32_t entries[MAX_ENTRIES];
    if (load) n=load_file(argv[2],entries,&mw,&mh);
    if (capture) {
        corrected=!strcmp(argv[3],"corrected");
        low=!strcmp(argv[4],"low");
        if ((!corrected&&strcmp(argv[3],"raw"))||(!low&&strcmp(argv[4],"high"))) die("invalid survey source/comparison");
        threshold=number(argv[5],1023);
        frames=number(argv[6],255);
        if (!frames) die("survey needs at least one frame");
    }
    (void)mkdir("/run/lock",0755);
    int owner=open("/run/ibex_isp_handoff.lock",O_CREAT|O_RDWR,0600);
    if (owner<0 || flock(owner,LOCK_EX|LOCK_NB)) die("ownership lock busy");
    int lock=open("/run/lock/ispctl.lock",O_CREAT|O_RDWR,0600);
    if (lock<0 || flock(lock,LOCK_EX|LOCK_NB)) die("ISP lock busy");
    int fd=open("/dev/mem",O_RDWR|O_SYNC);
    if (fd<0) die("cannot open /dev/mem");
    mmio=mmap(NULL,65536,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0xa0040000ULL);
    if (mmio==MAP_FAILED) die("mmap failed");
    if (signal(SIGBUS,bus_fault)==SIG_ERR) die("cannot install bus fault handler");
    if ((rd(0xff00)&1)||(rd(0xff08)&1)||(rd(0xff04)&6)) die("Ibex not stopped/reclaimed");
    if (rd(0)!=0x49535031 || rd(ID)!=0x44504331) die("hardware identity mismatch");
    unsigned g=rd(GEOMETRY),w=g&65535,h=g>>16;
    if (w<2 || w>2048 || (w&1) || !h || h>1024 || rd(CAPACITY)!=MAX_ENTRIES || rd(MAX_RUN)!=32)
        die("unsupported hardware geometry or map capacity");
    if (status) {
        unsigned state=rd(STATUS),seq=0,last=0;
        for (unsigned retry=0;retry<16;retry++) {
            seq=rd(FRAME_SEQ);last=rd(REPAIRED);
            if (seq==rd(FRAME_SEQ)) break;
            if (retry==15) die("could not read coherent frame counters");
        }
        printf("DPC enable=%u pending=%u bank=%u apply_seq=%u active_runs=%u uploaded=%u "
               "frame_seq=%u last_repaired=%u fault_events=%u probe=%u\n",state&1,(state>>1)&1,(state>>2)&1,
               rd(APPLY_SEQ),rd(ACTIVE_COUNT),rd(UPLOADED),seq,last,rd(FAULTS),rd(PROBE_STATUS));
    }
    if (load) {
        if (mw!=w || mh!=h) die("map geometry does not match hardware");
        if (rd(STATUS)&2) die("an apply is already pending");
        wr(BEGIN,n);
        for (unsigned i=0;i<n;i++) {
            wr(MAP_BASE+4*i,entries[i]);
            if (rd(MAP_BASE+4*i)!=entries[i] || rd(UPLOADED)!=i+1)
                die("inactive map readback mismatch; active bank unchanged");
        }
        apply(1);
        printf("DPC_LOAD_PASS runs=%u\n",n);
    }
    if (disable) { apply(0);puts("DPC_DISABLED"); }
    if (capture) survey(argv[2],w,h,corrected,low,threshold,frames);
    munmap((void*)mmio,65536);
    close(fd);close(lock);close(owner);
    return 0;
}
