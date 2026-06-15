local ffi = require("ffi")

ffi.cdef([[
enum {
  EVIOCGRAB = 1074021776,
  EVIOCGREP = 2148025603,
  EVIOCSREP = 1074283779,
  EV_SYN = 0,
  EV_KEY = 1,
  EV_REL = 2,
  EV_ABS = 3,
  EV_MSC = 4,
  EV_SW = 5,
  EV_LED = 17,
  EV_SND = 18,
  EV_REP = 20,
  EV_FF = 21,
  EV_PWR = 22,
  EV_FF_STATUS = 23,
  EV_MAX = 31,
  SYN_REPORT = 0,
  SYN_CONFIG = 1,
  SYN_MT_REPORT = 2,
  SYN_DROPPED = 3,
  KEY_BATTERY = 236,
  BTN_TOOL_PEN = 320,
  BTN_TOOL_FINGER = 325,
  BTN_TOOL_RUBBER = 321,
  BTN_TOUCH = 330,
  BTN_STYLUS = 331,
  BTN_STYLUS2 = 332,
  BTN_TOOL_DOUBLETAP = 333,
  ABS_X = 0,
  ABS_Y = 1,
  ABS_PRESSURE = 24,
  ABS_DISTANCE = 25,
  ABS_TILT_X = 26,
  ABS_TILT_Y = 27,
  ABS_MT_SLOT = 47,
  ABS_MT_TOUCH_MAJOR = 48,
  ABS_MT_TOUCH_MINOR = 49,
  ABS_MT_WIDTH_MAJOR = 50,
  ABS_MT_WIDTH_MINOR = 51,
  ABS_MT_ORIENTATION = 52,
  ABS_MT_POSITION_X = 53,
  ABS_MT_POSITION_Y = 54,
  ABS_MT_TOOL_TYPE = 55,
  ABS_MT_BLOB_ID = 56,
  ABS_MT_TRACKING_ID = 57,
  ABS_MT_PRESSURE = 58,
  ABS_MT_DISTANCE = 59,
  ABS_MT_TOOL_X = 60,
  ABS_MT_TOOL_Y = 61,
  SW_ROTATE_LOCK = 12,
  SW_MACHINE_COVER = 16,
  MSC_GESTURE = 2,
  MSC_RAW = 3,
  REP_DELAY = 0,
  REP_PERIOD = 1,
  REP_CNT = 2
};
struct input_event {
  struct timeval time;
  unsigned short type;
  unsigned short code;
  int value;
};
]])

-- Include our custom stuff, too
require("ffi/custom_input_h")
