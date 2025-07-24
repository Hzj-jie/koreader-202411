local ffi = require("ffi")

ffi.cdef([[
struct timeval {
  time_t tv_sec;
  suseconds_t tv_usec;
};
struct timespec {
  time_t tv_sec;
  long int tv_nsec;
};
struct statvfs {
  unsigned long int f_bsize;
  unsigned long int f_frsize;
  unsigned long int f_blocks;
  unsigned long int f_bfree;
  unsigned long int f_bavail;
  unsigned long int f_files;
  unsigned long int f_ffree;
  unsigned long int f_favail;
  unsigned long int f_fsid;
  unsigned long int f_flag;
  unsigned long int f_namemax;
  int __f_spare[6];
};
]])

if ffi.typeof("off_t") == nil then
  assert(ffi.typeof("time_t") == nil)
  assert(ffi.typeof("suseconds_t") == nil)
  ffi.cdef([[
typedef long int off_t;
typedef long int time_t;
typedef long int suseconds_t;
  ]])
end
