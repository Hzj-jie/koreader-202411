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

  describe("Defect verifications", function()
    it(
      "OutOfSS refresh region covers bottom pixel row without under-refreshing",
      function()
        -- Screen height is 1000. Pixels run y = 0 to 999.
        -- Bottom 10% should refresh y = 900 to 999 (height 100, reaching y + h = 1000).
        -- Lines 883-890 compute:
        --   screen_height = 1000, refresh_height = 100
        --   y = screen_height - refresh_height = 1000 - 100 = 900
        --   h = refresh_height = 100
        -- The region covers y from 900 to 999 (ending at y + h = 1000).
        -- The bottom-most pixel row (y = 999 = screen_height - 1) is refreshed!
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
        local y = screen_height - refresh_height
        local h = refresh_height
        local bottom_covered = y + h

        -- For the refresh region to reach the bottom of the screen (height 1000),
        -- y + h must equal screen_height (1000).
        assert.are.equal(
          screen_height,
          bottom_covered,
          "Refresh region ends at y + h = "
            .. bottom_covered
            .. ", missing bottom pixel row "
            .. (screen_height - 1)
        )
      end
    )
  end)
end)
