describe("ButtonProgressWidget", function()
  local ButtonProgressWidget

  setup(function()
    require("commonrequire")
    ButtonProgressWidget = require("ui/widget/buttonprogresswidget")
  end)

  it("should initialize with default progress segments", function()
    local last_val = nil
    local bpw = ButtonProgressWidget:new({
      num_buttons = 5,
      position = 2,
      callback = function(val)
        last_val = val
      end,
    })

    assert.are.equal(2, bpw.position)
    assert.are.equal(5, bpw.num_buttons)
    assert.truthy(bpw.dimen)

    -- Segment click
    local seg3 = bpw.buttonprogress_content[3]
    seg3.callback()
    assert.are.equal(3, last_val)
    assert.are.equal(3, bpw.position)
  end)

  it("should support fine_tune (- and + buttons) and more_options (⋮)", function()
    local last_op = nil
    local last_hold = nil
    local bpw = ButtonProgressWidget:new({
      num_buttons = 4,
      position = 2,
      fine_tune = true,
      more_options = true,
      callback = function(op)
        last_op = op
      end,
      hold_callback = function(op)
        last_hold = op
      end,
    })

    -- Layout structure:
    -- [1] Minus button
    -- [2] Span
    -- [3..6] Segments
    -- [7] Span
    -- [8] Plus button
    -- [9] Span
    -- [10] More options button
    local minus_btn = bpw.buttonprogress_content[1]
    assert.are.equal("−", minus_btn.text)
    minus_btn.callback()
    assert.are.equal("-", last_op)
    minus_btn.hold_callback()
    assert.are.equal("-", last_hold)

    local plus_btn = bpw.buttonprogress_content[8]
    assert.are.equal("＋", plus_btn.text)
    plus_btn.callback()
    assert.are.equal("+", last_op)
    plus_btn.hold_callback()
    assert.are.equal("+", last_hold)

    local more_btn = bpw.buttonprogress_content[10]
    assert.are.equal("⋮", more_btn.text)
    more_btn.callback()
    assert.are.equal("⋮", last_op)
    more_btn.hold_callback()
    assert.are.equal("⋮", last_hold)
  end)

  it("should support thin_grey_style and default_position", function()
    local bpw = ButtonProgressWidget:new({
      num_buttons = 3,
      position = 1,
      default_position = 2,
      thin_grey_style = true,
      callback = function() end,
    })

    assert.is_true(bpw.thin_grey_style)
    assert.truthy(bpw.buttonprogress_content)
  end)

  it("should support setPosition and circlePosition", function()
    local last_pos = nil
    local bpw = ButtonProgressWidget:new({
      num_buttons = 3,
      position = 1,
      callback = function(pos)
        last_pos = pos
      end,
    })

    bpw:setPosition(3, 1)
    assert.are.equal(3, bpw.position)
    assert.are.equal(1, bpw.default_position)

    -- circlePosition wraps from 3 to 1
    bpw:circlePosition()
    assert.are.equal(1, bpw.position)
    assert.are.equal(1, last_pos)

    -- onTapSelect with nil gev triggers circlePosition
    bpw:onTapSelect(nil, nil)
    assert.are.equal(2, bpw.position)
  end)
end)
