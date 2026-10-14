local ffi
local Jpeg

describe("ffi/jpeg module", function()
  setup(function()
    require("commonrequire")
    ffi = require("ffi")
    Jpeg = require("ffi/jpeg")
  end)

  it("fails gracefully with error on invalid JPEG header in memory", function()
    local bad_data = "not a valid jpeg stream"
    local ok, err = pcall(function()
      Jpeg.openDocumentFromMem(bad_data, false)
    end)
    assert.is_false(ok)
    assert.is_not_nil(string.match(tostring(err), "reading JPEG header"))
  end)

  it("converts RGB pixels to accurate grayscale values", function()
    -- 1 pixel RGB: (100, 150, 200)
    -- gray = round(0.299 * 100 + 0.587 * 150 + 0.114 * 200) = round(140.75) = 141
    local buf = ffi.new("uint8_t[6]")
    buf[0] = 100
    buf[1] = 150
    buf[2] = 200

    Jpeg.convertToGray(buf, 3, 1)
    assert.are.equal(141, buf[0])
  end)

  it(
    "does not read or write past row bounds during grayscale conversion",
    function()
      -- A 2-pixel RGB row has stride = 6 (pixels 0 and 1).
      -- Allocate 9 bytes: bytes 0..5 are image data, bytes 6..8 are trailing sentinel data.
      local buf = ffi.new("uint8_t[9]")
      buf[0] = 100
      buf[1] = 100
      buf[2] = 100 -- Pixel 0 -> gray 100
      buf[3] = 200
      buf[4] = 200
      buf[5] = 200 -- Pixel 1 -> gray 200
      buf[6] = 50
      buf[7] = 50
      buf[8] = 50 -- Sentinel outside image row

      Jpeg.convertToGray(buf, 6, 1)

      assert.are.equal(100, buf[0])
      assert.are.equal(200, buf[1])
      assert.is_not_equal(50, buf[2])
    end
  )

  it(
    "frees blitbuffer when tj3Decompress8 fails in openDocumentFromMem",
    function()
      local _, orig_turbojpeg = debug.getupvalue(Jpeg.openDocumentFromMem, 1)

      local mock_turbojpeg = setmetatable({
        tj3DecompressHeader = function(...)
          return 0
        end,
        tj3Get = function(handle, param)
          return 10
        end,
        tj3Decompress8 = function(...)
          return -1
        end,
      }, { __index = orig_turbojpeg })

      local BlitBuffer = require("ffi/blitbuffer")
      local orig_bb_new = BlitBuffer.new
      local bb_freed = false
      BlitBuffer.new = function(...)
        local real_bb = orig_bb_new(...)
        return setmetatable({
          free = function(self)
            bb_freed = true
            return real_bb:free()
          end,
        }, {
          __index = real_bb,
          __newindex = real_bb,
        })
      end

      debug.setupvalue(Jpeg.openDocumentFromMem, 1, mock_turbojpeg)

      local ok, err = pcall(function()
        Jpeg.openDocumentFromMem("dummy_jpeg_data", false)
      end)

      debug.setupvalue(Jpeg.openDocumentFromMem, 1, orig_turbojpeg)
      BlitBuffer.new = orig_bb_new

      assert.is_false(ok)
      assert.is_not_nil(string.match(tostring(err), "decoding JPEG file"))
      assert.is_true(bb_freed)
    end
  )
end)
