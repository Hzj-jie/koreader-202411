describe("CheckButton widget", function()
  local CheckButton, Font, Blitbuffer
  setup(function()
    require("commonrequire")
    CheckButton = require("ui/widget/checkbutton")
    Font = require("ui/font")
    Blitbuffer = require("ffi/blitbuffer")
  end)

  it("should preserve checked state when disabled and re-enabled", function()
    local mock_parent = {
      getAddedWidgetAvailableWidth = function()
        return 200
      end,
    }

    local UIManager = require("ui/uimanager")
    local original_setDirty = UIManager.setDirty
    UIManager.setDirty = function() end

    local cb = CheckButton:new({
      text = "Test CheckBox",
      checked = true,
      parent = mock_parent,
    })

    assert.is_true(cb.checked)

    -- Disable it
    cb:disable()

    -- It should STILL be checked!
    assert.is_true(cb.checked)

    -- Re-enable it
    cb:enable()

    -- It should still be checked
    assert.is_true(cb.checked)

    UIManager.setDirty = original_setDirty
  end)

  it(
    "should calculate size via getSize and support geometry merge methods",
    function()
      local mock_parent = {
        getAddedWidgetAvailableWidth = function()
          return 200
        end,
      }

      local cb = CheckButton:new({
        text = "Geometry CheckBox",
        parent = mock_parent,
        width = 150,
        height = 40,
      })

      local size = cb:getSize()
      assert.is_not_nil(size)
      assert.is_true(size.w > 0)
      assert.is_true(size.h > 0)

      cb:mergeSize(180, 60)
      local new_size = cb:getSize()
      assert.are.equal(180, new_size.w)
      assert.are.equal(60, new_size.h)
    end
  )

  it("should support mergePosition and dirtyRegion", function()
    local mock_parent = {
      getAddedWidgetAvailableWidth = function()
        return 200
      end,
    }

    local cb = CheckButton:new({
      text = "Position CheckBox",
      parent = mock_parent,
    })

    cb:mergePosition(15, 25)
    local pos_size = cb:getSize()
    assert.are.equal(15, pos_size.x)
    assert.are.equal(25, pos_size.y)

    local region = cb:dirtyRegion()
    assert.is_not_nil(region)
  end)
end)
