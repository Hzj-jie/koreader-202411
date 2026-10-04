describe("ConfirmBox multiple instances", function()
  local ConfirmBox, UIManager
  local open_boxes

  setup(function()
    require("commonrequire")
    ConfirmBox = require("ui/widget/confirmbox")
    UIManager = require("ui/uimanager")
  end)

  before_each(function()
    open_boxes = {}
  end)

  after_each(function()
    for _, box in ipairs(open_boxes) do
      if UIManager:isWindowWidget(box) then
        UIManager:close(box)
      end
    end
  end)

  it("allows multiple ConfirmBoxes shown at once", function()
    local a = ConfirmBox:new({ text = "first" })
    local b = ConfirmBox:new({ text = "second" })
    table.insert(open_boxes, a)
    table.insert(open_boxes, b)

    UIManager:show(a)
    UIManager:show(b)

    assert.is_true(UIManager:isWindowWidget(a))
    assert.is_true(UIManager:isWindowWidget(b))

    UIManager:close(b)
    UIManager:close(a)
    assert.is_false(UIManager:isWindowWidget(a))
    assert.is_false(UIManager:isWindowWidget(b))
  end)

  it("allows showing a ConfirmBox from another ConfirmBox ok_callback", function()
    local inner
    local outer = ConfirmBox:new({
      text = "outer",
      ok_callback = function()
        inner = ConfirmBox:new({ text = "inner" })
        table.insert(open_boxes, inner)
        UIManager:show(inner)
      end,
    })
    table.insert(open_boxes, outer)

    UIManager:show(outer)
    assert.is_true(UIManager:isWindowWidget(outer))

    local btn_table = outer[1][1][1][1][3]
    local ok_btn = btn_table.buttons[1][2]
    ok_btn.callback()

    assert.truthy(inner)
    assert.is_true(UIManager:isWindowWidget(inner))
    assert.is_false(UIManager:isWindowWidget(outer))

    UIManager:close(inner)
    assert.is_false(UIManager:isWindowWidget(inner))
  end)
end)
