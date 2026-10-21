-- luacheck: ignore 122
local ffi
local input

describe("ffi/input_android module", function()
  local mock_android
  local poll_state_result

  setup(function()
    require("commonrequire")
    ffi = require("ffi")

    ffi.cdef([[
      struct android_app;
      struct android_poll_source {
        int32_t id;
        struct android_app* app;
        void (*process)(struct android_app* app, struct android_poll_source* source);
      };
      enum {
        ALOOPER_POLL_WAKE = -1,
        ALOOPER_POLL_CALLBACK = -2,
        ALOOPER_POLL_TIMEOUT = -3,
        ALOOPER_POLL_ERROR = -4,
      };
    ]])

    mock_android = {
      LOGI = function() end,
      LOGE = function() end,
      lib = {
        ALooper_pollOnce = function()
          return poll_state_result
        end,
      },
      glue = {},
      app = {
        destroyRequested = 0,
      },
    }

    package.loaded["android"] = mock_android
    package.loaded["ffi/input_android"] = nil
    input = require("ffi/input_android")
  end)

  it("exposes is_ffi interface property", function()
    assert.is_true(input.is_ffi)
  end)

  it("handles poll timeout by returning false and ETIME", function()
    poll_state_result = ffi.C.ALOOPER_POLL_TIMEOUT
    local ok, err = input.waitForEvent(0, 500)
    assert.is_false(ok)
    assert.are.equal(ffi.C.ETIME, err)
  end)

  it(
    "returns nil on ALOOPER_POLL_ERROR indicating catastrophic failure to UIManager",
    function()
      poll_state_result = ffi.C.ALOOPER_POLL_ERROR

      local ok, err = input.waitForEvent(0, 500)
      assert.is_nil(ok)
      assert.is_nil(err)
    end
  )
end)
