local ffi = require("ffi")

ffi.cdef([[
unsigned long compressBound(unsigned long);
int compress2(unsigned char *, unsigned long *, const unsigned char *, unsigned long, int);
unsigned long crc32(unsigned long, const unsigned char *, unsigned int);
int uncompress(unsigned char *, unsigned long *, const unsigned char *, unsigned long);
]])
