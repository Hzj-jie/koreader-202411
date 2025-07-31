local ffi = require("ffi")

ffi.cdef([[
struct timezone {
  int tz_minuteswest;
  int tz_dsttime;
};
int pipe(int *) __attribute__((nothrow, leaf));
int fork(void) __attribute__((nothrow));
int dup(int) __attribute__((nothrow, leaf));
int dup2(int, int) __attribute__((nothrow, leaf));
int open(const char *, int, ...);
int mq_open(const char *, int, ...) __attribute__((nothrow, leaf));
ssize_t mq_receive(int, char *, size_t, unsigned int *);
int mq_close(int) __attribute__((nothrow, leaf));
int close(int);
int fcntl(int, int, ...);
int execl(const char *, const char *, ...) __attribute__((nothrow, leaf));
int execlp(const char *, const char *, ...) __attribute__((nothrow, leaf));
int execv(const char *, char *const *) __attribute__((nothrow, leaf));
int execvp(const char *, char *const *) __attribute__((nothrow, leaf));
ssize_t write(int, const void *, size_t);
ssize_t read(int, void *, size_t);
int kill(int, int) __attribute__((nothrow, leaf));
int waitpid(int, int *, int);
int getpid(void) __attribute__((nothrow, leaf));
int getppid(void) __attribute__((nothrow, leaf));
int setpgid(int, int) __attribute__((nothrow, leaf));
struct pollfd {
  int fd;
  short int events;
  short int revents;
};
int poll(struct pollfd *, long unsigned int, int);
int memcmp(const void *, const void *, size_t) __attribute__((pure, leaf, nothrow));
void *mmap(void *, size_t, int, int, int, off_t) __attribute__((nothrow, leaf));
int munmap(void *, size_t) __attribute__((nothrow, leaf));
int ioctl(int, long unsigned int, ...) __attribute__((nothrow, leaf));
void Sleep(int ms);
unsigned int sleep(unsigned int);
int usleep(unsigned int);
int nanosleep(const struct timespec *, struct timespec *);
int statvfs(const char *restrict, struct statvfs *restrict) __attribute__((nothrow, leaf));
int gettimeofday(struct timeval *restrict, struct timezone *restrict) __attribute__((nothrow, leaf));
char *realpath(const char *restrict, char *restrict) __attribute__((nothrow, leaf));
char *basename(char *) __attribute__((nothrow, leaf));
char *dirname(char *) __attribute__((nothrow, leaf));
typedef int clockid_t;
int clock_getres(clockid_t, struct timespec *) __attribute__((nothrow, leaf));
int clock_gettime(clockid_t, struct timespec *) __attribute__((nothrow, leaf));
int clock_settime(clockid_t, const struct timespec *) __attribute__((nothrow, leaf));
int clock_nanosleep(clockid_t, int, const struct timespec *, struct timespec *);
void *malloc(size_t) __attribute__((malloc, leaf, nothrow));
void *calloc(size_t, size_t) __attribute__((malloc, leaf, nothrow));
void free(void *) __attribute__((leaf, nothrow));
void *memset(void *, int, size_t) __attribute__((leaf, nothrow));
char *strdup(const char *) __attribute__((malloc, leaf, nothrow));
char *strndup(const char *, size_t) __attribute__((malloc, leaf, nothrow));
int strcoll(const char *, const char *) __attribute__((nothrow, leaf, pure));
int strcmp(const char *, const char *) __attribute__((pure, leaf, nothrow));
int strcasecmp(const char *, const char *) __attribute__((pure, leaf, nothrow));
int access(const char *, int) __attribute__((nothrow, leaf));
typedef struct _IO_FILE FILE;
typedef long long unsigned int dev_t;
typedef long unsigned int ino_t;
typedef unsigned int mode_t;
typedef unsigned int nlink_t;
typedef unsigned int uid_t;
typedef unsigned int gid_t;
typedef long int blksize_t;
typedef long int blkcnt_t;
struct stat {
  long long unsigned int st_dev;
  short unsigned int __pad1;
  long unsigned int st_ino;
  unsigned int st_mode;
  unsigned int st_nlink;
  unsigned int st_uid;
  unsigned int st_gid;
  long long unsigned int st_rdev;
  short unsigned int __pad2;
  long int st_size;
  long int st_blksize;
  long int st_blocks;
  struct timespec st_atim;
  struct timespec st_mtim;
  struct timespec st_ctim;
  long unsigned int __glibc_reserved4;
  long unsigned int __glibc_reserved5;
};
unsigned int getuid(void) __attribute__((nothrow, leaf));
FILE *fopen(const char *restrict, const char *restrict);
int stat(const char *restrict, struct stat *restrict) __attribute__((nothrow, leaf));
int fstat(int, struct stat *) __attribute__((nothrow, leaf));
int lstat(const char *restrict, struct stat *restrict) __attribute__((nothrow, leaf));
size_t fread(void *restrict, size_t, size_t, FILE *restrict);
size_t fwrite(const void *restrict, size_t, size_t, FILE *restrict);
int fclose(FILE *);
int fflush(FILE *);
int feof(FILE *) __attribute__((nothrow, leaf));
int ferror(FILE *) __attribute__((nothrow, leaf));
int printf(const char *, ...);
int sprintf(char *, const char *, ...) __attribute__((nothrow));
int fprintf(FILE *restrict, const char *restrict, ...);
int fputc(int, FILE *);
int fileno(FILE *) __attribute__((nothrow, leaf));
char *strerror(int) __attribute__((nothrow, leaf));
int fsync(int);
int fdatasync(int);
int setenv(const char *, const char *, int) __attribute__((nothrow, leaf));
int unsetenv(const char *) __attribute__((nothrow, leaf));
int _putenv(const char *);
typedef unsigned int id_t;
enum __priority_which {
  PRIO_PROCESS = 0,
  PRIO_PGRP = 1,
  PRIO_USER = 2,
};
typedef enum __priority_which __priority_which_t;
int getpriority(__priority_which_t, id_t) __attribute__((nothrow, leaf));
int setpriority(__priority_which_t, id_t, int) __attribute__((nothrow, leaf));
typedef int pid_t;
struct sched_param {
  int sched_priority;
};
int sched_getscheduler(int) __attribute__((nothrow, leaf));
int sched_setscheduler(int, int, const struct sched_param *) __attribute__((nothrow, leaf));
int sched_getparam(int, struct sched_param *) __attribute__((nothrow, leaf));
int sched_setparam(int, const struct sched_param *) __attribute__((nothrow, leaf));
typedef struct {
  long unsigned int __bits[32];
} cpu_set_t;
int sched_getaffinity(int, size_t, cpu_set_t *) __attribute__((nothrow, leaf));
int sched_setaffinity(int, size_t, const cpu_set_t *) __attribute__((nothrow, leaf));
int sched_yield(void) __attribute__((nothrow, leaf));
struct sockaddr {
  short unsigned int sa_family;
  char sa_data[14];
};
struct ifaddrs {
  struct ifaddrs *ifa_next;
  char *ifa_name;
  unsigned int ifa_flags;
  struct sockaddr *ifa_addr;
  struct sockaddr *ifa_netmask;
  union {
    struct sockaddr *ifu_broadaddr;
    struct sockaddr *ifu_dstaddr;
  } ifa_ifu;
  void *ifa_data;
};
int getifaddrs(struct ifaddrs **) __attribute__((nothrow, leaf));
int getnameinfo(const struct sockaddr *restrict, unsigned int, char *restrict, unsigned int, char *restrict, unsigned int, int);
struct in_addr {
  unsigned int s_addr;
};
struct sockaddr_in {
  short unsigned int sin_family;
  short unsigned int sin_port;
  struct in_addr sin_addr;
  unsigned char sin_zero[8];
};
struct in6_addr {
  union {
    uint8_t __u6_addr8[16];
    uint16_t __u6_addr16[8];
    uint32_t __u6_addr32[4];
  } __in6_u;
};
struct sockaddr_in6 {
  short unsigned int sin6_family;
  short unsigned int sin6_port;
  uint32_t sin6_flowinfo;
  struct in6_addr sin6_addr;
  uint32_t sin6_scope_id;
};
const char *gai_strerror(int) __attribute__((nothrow, leaf));
void freeifaddrs(struct ifaddrs *) __attribute__((nothrow, leaf));
int socket(int, int, int) __attribute__((nothrow, leaf));
struct ifmap {
  long unsigned int mem_start;
  long unsigned int mem_end;
  short unsigned int base_addr;
  unsigned char irq;
  unsigned char dma;
  unsigned char port;
};
struct ifreq {
  union {
    char ifrn_name[16];
  } ifr_ifrn;
  union {
    struct sockaddr ifru_addr;
    struct sockaddr ifru_dstaddr;
    struct sockaddr ifru_broadaddr;
    struct sockaddr ifru_netmask;
    struct sockaddr ifru_hwaddr;
    short int ifru_flags;
    int ifru_ivalue;
    int ifru_mtu;
    struct ifmap ifru_map;
    char ifru_slave[16];
    char ifru_newname[16];
    char *ifru_data;
  } ifr_ifru;
};
struct iw_point {
  void *pointer;
  short unsigned int length;
  short unsigned int flags;
};
struct iw_param {
  int value;
  unsigned char fixed;
  unsigned char disabled;
  short unsigned int flags;
};
struct iw_freq {
  int m;
  short int e;
  unsigned char i;
  unsigned char flags;
};
struct iw_quality {
  unsigned char qual;
  unsigned char level;
  unsigned char noise;
  unsigned char updated;
};
union iwreq_data {
  char name[16];
  struct iw_point essid;
  struct iw_param nwid;
  struct iw_freq freq;
  struct iw_param sens;
  struct iw_param bitrate;
  struct iw_param txpower;
  struct iw_param rts;
  struct iw_param frag;
  unsigned int mode;
  struct iw_param retry;
  struct iw_point encoding;
  struct iw_param power;
  struct iw_quality qual;
  struct sockaddr ap_addr;
  struct sockaddr addr;
  struct iw_param param;
  struct iw_point data;
};
struct iwreq {
  union {
    char ifrn_name[16];
  } ifr_ifrn;
  union iwreq_data u;
};
typedef char *caddr_t;
typedef unsigned int socklen_t;
struct icmphdr {
  uint8_t type;
  uint8_t code;
  uint16_t checksum;
  union {
    struct {
      uint16_t id;
      uint16_t sequence;
    } echo;
    uint32_t gateway;
    struct {
      uint16_t __glibc_reserved;
      uint16_t mtu;
    } frag;
  } un;
};
struct ih_idseq {
  uint16_t icd_id;
  uint16_t icd_seq;
};
struct ih_pmtu {
  uint16_t ipm_void;
  uint16_t ipm_nextmtu;
};
struct ih_rtradv {
  uint8_t irt_num_addrs;
  uint8_t irt_wpa;
  uint16_t irt_lifetime;
};
struct ip {
  unsigned int ip_hl : 4;
  unsigned int ip_v : 4;
  uint8_t ip_tos;
  short unsigned int ip_len;
  short unsigned int ip_id;
  short unsigned int ip_off;
  uint8_t ip_ttl;
  uint8_t ip_p;
  short unsigned int ip_sum;
  struct in_addr ip_src;
  struct in_addr ip_dst;
};
struct icmp_ra_addr {
  uint32_t ira_addr;
  uint32_t ira_preference;
};
struct icmp {
  uint8_t icmp_type;
  uint8_t icmp_code;
  uint16_t icmp_cksum;
  union {
    unsigned char ih_pptr;
    struct in_addr ih_gwaddr;
    struct ih_idseq ih_idseq;
    uint32_t ih_void;
    struct ih_pmtu ih_pmtu;
    struct ih_rtradv ih_rtradv;
  } icmp_hun;
  union {
    struct {
      uint32_t its_otime;
      uint32_t its_rtime;
      uint32_t its_ttime;
    } id_ts;
    struct {
      struct ip idi_ip;
    } id_ip;
    struct icmp_ra_addr id_radv;
    uint32_t id_mask;
    uint8_t id_data[1];
  } icmp_dun;
};
ssize_t sendto(int, const void *, size_t, int, const struct sockaddr *, unsigned int);
ssize_t recv(int, void *, size_t, int);
struct iphdr {
  unsigned int ihl : 4;
  unsigned int version : 4;
  uint8_t tos;
  uint16_t tot_len;
  uint16_t id;
  uint16_t frag_off;
  uint8_t ttl;
  uint8_t protocol;
  uint16_t check;
  uint32_t saddr;
  uint32_t daddr;
};
int inet_aton(const char *, struct in_addr *) __attribute__((nothrow, leaf));
uint32_t htonl(uint32_t) __attribute__((nothrow, leaf, const));
uint16_t htons(uint16_t) __attribute__((nothrow, leaf, const));
]])

-- clock_gettime & friends require librt on old glibc (< 2.17) versions...
if jit.os == "Linux" then
  -- Load it in the global namespace to make it easier on callers...
  -- NOTE: There's no librt.so symlink, so, specify the SOVER, but not the full path,
  --       in order to let the dynamic loader figure it out on its own (e.g.,  multilib).
  pcall(ffi.load, "rt.so.1", true)
end
