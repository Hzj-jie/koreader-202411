describe("IconButton", function()
  local IconButton
  local UIManager

  local orig_setDirty
  local orig_invertWidget
  local orig_forceRepaint
  local orig_waitForScreenRefresh

  setup(function()
    require("commonrequire")
    IconButton = require("ui/widget/iconbutton")
    UIManager = require("ui/uimanager")

    orig_setDirty = UIManager.setDirty
    orig_invertWidget = UIManager.invertWidget
    orig_forceRepaint = UIManager.forceRepaint
    orig_waitForScreenRefresh = UIManager.waitForScreenRefresh
  end)

  before_each(function()
    UIManager.setDirty = function() end
    UIManager.invertWidget = function() end
    UIManager.forceRepaint = function() end
    UIManager.waitForScreenRefresh = function() end
  end)

  after_each(function()
    UIManager.setDirty = orig_setDirty
    UIManager.invertWidget = orig_invertWidget
    UIManager.forceRepaint = orig_forceRepaint
    UIManager.waitForScreenRefresh = orig_waitForScreenRefresh
  end)

  it("should initialize with custom padding and icon", function()
    local btn = IconButton:new({
      icon = "appbar.menu",
      padding = 5,
      padding_top = 8,
      padding_bottom = 4,
    })

    assert.truthy(btn.image)
    assert.truthy(btn.dimen)
    assert.are.equal(8, btn.padding_top)
    assert.are.equal(4, btn.padding_bottom)
    assert.are.equal(5, btn.padding_left)
    assert.are.equal(5, btn.padding_right)
  end)

  it("should handle tap callbacks and highlight cycle", function()
    local tapped = false
    local btn = IconButton:new({
      icon = "appbar.menu",
      callback = function()
        tapped = true
      end,
    })

    assert.is_true(btn:onTapIconButton())
    assert.is_true(tapped)

    -- onTapSelect delegates to onTapIconButton
    tapped = false
    btn:onTapSelect()
    assert.is_true(tapped)
  end)

  it("should handle hold callbacks and input triggers", function()
    local held = false
    local btn = IconButton:new({
      icon = "appbar.menu",
      hold_callback = function()
        held = true
      end,
    })

    assert.is_true(btn:onHoldIconButton())
    assert.is_true(held)
    assert.is_true(btn:onHoldReleaseIconButton())
    assert.is_false(btn:onHoldReleaseIconButton())

    -- hold_input option
    local input_arg = nil
    local btn_input = IconButton:new({
      icon = "appbar.menu",
      hold_input = { title = "Input Title" },
    })
    btn_input.onInput = function(self, arg)
      input_arg = arg
    end
    assert.is_true(btn_input:onHoldIconButton())
    assert.truthy(input_arg)

    -- hold_input_func option
    input_arg = nil
    local btn_func = IconButton:new({
      icon = "appbar.menu",
      hold_input_func = function()
        return { title = "Func Title" }
      end,
    })
    btn_func.onInput = function(self, arg)
      input_arg = arg
    end
    assert.is_true(btn_func:onHoldIconButton())
    assert.truthy(input_arg)
  end)

  it("should handle onFocus and onUnfocus", function()
    local btn = IconButton:new({
      icon = "appbar.menu",
    })

    assert.is_true(btn:onFocus())
    assert.is_true(btn.image.invert)

    assert.is_true(btn:onUnfocus())
    assert.is_false(btn.image.invert)
  end)

  it("should update icon with setIcon", function()
    local btn = IconButton:new({
      icon = "appbar.menu",
    })

    btn:setIcon("search")
    assert.are.equal("search", btn.icon)
  end)
end)
