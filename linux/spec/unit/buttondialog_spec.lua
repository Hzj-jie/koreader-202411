describe("ButtonDialog", function()
  local ButtonDialog
  local mock_device
  local UIManager
  local util = require("util")

  setup(function()
    require("commonrequire")

    mock_device = {
      hasKeys = function() return true end,
      isAndroid = function() return false end,
      isKindle = function() return false end,
      isTouchDevice = function() return true end,
      hasDPad = function() return false end,
      hasKeyboard = function() return false end,
      input = {
        group = {
          Dismiss = { "MockDismissKey" }
        }
      },
      screen = {
        getSize = function() return { w = 600, h = 800 } end,
        getWidth = function() return 600 end,
        getHeight = function() return 800 end,
        scaleBySize = function(self, v) return v end,
        scaleByDPI = function(self, v) return v end,
      }
    }
    package.loaded["device"] = mock_device

    UIManager = {
      setDirty = spy.new(function() end),
    }
    package.loaded["ui/uimanager"] = UIManager

    package.loaded["ui/widget/buttondialog"] = nil
    ButtonDialog = require("ui/widget/buttondialog")
  end)

  teardown(function()
    package.loaded["device"] = nil
    package.loaded["ui/uimanager"] = nil
  end)

  it("should map page buttons to Exit event when dismissable is true", function()
    local dialog = ButtonDialog:new({
      buttons = { { text = "Test", id = "test" } },
      dismissable = true,
    })

    local exit_keys = dialog.key_events.Exit[1][1]
    assert.truthy(exit_keys)

    assert.are.equal(mock_device.input.group.Dismiss, exit_keys)
  end)

  it("should NOT map page buttons to Exit event when dismissable is false", function()
    local dialog = ButtonDialog:new({
      buttons = { { text = "Test", id = "test" } },
      dismissable = false,
    })

    assert.is_nil(dialog.key_events.Exit)
  end)

  it("should be modal by default", function()
    local dialog = ButtonDialog:new({
      buttons = { { text = "Test", id = "test" } },
    })
    assert.is_true(dialog.modal)
  end)
end)
