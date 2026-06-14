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
            getAddedWidgetAvailableWidth = function() return 200 end,
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
end)
