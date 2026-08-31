describe("ToggleSwitch module", function()
  local ToggleSwitch
  local UIManager
  local BD
  local Geom

  setup(function()
    require("commonrequire")
    ToggleSwitch = require("ui/widget/toggleswitch")
    UIManager = require("ui/uimanager")
    BD = require("ui/bidi")
    Geom = require("ui/geometry")
  end)

  it("should toggle without args", function()
    local orig_setDirty = UIManager.setDirty
    UIManager.setDirty = function() end

    local config = {
      onConfigChoose = function() end,
    }

    local switch = ToggleSwitch:new({
      event = "ChangeSpec",
      default_value = 2,
      toggle = { "Finished", "Reading", "On hold" },
      values = { 1, 2, 3 },
      name = "spec_status",
      alternate = false,
      enabled = true,
      config = config,
    })
    switch:togglePosition(1, true)
    switch:onTapSelect()

    UIManager.setDirty = orig_setDirty
  end)

  it("should handle setPosition and update cell colors", function()
    local switch = ToggleSwitch:new({
      toggle = { "Opt1", "Opt2" },
      values = { 1, 2 },
      name = "test_opt",
    })

    switch:setPosition(1)
    assert.are.equal(1, switch.position)

    switch:setPosition(2)
    assert.are.equal(2, switch.position)
  end)

  it("should handle dual-state alternating togglePosition and single-state toggle", function()
    local switch_dual = ToggleSwitch:new({
      toggle = { "Off", "On" },
      values = { 0, 1 },
      alternate = true,
    })
    switch_dual.position = 1
    switch_dual:togglePosition(1, true)
    assert.are.equal(2, switch_dual.position)
    switch_dual:togglePosition(2, true)
    assert.are.equal(1, switch_dual.position)

    local switch_single = ToggleSwitch:new({
      toggle = { "Solo" },
      values = { 1 },
    })
    switch_single.position = 1
    switch_single:togglePosition(1, true)
    assert.are.equal(0, switch_single.position)
    switch_single:togglePosition(0, true)
    assert.are.equal(1, switch_single.position)
  end)

  it("should circlePosition through positions", function()
    local switch = ToggleSwitch:new({
      toggle = { "A", "B", "C" },
      values = { 1, 2, 3 },
    })
    switch.position = 1
    switch:circlePosition()
    assert.are.equal(2, switch.position)
    switch:circlePosition()
    assert.are.equal(3, switch.position)
    switch:circlePosition()
    assert.are.equal(1, switch.position)
  end)

  it("should calculate position accurately for LTR and RTL layouts", function()
    local switch = ToggleSwitch:new({
      toggle = { "Left", "Mid", "Right" },
      values = { 1, 2, 3 },
      width = 300,
      height = 50,
    })
    switch:getSize().x = 0
    switch:getSize().y = 0
    switch:getSize().w = 300
    switch:getSize().h = 50

    local gev_left = { pos = Geom:new({ x = 50, y = 25 }) }
    local gev_mid = { pos = Geom:new({ x = 150, y = 25 }) }
    local gev_right = { pos = Geom:new({ x = 250, y = 25 }) }

    assert.are.equal(1, switch:calculatePosition(gev_left))
    assert.are.equal(2, switch:calculatePosition(gev_mid))
    assert.are.equal(3, switch:calculatePosition(gev_right))

    -- RTL mirroring
    local orig_mirrored = BD.mirroredUILayout
    BD.mirroredUILayout = function() return true end

    assert.are.equal(3, switch:calculatePosition(gev_left))
    assert.are.equal(1, switch:calculatePosition(gev_right))

    BD.mirroredUILayout = orig_mirrored
  end)

  it("should handle onTapSelect with gesture event and more button '⋮'", function()
    local chosen_val = nil
    local config = {
      onConfigChoose = function(self, values, name, event, args, position, hide)
        chosen_val = values and values[position]
      end,
    }

    local callback_pos = nil
    local switch = ToggleSwitch:new({
      toggle = { "A", "B", "⋮" },
      values = { 10, 20, 30 },
      name = "choice_opt",
      config = config,
      width = 300,
      callback = function(p)
        callback_pos = p
      end,
    })
    switch:getSize().x = 0
    switch:getSize().y = 0
    switch:getSize().w = 300
    switch:getSize().h = 50

    local orig_setDirty = UIManager.setDirty
    UIManager.setDirty = function() end

    -- Tap on option B (x = 150)
    switch:onTapSelect(nil, { pos = Geom:new({ x = 150, y = 25 }) })
    assert.are.equal(2, switch.position)
    assert.are.equal(2, callback_pos)
    assert.are.equal(20, chosen_val)

    -- Tap on option ⋮ (x = 280)
    chosen_val = nil
    switch:onTapSelect(nil, { pos = Geom:new({ x = 280, y = 25 }) })
    assert.are.equal(3, switch.position)
    assert.is_nil(chosen_val) -- did not call onConfigChoose because of ⋮

    -- Disabled switch
    switch.enabled = false
    switch.readonly = true
    assert.is_nil(switch:onTapSelect())

    switch.readonly = false
    assert.is_true(switch:onTapSelect())

    UIManager.setDirty = orig_setDirty
  end)

  it("should handle onHoldSelect for normal options and font_fine_tune", function()
    local default_set = nil
    local fine_tune_set = nil
    local config = {
      onMakeDefault = function(self, name, text, values, toggle, pos)
        default_set = { name = name, pos = pos }
      end,
      onMakeFineTuneDefault = function(self, name, text, values, toggle, sign)
        fine_tune_set = { name = name, sign = sign }
      end,
    }

    local switch = ToggleSwitch:new({
      toggle = { "Low", "High" },
      values = { 1, 2 },
      name = "speed",
      name_text = "Speed",
      config = config,
      width = 200,
      height = 50,
    })
    switch:getSize().x = 0
    switch:getSize().y = 0
    switch:getSize().w = 200
    switch:getSize().h = 50

    switch:onHoldSelect(nil, { pos = Geom:new({ x = 50, y = 25 }) })
    assert.truthy(default_set)
    assert.are.equal("speed", default_set.name)
    assert.are.equal(1, default_set.pos)

    -- font_fine_tune
    local switch_ft = ToggleSwitch:new({
      toggle = { "-", "+" },
      args = { -0.5, 0.5 },
      name = "font_fine_tune",
      config = config,
      width = 200,
      height = 50,
    })
    switch_ft:getSize().x = 0
    switch_ft:getSize().y = 0
    switch_ft:getSize().w = 200
    switch_ft:getSize().h = 50

    switch_ft:onHoldSelect(nil, { pos = Geom:new({ x = 150, y = 25 }) })
    assert.truthy(fine_tune_set)
    assert.are.equal("font_size", fine_tune_set.name)
    assert.are.equal("+", fine_tune_set.sign)
  end)
end)
