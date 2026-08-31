describe("menu table screen color module", function()
  local menu, Screen, CanvasContext
  setup(function()
    require("commonrequire")
    menu = dofile("frontend/ui/elements/screen_color_menu_table.lua")
    Screen = require("device").screen
    CanvasContext = require("document/canvascontext")
  end)

  it("should toggle color rendering", function()
    assert.is.truthy(Screen.isColorEnabled())
    assert.is.truthy(CanvasContext.is_color_rendering_enabled)
    menu.callback()
    assert.is.falsy(Screen.isColorEnabled())
    assert.is.falsy(CanvasContext.is_color_rendering_enabled)
    menu.callback()
    assert.is.truthy(Screen.isColorEnabled())
    assert.is_truthy(CanvasContext.is_color_rendering_enabled)
  end)

  it("should trigger askForRestart on color Kobo devices", function()
    local Device = require("device")
    local UIManager = require("ui/uimanager")
    local stub = require("luassert.stub")

    local kobo_stub = stub(Device, "isKobo", function() return true end)
    local color_stub = stub(Device, "hasColorScreen", function() return true end)
    local restart_asked = false
    local restart_stub = stub(UIManager, "askForRestart", function() restart_asked = true end)

    menu.callback()
    assert.is_true(restart_asked)

    kobo_stub:revert()
    color_stub:revert()
    restart_stub:revert()
  end)
end)
