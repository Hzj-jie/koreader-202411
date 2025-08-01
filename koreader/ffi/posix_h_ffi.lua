local ffi = require("ffi")

ffi.cdef([[
struct timezone {
  int tz_minuteswest;
  int tz_dsttime;
};
int pipe(int *);
int fork(void);
int dup(int);
int dup2(int, int);
int open(const char *, int, ...);
int mq_open(const char *, int, ...);
ssize_t mq_receive(int, char *, size_t, unsigned int *);
int mq_close(int);
int close(int);
int fcntl(int, int, ...);
int execl(const char *, const char *, ...);
int execlp(const char *, const char *, ...);
int execv(const char *, char *const *);
int execvp(const char *, char *const *);
ssize_t write(int, const void *, size_t);
ssize_t read(int, void *, size_t);
int kill(int, int);
int waitpid(int, int *, int);
int getpid(void);
int getppid(void);
int setpgid(int, int);
struct pollfd {
  int fd;
  short int events;
  short int revents;
};
int poll(struct pollfd *, unsigned long, int);
int memcmp(const void *, const void *, size_t);
void *mmap(void *, size_t, int, int, int, off_t);
int munmap(void *, size_t);
int ioctl(int, unsigned long, ...);
void Sleep(int ms);
unsigned int sleep(unsigned int);
int usleep(unsigned int);
int nanosleep(const struct timespec *, struct timespec *);
int statvfs(const char *restrict, struct statvfs *restrict);
int gettimeofday(struct timeval *restrict, struct timezone *restrict);
char *realpath(const char *restrict, char *restrict);
char *basename(char *);
char *dirname(char *);
typedef int clockid_t;
int clock_getres(clockid_t, struct timespec *);
int clock_gettime(clockid_t, struct timespec *);
int clock_settime(clockid_t, const struct timespec *);
int clock_nanosleep(clockid_t, int, const struct timespec *, struct timespec *);
void *malloc(size_t);
void *calloc(size_t, size_t);
void free(void *);
void *memset(void *, int, size_t);
char *strdup(const char *);
char *strndup(const char *, size_t);
int strcoll(const char *, const char *);
int strcmp(const char *, const char *);
int strcasecmp(const char *, const char *);
int access(const char *, int);
typedef struct _IO_FILE FILE;
typedef unsigned long long dev_t;
typedef unsigned long ino_t;
typedef unsigned int mode_t;
typedef unsigned int nlink_t;
typedef unsigned int uid_t;
typedef unsigned int gid_t;
typedef long blksize_t;
typedef long blkcnt_t;
struct stat {
  unsigned long long st_dev;
  unsigned short __pad1;
  unsigned long st_ino;
  unsigned int st_mode;
  unsigned int st_nlink;
  unsigned int st_uid;
  unsigned int st_gid;
  unsigned long long st_rdev;
  unsigned short __pad2;
  long st_size;
  long st_blksize;
  long st_blocks;
  struct timespec st_atim;
  struct timespec st_mtim;
  struct timespec st_ctim;
  unsigned long __glibc_reserved4;
  unsigned long __glibc_reserved5;
};
unsigned int getuid(void);
FILE *fopen(const char *restrict, const char *restrict);
int stat(const char *restrict, struct stat *restrict);
int fstat(int, struct stat *);
int lstat(const char *restrict, struct stat *restrict);
size_t fread(void *restrict, size_t, size_t, FILE *restrict);
size_t fwrite(const void *restrict, size_t, size_t, FILE *restrict);
int fclose(FILE *);
int fflush(FILE *);
int feof(FILE *);
int ferror(FILE *);
int printf(const char *, ...);
int sprintf(char *, const char *, ...);
int fprintf(FILE *restrict, const char *restrict, ...);
int fputc(int, FILE *);
int fileno(FILE *);
char *strerror(int);
int fsync(int);
int fdatasync(int);
int setenv(const char *, const char *, int);
int unsetenv(const char *);
int _putenv(const char *);
typedef unsigned int id_t;
enum __priority_which {
  PRIO_PROCESS = 0,
  PRIO_PGRP = 1,
  PRIO_USER = 2,
};
typedef enum __priority_which __priority_which_t;
int getpriority(__priority_which_t, id_t);
int setpriority(__priority_which_t, id_t, int);
typedef int pid_t;
struct sched_param {
  int sched_priority;
};
int sched_getscheduler(int);
int sched_setscheduler(int, int, const struct sched_param *);
int sched_getparam(int, struct sched_param *);
int sched_setparam(int, const struct sched_param *);
typedef struct {
  unsigned long __bits[32];
} cpu_set_t;
int sched_getaffinity(int, size_t, cpu_set_t *);
int sched_setaffinity(int, size_t, const cpu_set_t *);
int sched_yield(void);
struct sockaddr {
  unsigned short sa_family;
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
int getifaddrs(struct ifaddrs **);
int getnameinfo(const struct sockaddr *restrict, unsigned int, char *restrict, unsigned int, char *restrict, unsigned int, int);
struct in_addr {
  unsigned int s_addr;
};
struct sockaddr_in {
  unsigned short sin_family;
  unsigned short sin_port;
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
  unsigned short sin6_family;
  unsigned short sin6_port;
  uint32_t sin6_flowinfo;
  struct in6_addr sin6_addr;
  uint32_t sin6_scope_id;
};
const char *gai_strerror(int);
void freeifaddrs(struct ifaddrs *);
int socket(int, int, int);
struct ifmap {
  unsigned long mem_start;
  unsigned long mem_end;
  unsigned short base_addr;
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
  unsigned short length;
  unsigned short flags;
};
struct iw_param {
  int value;
  unsigned char fixed;
  unsigned char disabled;
  unsigned short flags;
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
  unsigned int ip_hl;
  unsigned int ip_v;
  uint8_t ip_tos;
  unsigned short ip_len;
  unsigned short ip_id;
  unsigned short ip_off;
  uint8_t ip_ttl;
  uint8_t ip_p;
  unsigned short ip_sum;
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
  unsigned int ihl;
  unsigned int version;
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
int inet_aton(const char *, struct in_addr *);
uint32_t htonl(uint32_t);
uint16_t htons(uint16_t);
]])

-- clock_gettime & friends require librt on old glibc (< 2.17) versions...
if jit.os == "Linux" then
  -- Load it in the global namespace to make it easier on callers...
  -- NOTE: There's no librt.so symlink, so, specify the SOVER, but not the full path,
  --       in order to let the dynamic loader figure it out on its own (e.g.,  multilib).
  pcall(ffi.load, "rt.so.1", true)
end
