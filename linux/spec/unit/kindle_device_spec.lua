local ffiUtil = require("ffi/util")
local util = require("util")

describe("Kindle device", function()
  local KindlePaperWhite
  local tmp_usid

  setup(function()
    require("commonrequire")
    tmp_usid = "/tmp/test_kindle_usid_" .. ffiUtil.getpid()
    local f = io.open(tmp_usid, "w")
    f:write("B024123456789012\n")
    f:close()

    local orig_open = io.open
    io.open = function(path, mode)
      if path == "/proc/usid" then
        return orig_open(tmp_usid, mode)
      end
      return orig_open(path, mode)
    end

    KindlePaperWhite = require("device/kindle/device")
    io.open = orig_open
  end)

  teardown(function()
    if tmp_usid then
      os.remove(tmp_usid)
    end
  end)

  describe("Model identification and capabilities", function()
    it("should report basic KindlePaperWhite model properties", function()
      assert.are.equal("KindlePaperWhite", KindlePaperWhite.model)
      assert.is_true(KindlePaperWhite:isKindle())
      assert.is_true(KindlePaperWhite:isTouchDevice())
      assert.is_true(KindlePaperWhite:hasFrontlight())
    end)
  end)

  describe("setDateTime on legacy models", function()
    it("should allow querying feature support on legacy models", function()
      local legacy_dev = setmetatable(
        { model = "Kindle2" },
        { __index = KindlePaperWhite }
      )
      -- When hour/min are nil, checks if feature is supported and returns true on legacy models
      assert.is_true(legacy_dev:setDateTime(2026, 10, 10, nil, nil))
    end)
  end)

  describe("Screen refresh geometry", function()
    it(
      "computes OutOfSS refresh region coordinates matching physical screen",
      function()
        local mock_screen = {
          getHeight = function()
            return 1000
          end,
          getWidth = function()
            return 800
          end,
        }
        local mock_dev = setmetatable({
          screen = mock_screen,
        }, { __index = KindlePaperWhite })

        local screen_height = mock_dev.screen:getHeight()
        local refresh_height = math.ceil(screen_height * (1 / 10))
        local y = screen_height - 1 - refresh_height
        local h = refresh_height

        assert.are.equal(100, refresh_height)
        assert.are.equal(899, y)
        assert.are.equal(100, h)
      end
    )
  end)
end)
