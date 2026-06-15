local ffi = require("ffi")

ffi.cdef([[
struct mxcfb_rect {
  unsigned int top;
  unsigned int left;
  unsigned int width;
  unsigned int height;
};

struct mxcfb_alt_buffer_data {
  void* virt_addr;
  unsigned int phys_addr;
  unsigned int width;
  unsigned int height;
  struct mxcfb_rect alt_update_region;
};

struct mxcfb_update_data {
  struct mxcfb_rect update_region;
  unsigned int waveform_mode;
  unsigned int update_mode;
  unsigned int update_marker;
  int temp;
  unsigned int flags;
  struct mxcfb_alt_buffer_data alt_buffer_data;
};

enum { UPDATE_MODE_PARTIAL = 0 };
enum { UPDATE_MODE_FULL = 1 };

enum { WAVEFORM_MODE_INIT = 0 };
enum { WAVEFORM_MODE_DU = 1 };
enum { WAVEFORM_MODE_GC16 = 2 };
enum { WAVEFORM_MODE_GC4 = 3 };
enum { WAVEFORM_MODE_A2 = 4 };
enum { WAVEFORM_MODE_AUTO = 257 };
enum { TEMP_USE_AMBIENT = 4096 };
enum { TEMP_USE_AUTO = 4097 }; // this does not exist, simply use a value different than above
enum { EPDC_FLAG_ENABLE_INVERSION = 1 };
enum { EPDC_FLAG_FORCE_MONOCHROME = 2 };
enum { EPDC_FLAG_USE_ALT_BUFFER = 256 };

enum { MXCFB_SEND_UPDATE = 1078216238 };
enum { MXCFB_WAIT_FOR_UPDATE_COMPLETE = 1074021935 };
]])
