describe("ReaderActivityIndicator module", function()
  local ReaderActivityIndicator, Device

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Device = require("device")
  end)

  it("should return stub implementation on non-Kindle devices", function()
    local ReaderActivityIndicatorStub =
      require("apps/reader/modules/readeractivityindicator")
    assert.is_table(ReaderActivityIndicatorStub)
    assert.is_true(ReaderActivityIndicatorStub:isStub())

    ReaderActivityIndicatorStub:onStartActivityIndicator()
    ReaderActivityIndicatorStub:onStopActivityIndicator()
  end)

  it("should initialize active activity indicator on Kindle devices", function()
    local old_isKindle = Device.isKindle
    local old_isTouch = Device.isTouchDevice

    Device.isKindle = function()
      return true
    end
    Device.isTouchDevice = function()
      return true
    end

    package.loaded["apps/reader/modules/readeractivityindicator"] = nil
    local ActiveIndicator =
      require("apps/reader/modules/readeractivityindicator")

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
    assert.is_true(inst:onStopActivityIndicator())

    Device.isKindle = old_isKindle
    Device.isTouchDevice = old_isTouch
  end)
end)
