describe("PhysicalButtons element", function()
  local PhysicalButtons, Device, UIManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Device = require("device")
    UIManager = require("ui/uimanager")
    UIManager.askForRestartOrReload = function() end

    PhysicalButtons = require("ui/elements/physical_buttons")
  end)

  it("should expose PhysicalButtons menu structure", function()
    assert.is_table(PhysicalButtons)
    assert.is_table(PhysicalButtons.sub_item_table)
    assert.is_true(#PhysicalButtons.sub_item_table >= 1)
  end)

  it("should handle invert page turn buttons callback", function()
    local item = PhysicalButtons.sub_item_table[1]
    assert.is_boolean(item.enabled_func())
    assert.is_boolean(item.checked_func())

    item.callback()
  end)

  it(
    "should include DPad and key repeat items when supported by device",
    function()
      local old_hasDPad = Device.hasDPad
      local old_useDPad = Device.useDPadAsActionKeys
      local old_canKeyRepeat = Device.canKeyRepeat

      Device.hasDPad = function()
        return true
      end
      Device.useDPadAsActionKeys = function()
        return true
      end
      Device.canKeyRepeat = function()
        return true
      end

      package.loaded["ui/elements/physical_buttons"] = nil
      local PhysicalButtonsDPad = require("ui/elements/physical_buttons")

      assert.is_table(PhysicalButtonsDPad.sub_item_table)
      assert.is_true(#PhysicalButtonsDPad.sub_item_table >= 4)

      Device.hasDPad = old_hasDPad
      Device.useDPadAsActionKeys = old_useDPad
      Device.canKeyRepeat = old_canKeyRepeat
    end
  )
end)
