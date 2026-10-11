local ffi
local Webp

describe("ffi/webp module", function()
  setup(function()
    require("commonrequire")
    ffi = require("ffi")
    Webp = require("ffi/webp")
  end)

  it(
    "cleans up decoder when WebPAnimDecoderGetInfo fails in fromData",
    function()
      local deleted = false
      local up_idx = 1
      local name, orig_libwebpdemux = debug.getupvalue(Webp.fromData, up_idx)
      if name ~= "libwebpdemux" then
        up_idx = 2
        orig_libwebpdemux = select(2, debug.getupvalue(Webp.fromData, up_idx))
      end

      local mock_libwebpdemux = setmetatable({
        WebPAnimDecoderOptionsInitInternal = function(...)
          return 1
        end,
        WebPAnimDecoderNewInternal = function(...)
          return ffi.cast("void*", 0x1234)
        end,
        WebPAnimDecoderGetInfo = function(...)
          return 0
        end,
        WebPAnimDecoderDelete = function(_)
          deleted = true
        end,
      }, { __index = orig_libwebpdemux })

      debug.setupvalue(Webp.fromData, up_idx, mock_libwebpdemux)

      local ok, err = pcall(function()
        Webp.fromData("dummy_webp_data")
      end)

      debug.setupvalue(Webp.fromData, up_idx, orig_libwebpdemux)

      assert.is_false(ok)
      assert.is_not_nil(
        string.match(tostring(err), "WebPAnimDecoderGetInfo%(%) failed")
      )
      assert.is_true(deleted)
    end
  )
end)
