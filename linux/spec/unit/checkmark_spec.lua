describe("CheckMark", function()
  local CheckMark
  local BD

  setup(function()
    require("commonrequire")
    CheckMark = require("ui/widget/checkmark")
    BD = require("ui/bidi")
  end)

  it("should initialize enabled and checked", function()
    local mark = CheckMark:new({
      checkable = true,
      checked = true,
      enabled = true,
    })

    assert.truthy(mark[1])
    assert.truthy(mark.baseline)
    assert.truthy(mark:getSize())
  end)

  it("should initialize enabled and unchecked", function()
    local mark = CheckMark:new({
      checkable = true,
      checked = false,
      enabled = true,
    })

    assert.truthy(mark[1])
  end)

  it("should initialize disabled checked and disabled unchecked", function()
    local mark_checked = CheckMark:new({
      checkable = true,
      checked = true,
      enabled = false,
    })
    assert.truthy(mark_checked[1])

    local mark_unchecked = CheckMark:new({
      checkable = true,
      checked = false,
      enabled = false,
    })
    assert.truthy(mark_unchecked[1])
  end)

  it("should handle checkable = false", function()
    local mark = CheckMark:new({
      checkable = false,
    })

    assert.truthy(mark[1])
  end)

  it("should support mirrored UI layout", function()
    local orig_mirrored = BD.mirroredUILayout
    BD.mirroredUILayout = function()
      return true
    end

    local mark = CheckMark:new({
      checkable = true,
      checked = true,
    })
    assert.truthy(mark[1])

    BD.mirroredUILayout = orig_mirrored
  end)
end)
