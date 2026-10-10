-- luacheck: ignore 122
describe("ReaderActivityIndicator module", function()
  local Device, LibLipcs

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Device = require("device")
    LibLipcs = require("liblipcs")
  end)

  local orig_isKindle, orig_isTouchDevice, orig_getenv
  local orig_isFake, orig_accessor

  before_each(function()
    orig_isKindle = Device.isKindle
    orig_isTouchDevice = Device.isTouchDevice
    orig_getenv = os.getenv
    orig_isFake = LibLipcs.isFake
    orig_accessor = LibLipcs.accessor
  end)

  after_each(function()
    Device.isKindle = orig_isKindle
    Device.isTouchDevice = orig_isTouchDevice
    os.getenv = orig_getenv
    LibLipcs.isFake = orig_isFake
    LibLipcs.accessor = orig_accessor
    package.loaded["apps/reader/modules/readeractivityindicator"] = nil
  end)

  it("should return stub implementation on non-Kindle devices", function()
    Device.isKindle = function()
      return false
    end

    package.loaded["apps/reader/modules/readeractivityindicator"] = nil
    local Indicator = require("apps/reader/modules/readeractivityindicator")
    assert.is_table(Indicator)
    assert.is_true(Indicator:isStub())

    assert.is_nil(Indicator:onStartActivityIndicator())
    assert.is_nil(Indicator:onStopActivityIndicator())
  end)

  it("should return stub implementation on Kindle devices without touch support", function()
    Device.isKindle = function()
      return true
    end
    Device.isTouchDevice = function()
      return false
    end

    package.loaded["apps/reader/modules/readeractivityindicator"] = nil
    local Indicator = require("apps/reader/modules/readeractivityindicator")
    assert.is_table(Indicator)
    assert.is_true(Indicator:isStub())
  end)

  it("should return stub implementation on Kindle devices when Pillow is disabled", function()
    Device.isKindle = function()
      return true
    end
    Device.isTouchDevice = function()
      return true
    end

    -- PILLOW_HARD_DISABLED
    os.getenv = function(var)
      if var == "PILLOW_HARD_DISABLED" then
        return "1"
      end
      return orig_getenv(var)
    end

    package.loaded["apps/reader/modules/readeractivityindicator"] = nil
    local Indicator1 = require("apps/reader/modules/readeractivityindicator")
    assert.is_table(Indicator1)
    assert.is_true(Indicator1:isStub())

    -- PILLOW_SOFT_DISABLED
    os.getenv = function(var)
      if var == "PILLOW_SOFT_DISABLED" then
        return "1"
      end
      return orig_getenv(var)
    end

    package.loaded["apps/reader/modules/readeractivityindicator"] = nil
    local Indicator2 = require("apps/reader/modules/readeractivityindicator")
    assert.is_table(Indicator2)
    assert.is_true(Indicator2:isStub())
  end)

  it("should initialize active indicator on Kindle and handle fake LibLipcs", function()
    Device.isKindle = function()
      return true
    end
    Device.isTouchDevice = function()
      return true
    end

    LibLipcs.isFake = function()
      return true
    end

    package.loaded["apps/reader/modules/readeractivityindicator"] = nil
    local ActiveIndicator = require("apps/reader/modules/readeractivityindicator")

    assert.is_table(ActiveIndicator)
    assert.is_false(ActiveIndicator:isStub())

    local inst = ActiveIndicator:new({
      document = {
        configurable = {
          text_wrap = 1,
        },
      },
    })

    assert.is_true(inst:onStartActivityIndicator())
    assert.is_nil(inst.indicator_started)
    assert.is_true(inst:onStopActivityIndicator())
  end)

  it("should start and stop activity indicator via LibLipcs on supported Kindle", function()
    Device.isKindle = function()
      return true
    end
    Device.isTouchDevice = function()
      return true
    end

    local lipc_calls = {}
    local mock_accessor = {
      set_string_property = function(_self, domain, prop, val)
        table.insert(lipc_calls, { domain = domain, prop = prop, val = val })
      end,
    }

    LibLipcs.isFake = function()
      return false
    end
    LibLipcs.accessor = function()
      return mock_accessor
    end

    package.loaded["apps/reader/modules/readeractivityindicator"] = nil
    local ActiveIndicator = require("apps/reader/modules/readeractivityindicator")

    -- Case A: text_wrap == 1 starts indicator
    local inst = ActiveIndicator:new({
      document = {
        configurable = {
          text_wrap = 1,
        },
      },
    })

    assert.is_true(inst:onStartActivityIndicator())
    assert.is_true(inst.indicator_started)
    assert.are.equal(1, #lipc_calls)
    assert.are.equal("com.lab126.pillow", lipc_calls[1].domain)
    assert.are.equal("activityIndicator", lipc_calls[1].prop)
    assert.is_true(string.find(lipc_calls[1].val, '"action":"start"') ~= nil)

    assert.is_true(inst:onStopActivityIndicator())
    assert.is_false(inst.indicator_started)
    assert.are.equal(2, #lipc_calls)
    assert.are.equal("com.lab126.pillow", lipc_calls[2].domain)
    assert.are.equal("activityIndicator", lipc_calls[2].prop)
    assert.is_true(string.find(lipc_calls[2].val, '"action":"stop"') ~= nil)

    -- Calling stop again when indicator_started is false does not call lipc
    assert.is_true(inst:onStopActivityIndicator())
    assert.are.equal(2, #lipc_calls)

    -- Case B: text_wrap ~= 1 does not start indicator
    local inst_no_wrap = ActiveIndicator:new({
      document = {
        configurable = {
          text_wrap = 0,
        },
      },
    })

    assert.is_true(inst_no_wrap:onStartActivityIndicator())
    assert.is_nil(inst_no_wrap.indicator_started)
    assert.are.equal(2, #lipc_calls)
  end)
end)
