local ffi = require("ffi")

ffi.cdef([[
enum { UPDATE_MODE_PARTIAL = 0 };
enum { UPDATE_MODE_FULL = 1 };
enum { WAVEFORM_MODE_INIT = 0 };
enum { WAVEFORM_MODE_DU = 1 };
enum { WAVEFORM_MODE_GC16 = 2 };
enum { WAVEFORM_MODE_GL16 = 3 };
enum { WAVEFORM_MODE_A2 = 4 };
enum { WAVEFORM_MODE_AUTO = 257 };
enum { TEMP_USE_AMBIENT = 4096 };
enum { TEMP_USE_REMARKABLE = 24 };
enum { EPDC_FLAG_ENABLE_INVERSION = 1 };
enum { EPDC_FLAG_FORCE_MONOCHROME = 2 };
enum { EPDC_FLAG_USE_CMAP = 4 };
enum { EPDC_FLAG_USE_ALT_BUFFER = 256 };
enum { EPDC_FLAG_USE_DITHERING_Y1 = 8192 };
enum { EPDC_FLAG_USE_DITHERING_Y4 = 16384 };
enum { EPDC_FLAG_USE_REGAL = 32768 };
enum mxcfb_dithering_mode {
  EPDC_FLAG_USE_DITHERING_PASSTHROUGH = 0,
  EPDC_FLAG_USE_DITHERING_FLOYD_STEINBERG = 1,
  EPDC_FLAG_USE_DITHERING_ATKINSON = 2,
  EPDC_FLAG_USE_DITHERING_ORDERED = 3,
  EPDC_FLAG_USE_DITHERING_QUANT_ONLY = 4,
  EPDC_FLAG_USE_DITHERING_MAX = 5,
};
struct mxcfb_rect {
  unsigned int top;
  unsigned int left;
  unsigned int width;
  unsigned int height;
};
struct mxcfb_alt_buffer_data {
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
  int dither_mode;
  int quant_bit;
  struct mxcfb_alt_buffer_data alt_buffer_data;
};
struct mxcfb_update_marker_data {
  unsigned int update_marker;
  unsigned int collision_test;
};
enum { MXCFB_SEND_UPDATE = 1078478382 };
enum { MXCFB_WAIT_FOR_UPDATE_COMPLETE = 3221767727 };
]])
