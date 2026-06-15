local ffi = require("ffi")

ffi.cdef([[
enum { UPDATE_MODE_PARTIAL = 0 };
enum { UPDATE_MODE_FULL = 1 };
enum { TEMP_USE_AMBIENT = 4096 };
enum { WAVEFORM_MODE_AUTO = 257 };
enum { WAVEFORM_MODE_INIT = 0 };
enum { WAVEFORM_MODE_DU = 1 };
enum { WAVEFORM_MODE_GC16 = 2 };
enum { WAVEFORM_MODE_A2 = 4 };
enum { WAVEFORM_MODE_GL16 = 5 };
enum { WAVEFORM_MODE_GLR16 = 6 };
enum { WAVEFORM_MODE_GLD16 = 7 };
enum { EPDC_FLAG_ENABLE_INVERSION = 1 };
enum { EPDC_FLAG_FORCE_MONOCHROME = 2 };
enum { EPDC_FLAG_USE_ALT_BUFFER = 256 };
enum { EPDC_FLAG_USE_CMAP = 4 };
enum { EPDC_FLAG_TEST_COLLISION = 512 };
enum { EPDC_FLAG_GROUP_UPDATE = 1024 };
enum { EPDC_FLAG_USE_DITHERING_Y1 = 8192 };
enum { EPDC_FLAG_USE_DITHERING_Y4 = 16384 };
enum { EPDC_FLAG_USE_AAD = 4096 };
enum { EPDC_FLAG_USE_DITHERING_NTX_D8 = 1048576 };
struct mxcfb_rect {
  unsigned int top;
  unsigned int left;
  unsigned int width;
  unsigned int height;
};
struct mxcfb_alt_buffer_data {
  void *virt_addr;
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
enum { MXCFB_SEND_UPDATE = 1078216238 };
enum { MXCFB_WAIT_FOR_UPDATE_COMPLETE = 1074021935 };
]])
