local ffi = require("ffi")

ffi.cdef([[
enum { IN_ACCESS = 1 };
enum { IN_ATTRIB = 4 };
enum { IN_CLOSE_WRITE = 8 };
enum { IN_CLOSE_NOWRITE = 16 };
enum { IN_CREATE = 256 };
enum { IN_DELETE = 512 };
enum { IN_DELETE_SELF = 1024 };
enum { IN_MODIFY = 2 };
enum { IN_MOVE_SELF = 2048 };
enum { IN_MOVED_FROM = 64 };
enum { IN_MOVED_TO = 128 };
enum { IN_OPEN = 32 };
enum { IN_ALL_EVENTS = 4095 };
enum { IN_MOVE = 192 };
enum { IN_CLOSE = 24 };
enum { IN_DONT_FOLLOW = 33554432 };
enum { IN_EXCL_UNLINK = 67108864 };
enum { IN_MASK_ADD = 536870912 };
enum { IN_ONESHOT = 2147483648 };
enum { IN_ONLYDIR = 16777216 };
enum { IN_IGNORED = 32768 };
enum { IN_ISDIR = 1073741824 };
enum { IN_Q_OVERFLOW = 16384 };
enum { IN_UNMOUNT = 8192 };
enum { IN_NONBLOCK = 2048 };
enum { IN_CLOEXEC = 524288 };
int inotify_init(void) __attribute__((nothrow, leaf));
int inotify_init1(int) __attribute__((nothrow, leaf));
int inotify_add_watch(int, const char *, uint32_t) __attribute__((nothrow, leaf));
int inotify_rm_watch(int, int) __attribute__((nothrow, leaf));
struct inotify_event {
  int wd;
  uint32_t mask;
  uint32_t cookie;
  uint32_t len;
  char name[];
};
]])
