describe("sysfs_light", function()
  local SysfsLight
  local mock_ffi_util

  before_each(function()
    package.loaded["dbg"] = {
      guard = function(self, mod, method, pre_guard, post_guard)
        local old_method = mod[method]
        mod[method] = function(...)
          if pre_guard then pre_guard(...) end
          local values = table.pack(old_method(...))
          if post_guard then post_guard(...) end
          return unpack(values, 1, values.n)
        end
      end,
      dassert = assert,
    }

    mock_ffi_util = {
      writeToSysfs = spy.new(function() end),
    }
    package.loaded["ffi/util"] = mock_ffi_util

    package.loaded["device/sysfs_light"] = nil
    SysfsLight = require("device/sysfs_light")
  end)

  after_each(function()
    package.loaded["dbg"] = nil
    package.loaded["ffi/util"] = nil
    package.loaded["device/sysfs_light"] = nil
  end)

  describe("new", function()
    it("should initialize a new SysfsLight instance", function()
      local light = SysfsLight:new{ exponent = 0.5 }
      assert.are.equal(0.5, light.exponent)
    end)
  end)

  describe("guards and input assertions", function()
    it("should assert if setBrightness is called with out of range value", function()
      local light = SysfsLight:new{}
      assert.has_error(function() light:setBrightness(-1) end)
      assert.has_error(function() light:setBrightness(101) end)
    end)

    it("should assert if setWarmth is called with out of range value", function()
      local light = SysfsLight:new{}
      assert.has_error(function() light:setWarmth(-1) end)
      assert.has_error(function() light:setWarmth(101) end)
    end)

    it("should assert if setNaturalBrightness is called with out of range values", function()
      local light = SysfsLight:new{}
      assert.has_error(function() light:setNaturalBrightness(-1, 50) end)
      assert.has_error(function() light:setNaturalBrightness(50, 101) end)
    end)
  end)

  describe("setNaturalBrightness with frontlight_mixer", function()
    it("should use frontlight_ioctl if present to set brightness", function()
      local mock_ioctl = {
        setBrightness = spy.new(function() end),
      }
      local light = SysfsLight:new{
        frontlight_mixer = "/sys/mixer",
        frontlight_white = "/sys/white",
        frontlight_ioctl = mock_ioctl,
      }

      light:setBrightness(75)

      assert.spy(mock_ioctl.setBrightness).was.called_with(mock_ioctl, 75)
      assert.spy(mock_ffi_util.writeToSysfs).was_not.called()
      assert.are.equal(75, light.current_brightness)
    end)

    it("should write to sysfs directly if frontlight_ioctl is absent", function()
      local light = SysfsLight:new{
        frontlight_mixer = "/sys/mixer",
        frontlight_white = "/sys/white",
      }

      light:setBrightness(75)

      assert.spy(mock_ffi_util.writeToSysfs).was.called_with(75, "/sys/white")
      assert.are.equal(75, light.current_brightness)
    end)

    it("should set warmth without inverting if nl_inverted is false/nil", function()
      local light = SysfsLight:new{
        frontlight_mixer = "/sys/mixer",
        nl_inverted = false,
      }

      light:setWarmth(40)

      assert.spy(mock_ffi_util.writeToSysfs).was.called_with(40, "/sys/mixer")
      assert.are.equal(40, light.current_warmth)
    end)

    it("should set warmth with inverting (nl_max - warmth) if nl_inverted is true", function()
      local light = SysfsLight:new{
        frontlight_mixer = "/sys/mixer",
        nl_max = 100,
        nl_inverted = true,
      }

      light:setWarmth(40)

      assert.spy(mock_ffi_util.writeToSysfs).was.called_with(60, "/sys/mixer")
      assert.are.equal(40, light.current_warmth)
    end)
  end)

  describe("setNaturalBrightness without frontlight_mixer (RGB LEDs)", function()
    it("should compute and set white, green, red lights with bl_power logic", function()
      local light = SysfsLight:new{
        frontlight_white = "/sys/white",
        frontlight_green = "/sys/green",
        frontlight_red = "/sys/red",
        exponent = 0.25,
        white_gain = 25,
        red_gain = 24,
        green_gain = 24,
        white_offset = -25,
        red_offset = 0,
        green_offset = -65,
      }

      light:setNaturalBrightness(50, 50)

      assert.spy(mock_ffi_util.writeToSysfs).was.called_with(31, "/sys/white/bl_power")
      assert.spy(mock_ffi_util.writeToSysfs).was.called_with(151, "/sys/white/brightness")

      assert.spy(mock_ffi_util.writeToSysfs).was.called_with(31, "/sys/green/bl_power")
      assert.spy(mock_ffi_util.writeToSysfs).was.called_with(104, "/sys/green/brightness")

      assert.spy(mock_ffi_util.writeToSysfs).was.called_with(31, "/sys/red/bl_power")
      assert.spy(mock_ffi_util.writeToSysfs).was.called_with(169, "/sys/red/brightness")
    end)

    it("should turn off bl_power if values are <= 0", function()
      local light = SysfsLight:new{
        frontlight_white = "/sys/white",
        frontlight_green = "/sys/green",
        frontlight_red = "/sys/red",
        exponent = 0.25,
        white_gain = 25,
        white_offset = -200,
      }

      light:setNaturalBrightness(10, 0)

      assert.spy(mock_ffi_util.writeToSysfs).was.called_with(0, "/sys/white/bl_power")
      assert.spy(mock_ffi_util.writeToSysfs).was.called_with(0, "/sys/white/brightness")
    end)
  end)
end)
