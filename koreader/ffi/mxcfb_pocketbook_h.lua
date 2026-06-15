local ffi = require("ffi")

ffi.cdef([[
enum {
  UPDATE_MODE_PARTIAL = 0,
  UPDATE_MODE_FULL = 1,
  UPDATE_MODE_PARTIALHQ = 2,
  UPDATE_MODE_FULLHQ = 3,
  EPDC_WFTYPE_INIT = 0,
  EPDC_WFTYPE_DU = 1,
  EPDC_WFTYPE_GC16 = 2,
  EPDC_WFTYPE_GC4 = 3,
  EPDC_WFTYPE_A2 = 4,
  EPDC_WFTYPE_GL16 = 5,
  EPDC_WFTYPE_GS16 = 14,
  EPDC_WFTYPE_A2IN = 6,
  EPDC_WFTYPE_A2OUT = 7,
  EPDC_WFTYPE_DU4 = 8,
  EPDC_WFTYPE_AA = 9,
  EPDC_WFTYPE_AAD = 10,
  EPDC_WFTYPE_GC16HQ = 15,
  WAVEFORM_MODE_INIT = 0,
  WAVEFORM_MODE_DU = 1,
  WAVEFORM_MODE_GC16 = 2,
  WAVEFORM_MODE_GC4 = 3,
  WAVEFORM_MODE_A2 = 4,
  WAVEFORM_MODE_GL16 = 5,
  WAVEFORM_MODE_GS16 = 14,
  WAVEFORM_MODE_A2IN = 6,
  WAVEFORM_MODE_A2OUT = 7,
  WAVEFORM_MODE_DU4 = 8,
  WAVEFORM_MODE_REAGL = 9,
  WAVEFORM_MODE_REAGLD = 10,
  WAVEFORM_MODE_GC16HQ = 15,
  WAVEFORM_MODE_AUTO = 257,
  TEMP_USE_AMBIENT = 4096,
  EPDC_FLAG_ENABLE_INVERSION = 1,
  EPDC_FLAG_FORCE_MONOCHROME = 2,
  EPDC_FLAG_USE_CMAP = 4,
  EPDC_FLAG_USE_ALT_BUFFER = 256,
  EPDC_FLAG_TEST_COLLISION = 512,
  EPDC_FLAG_GROUP_UPDATE = 1024,
  EPDC_FLAG_USE_AAD = 4096,
  EPDC_FLAG_USE_DITHERING_Y1 = 8192,
  EPDC_FLAG_USE_DITHERING_Y4 = 16384,
  EPDC_FLAG_USE_DITHERING_NTX_D8 = 1048576
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
  struct mxcfb_alt_buffer_data alt_buffer_data;
};
struct mxcfb_update_marker_data {
  unsigned int update_marker;
  unsigned int collision_test;
};
enum {
  MXCFB_SEND_UPDATE = 1077954094,
  MXCFB_WAIT_FOR_UPDATE_COMPLETE_PB = 1074021935,
  EPDC_GET_UPDATE_STATE = 2147763797
};
]])
