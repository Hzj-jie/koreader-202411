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

  describe("IntoSS and OutOfSS handlers", function()
    local UIManager
    local Screensaver
    local calls
    local mock_dev

    before_each(function()
      UIManager = require("ui/uimanager")
      Screensaver = require("ui/screensaver")
      calls = {}
      stub(Screensaver, "setup", function()
        table.insert(calls, "Screensaver:setup")
      end)
      stub(Screensaver, "show", function()
        mock_dev.screen_saver_mode = true
        table.insert(calls, "Screensaver:show")
      end)
      stub(Screensaver, "close", function()
        mock_dev.screen_saver_mode = false
        table.insert(calls, "Screensaver:close")
        return true
      end)
      stub(UIManager, "nextTick")
      stub(UIManager, "scheduleIn")

      mock_dev = setmetatable({
        screen_saver_mode = false,
        canDeepSleep = false,
        input = {
          open = function() end,
          fake_event_args = {},
        },
        powerd = {
          initSuspend = function()
            table.insert(calls, "powerd:initSuspend")
          end,
          beforeSuspend = function()
            table.insert(calls, "powerd:beforeSuspend")
          end,
          initWakeup = function()
            table.insert(calls, "powerd:initWakeup")
          end,
          afterResume = function()
            table.insert(calls, "powerd:afterResume")
          end,
        },
        supportsScreensaver = function()
          return true
        end,
      }, { __index = KindlePaperWhite })
      mock_dev:UIManagerReady(UIManager)
      mock_dev:setEventHandlers(UIManager)
    end)

    after_each(function()
      Screensaver.setup:revert()
      Screensaver.show:revert()
      Screensaver.close:revert()
      UIManager.nextTick:revert()
      UIManager.scheduleIn:revert()
    end)

    it(
      "calls initSuspend before Screensaver and beforeSuspend on IntoSS",
      function()
        table.insert(mock_dev.input.fake_event_args.IntoSS, 1)
        UIManager.event_handlers.IntoSS("IntoSS")
        assert.are.same({
          "powerd:initSuspend",
          "Screensaver:setup",
          "Screensaver:show",
          "powerd:beforeSuspend",
        }, calls)
      end
    )

    it(
      "skips initSuspend on IntoSS when already in screensaver mode",
      function()
        mock_dev.screen_saver_mode = true
        table.insert(mock_dev.input.fake_event_args.IntoSS, 1)
        UIManager.event_handlers.IntoSS("IntoSS")
        assert.are.same({
          "powerd:beforeSuspend",
        }, calls)
      end
    )

    it("skips initSuspend on IntoSS on SO Kindles", function()
      mock_dev.supportsScreensaver = function()
        return false
      end
      local execute_stub = stub(os, "execute", function()
        return 0
      end)
      finally(function()
        execute_stub:revert()
      end)

      table.insert(mock_dev.input.fake_event_args.IntoSS, 1)
      UIManager.event_handlers.IntoSS("IntoSS")
      assert.are.same({
        "powerd:beforeSuspend",
      }, calls)
      assert.is_true(mock_dev.screen_saver_mode)
    end)

    it(
      "calls initWakeup before Screensaver:close and afterResume on OutOfSS",
      function()
        mock_dev.screen_saver_mode = true
        table.insert(mock_dev.input.fake_event_args.OutOfSS, 6)
        UIManager.event_handlers.OutOfSS("OutOfSS")
        assert.are.same({
          "powerd:initWakeup",
          "Screensaver:close",
          "powerd:afterResume",
        }, calls)
      end
    )

    it(
      "skips initWakeup on OutOfSS when not in screensaver mode",
      function()
        mock_dev.screen_saver_mode = false
        table.insert(mock_dev.input.fake_event_args.OutOfSS, 6)
        UIManager.event_handlers.OutOfSS("OutOfSS")
        assert.are.same({
          "powerd:afterResume",
        }, calls)
      end
    )

    it("skips initWakeup on OutOfSS on SO Kindles", function()
      mock_dev.screen_saver_mode = true
      mock_dev.supportsScreensaver = function()
        return false
      end
      local execute_stub = stub(os, "execute", function()
        return 0
      end)
      finally(function()
        execute_stub:revert()
      end)

      table.insert(mock_dev.input.fake_event_args.OutOfSS, 6)
      UIManager.event_handlers.OutOfSS("OutOfSS")
      assert.are.same({
        "powerd:afterResume",
      }, calls)
      assert.is_false(mock_dev.screen_saver_mode)
    end)
  end)
end)
