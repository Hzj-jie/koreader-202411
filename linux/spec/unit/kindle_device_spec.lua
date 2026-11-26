local ffiUtil = require("ffi/util")
local util = require("util")

describe("Kindle device", function()
  local KindlePaperWhite
  local tmp_usid

  local function loadKindleModel(serial_number)
    local f = assert(io.open(tmp_usid, "w"))
    f:write(serial_number .. "\n")
    f:close()

    local orig_open = io.open
    io.open = function(path, mode)
      if path == "/proc/usid" then
        return orig_open(tmp_usid, mode)
      end
      return orig_open(path, mode)
    end

    package.loaded["device/kindle/device"] = nil
    local dev = require("device/kindle/device")
    io.open = orig_open
    return dev
  end

  setup(function()
    require("commonrequire")
    tmp_usid = "/tmp/test_kindle_usid_" .. ffiUtil.getpid()
    KindlePaperWhite = loadKindleModel("B024123456789012")
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

  describe("hasNetwork and setDateTime across Kindle models", function()
    it("reports hasNetwork accurately and gates setDateTime on legacy models without network", function()
      finally(function()
        package.loaded["device/kindle/device"] = KindlePaperWhite
      end)

      local cases = {
        { sn = "B002123456789012", model = "Kindle2", has_network = false },
        { sn = "B004123456789012", model = "Kindle2", has_network = false },
        { sn = "B009123456789012", model = "KindleDXG", has_network = false },
        { sn = "B008123456789012", model = "Kindle3", has_network = true },
        { sn = "B00E123456789012", model = "Kindle4", has_network = true },
      }
      for _, case in ipairs(cases) do
        local dev = loadKindleModel(case.sn)
        assert.are.equal(case.model, dev.model)
        assert.are.equal(case.has_network, dev:hasNetwork())
        if case.has_network then
          assert.is_nil(dev:setDateTime(2026, 10, 10, nil, nil))
        else
          -- When hour/min are nil, checks if feature is supported and returns true on networkless models
          assert.is_true(dev:setDateTime(2026, 10, 10, nil, nil))
        end
      end

      assert.is_true(KindlePaperWhite:hasNetwork())
      assert.is_nil(KindlePaperWhite:setDateTime(2026, 10, 10, nil, nil))
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

    it("calls Screensaver:close before afterResume on OutOfSS", function()
      mock_dev.screen_saver_mode = true
      table.insert(mock_dev.input.fake_event_args.OutOfSS, 6)
      UIManager.event_handlers.OutOfSS("OutOfSS")
      assert.are.same({
        "Screensaver:close",
        "powerd:afterResume",
      }, calls)
    end)

    it(
      "skips Screensaver:close on OutOfSS when not in screensaver mode",
      function()
        mock_dev.screen_saver_mode = false
        table.insert(mock_dev.input.fake_event_args.OutOfSS, 6)
        UIManager.event_handlers.OutOfSS("OutOfSS")
        assert.are.same({
          "powerd:afterResume",
        }, calls)
      end
    )

    it(
      "stops native framework and clears screen_saver_mode on OutOfSS on SO Kindles",
      function()
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
      end
    )

    it(
      "pops WakeupFromSuspend arg and calls powerd:wakeupFromSuspend without args before OutOfSS",
      function()
        mock_dev.screen_saver_mode = true
        local wakeup_arg_count = nil
        mock_dev.powerd.wakeupFromSuspend = function(...)
          wakeup_arg_count = select("#", ...)
          table.insert(calls, "powerd:wakeupFromSuspend")
        end

        table.insert(mock_dev.input.fake_event_args.WakeupFromSuspend, 42)
        UIManager.event_handlers.WakeupFromSuspend("WakeupFromSuspend")
        assert.are.equal(0, #mock_dev.input.fake_event_args.WakeupFromSuspend)

        table.insert(mock_dev.input.fake_event_args.OutOfSS, 6)
        UIManager.event_handlers.OutOfSS("OutOfSS")

        assert.are.equal(1, wakeup_arg_count)
        assert.are.same({
          "powerd:wakeupFromSuspend",
          "Screensaver:close",
          "powerd:afterResume",
        }, calls)
      end
    )
  end)

  describe("canUseCBB on einkfb Kindles", function()
    it(
      "enables C blitter on Kindle2, KindleDXG, Kindle3, and Kindle4",
      function()
        local cases = {
          { serial = "B002123456789012\n", model = "Kindle2" },
          { serial = "B009123456789012\n", model = "KindleDXG" },
          { serial = "B008123456789012\n", model = "Kindle3" },
          { serial = "B00E123456789012\n", model = "Kindle4" },
        }
        local orig_open = io.open
        local orig_loaded = package.loaded["device/kindle/device"]
        local usid_path = "/tmp/test_kindle_usid_cbb_" .. ffiUtil.getpid()
        finally(function()
          io.open = orig_open
          os.remove(usid_path)
          package.loaded["device/kindle/device"] = orig_loaded
        end)

        for _, case in ipairs(cases) do
          local f = assert(orig_open(usid_path, "w"))
          f:write(case.serial)
          f:close()
          io.open = function(path, mode)
            if path == "/proc/usid" then
              return orig_open(usid_path, mode)
            end
            return orig_open(path, mode)
          end
          package.loaded["device/kindle/device"] = nil
          local dev = require("device/kindle/device")
          assert.are.equal(case.model, dev.model)
          assert.is_true(dev:canUseCBB())
          assert.is_false(dev:canHWInvert())
          assert.is_false(dev:canModifyFBInfo())
        end
      end
    )
  end)

  describe("NetworkMgr.isConnected", function()
    local LibLipcs

    before_each(function()
      LibLipcs = require("liblipcs")
    end)

    it(
      "removes Kindle:isWifiConnected and short-circuits NetworkMgr:isConnected when isWifiUp is false",
      function()
        assert.is_nil(KindlePaperWhite.isWifiConnected)

        local cm_state_queries = 0
        local orig_accessor = LibLipcs.accessor
        local orig_popen = io.popen
        local mock_dev = setmetatable({
          isWifiUp = function()
            return false
          end,
        }, { __index = KindlePaperWhite })
        finally(function()
          LibLipcs.accessor = orig_accessor
          io.popen = orig_popen
        end)

        LibLipcs.accessor = function()
          cm_state_queries = cm_state_queries + 1
          return {}
        end
        io.popen = function() --luacheck: ignore
          cm_state_queries = cm_state_queries + 1
          return nil
        end

        local net_mgr = {}
        mock_dev:initNetworkManager(net_mgr)

        assert.is_false(net_mgr:isWifiOn())
        assert.is_false(net_mgr:isConnected())
        assert.are.equal(0, cm_state_queries)
      end
    )

    it(
      "checks cmState == CONNECTED via LibLipcs or lipc-get-prop fallback when isWifiUp is true",
      function()
        local cm_state = "DISCONNECTED"
        local is_fake = false
        local orig_accessor = LibLipcs.accessor
        local orig_is_fake = LibLipcs.isFake
        local orig_popen = io.popen
        local mock_dev = setmetatable({
          isWifiUp = function()
            return true
          end,
        }, { __index = KindlePaperWhite })
        finally(function()
          LibLipcs.accessor = orig_accessor
          LibLipcs.isFake = orig_is_fake
          io.popen = orig_popen
        end)

        local queried_props = {}
        LibLipcs.isFake = function()
          return is_fake
        end
        LibLipcs.accessor = function()
          return {
            get_string_property = function(_, pub, prop)
              table.insert(queried_props, pub .. ":" .. prop)
              return cm_state
            end,
          }
        end
        local popen_cmds = {}
        io.popen = function(cmd) --luacheck: ignore
          table.insert(popen_cmds, cmd)
          if not cm_state then
            return nil
          end
          return {
            read = function()
              return cm_state
            end,
            close = function() end,
          }
        end

        local net_mgr = {}
        mock_dev:initNetworkManager(net_mgr)

        assert.is_true(net_mgr:isWifiOn())
        assert.is_false(net_mgr:isConnected())
        assert.are.same({ "com.lab126.wifid:cmState" }, queried_props)

        cm_state = "CONNECTED"
        assert.is_true(net_mgr:isConnected())

        is_fake = true
        cm_state = "READY"
        assert.is_false(net_mgr:isConnected())

        cm_state = "CONNECTED"
        assert.is_true(net_mgr:isConnected())

        cm_state = nil
        assert.is_false(net_mgr:isConnected())
        assert.are.same({
          "lipc-get-prop com.lab126.wifid cmState",
          "lipc-get-prop com.lab126.wifid cmState",
          "lipc-get-prop com.lab126.wifid cmState",
        }, popen_cmds)
      end
    )
  end)
end)
