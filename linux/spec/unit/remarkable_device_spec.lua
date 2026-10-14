-- luacheck: ignore 122
local orig_open = io.open
local orig_popen = io.popen
local orig_execute = os.execute

-- Intercept sysfs machine model check during file load
io.open = function(path, mode)
  if path == "/sys/devices/soc0/machine" then
    return {
      read = function(self, fmt)
        return "reMarkable 1.0"
      end,
      close = function(self) end,
    }
  end
  return orig_open(path, mode)
end

require("commonrequire")
local C = require("ffi").C
local Geom = require("ui/geometry")

package.loaded["device/remarkable/device"] = nil
local Remarkable1 = require("device/remarkable/device")

-- Restore io.open after initial require
io.open = orig_open

describe("Remarkable device", function()
  describe("hardware properties and models", function()
    it("reports correct model and capabilities for reMarkable 1", function()
      assert.are.equal("reMarkable 1.0", Remarkable1.model)
      assert.is_true(Remarkable1:isRemarkable())
      assert.is_true(Remarkable1:supportsScreensaver())
      assert.is_true(Remarkable1:canSuspend())
      assert.is_false(Remarkable1:hasFrontlight())
      assert.are.equal("/home/root", Remarkable1.home_dir)
      assert.are.equal(
        "/usr/share/remarkable/poweroff.png",
        Remarkable1:getDefaultCoverPath()
      )
    end)
  end)

  describe("touch coordinate adjustments", function()
    it("mirrors and scales ABS_MT coordinates for Remarkable1", function()
      local ev_x = { type = C.EV_ABS, code = C.ABS_MT_POSITION_X, value = 100 }
      local ev_y = { type = C.EV_ABS, code = C.ABS_MT_POSITION_Y, value = 200 }
      local by = { mt_scale_x = 2, mt_scale_y = 1.5 }

      Remarkable1:adjustTouchEvent(ev_x, by)
      -- Remarkable1.mt_width is 767: (767 - 100) * 2 = 1334
      assert.are.equal(1334, ev_x.value)

      Remarkable1:adjustTouchEvent(ev_y, by)
      -- Remarkable1.mt_height is 1023: (1023 - 200) * 1.5 = 1234.5
      assert.are.equal(1234.5, ev_y.value)
    end)
  end)

  describe("setDateTime", function()
    local executed_cmd = nil

    before_each(function()
      executed_cmd = nil
      os.execute = function(cmd)
        executed_cmd = cmd
        return 0
      end
    end)

    after_each(function()
      os.execute = orig_execute
    end)

    it("formats full date and time for timedatectl", function()
      local res = Remarkable1:setDateTime(2026, 10, 10, 14, 30, 0)
      assert.is_true(res)
      assert.are.equal(
        "timedatectl set-time '2026-10-10 14:30:0'",
        executed_cmd
      )
    end)

    it("formats time-only for timedatectl when date parts omitted", function()
      local res = Remarkable1:setDateTime(nil, nil, nil, 9, 15, 0)
      assert.is_true(res)
      assert.are.equal("timedatectl set-time '9:15'", executed_cmd)
    end)

    it("returns true without executing when hour or min is nil", function()
      local res = Remarkable1:setDateTime(2026, 10, 10, nil, 15, 0)
      assert.is_true(res)
      assert.is_nil(executed_cmd)
    end)
  end)

  describe("power actions", function()
    local executed_cmds = {}

    before_each(function()
      executed_cmds = {}
      os.execute = function(cmd)
        table.insert(executed_cmds, cmd)
        return 0
      end
    end)

    after_each(function()
      os.execute = orig_execute
    end)

    it("executes wifi disable and systemctl suspend on suspend", function()
      Remarkable1:suspend()
      assert.are.equal("./disable-wifi.sh", executed_cmds[1])
      assert.are.equal("systemctl suspend", executed_cmds[2])
    end)

    it("executes systemctl poweroff on powerOff", function()
      Remarkable1:powerOff()
      assert.are.equal("systemctl poweroff", executed_cmds[1])
    end)

    it("executes systemctl reboot on reboot", function()
      Remarkable1:reboot()
      assert.are.equal("systemctl reboot", executed_cmds[1])
    end)
  end)

  describe("device initialization and defect tests", function()
    local saved_screen_mod
    local saved_powerd_mod
    local saved_input_mod
    local mock_input_instance
    local registered_hooks = {}
    local opened_paths = {}

    before_each(function()
      registered_hooks = {}
      opened_paths = {}
      mock_input_instance = {
        open = function(self, path)
          table.insert(opened_paths, path)
        end,
        registerEventAdjustHook = function(self, hook, args)
          table.insert(registered_hooks, { hook = hook, args = args })
        end,
      }

      saved_screen_mod = package.loaded["ffi/framebuffer_mxcfb"]
      saved_powerd_mod = package.loaded["device/remarkable/powerd"]
      saved_input_mod = package.loaded["device/input"]

      package.loaded["ffi/framebuffer_mxcfb"] = {
        new = function()
          return {
            DEVICE_ROTATED_UPRIGHT = 0,
            getRawSize = function()
              return Geom:new({ w = 1404, h = 1872 })
            end,
            setViewport = function() end,
            getHWNightmode = function()
              return false
            end,
            setNightmode = function() end,
            getRotationMode = function()
              return 0
            end,
            setRotationMode = function() end,
            setupDithering = function() end,
          }
        end,
      }

      package.loaded["device/remarkable/powerd"] = {
        new = function()
          return {}
        end,
      }

      package.loaded["device/input"] = {
        new = function()
          return mock_input_instance
        end,
      }
    end)

    after_each(function()
      package.loaded["ffi/framebuffer_mxcfb"] = saved_screen_mod
      package.loaded["device/remarkable/powerd"] = saved_powerd_mod
      package.loaded["device/input"] = saved_input_mod
      os.execute = orig_execute
      io.popen = orig_popen
    end)

    it("kernel version parsing treats Linux 6.10+ as mainline", function()
      -- On Linux 6.10+, release must be parsed correctly so is_mainline evaluates to true
      os.execute = function()
        return 1
      end
      io.popen = function(cmd, mode)
        if cmd == "uname -r" then
          return {
            read = function(self, fmt)
              return "6.10.0-rm"
            end,
            close = function(self) end,
          }
        end
        return orig_popen(cmd, mode)
      end

      local dev = Remarkable1:extend({})
      dev:init()

      assert.are.equal(
        "/dev/input/touchscreen0",
        dev.input_ts,
        "Linux 6.10+ should be recognized as mainline kernel"
      )
    end)
  end)
end)
