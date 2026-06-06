describe("InputDialog widget", function()
    local InputDialog
    setup(function()
        require("commonrequire")
        InputDialog = require("ui/widget/inputdialog")
    end)

    it("should not crash when initialized with empty buttons table and save_callback", function()
        local dialog
        assert.has_no.errors(function()
            dialog = InputDialog:new({
                title = "Test",
                save_callback = function() end,
                buttons = {},
            })
        end)
        assert.is_not_nil(dialog)
    end)

    it("should not crash when initialized with empty buttons table and add_scroll_buttons=true", function()
        local dialog
        assert.has_no.errors(function()
            dialog = InputDialog:new({
                title = "Test",
                add_scroll_buttons = true,
                buttons = {},
            })
        end)
        assert.is_not_nil(dialog)
    end)

    it("should set and get input text correctly", function()
        local dialog = InputDialog:new({
            title = "Test",
            input = "initial text",
        })

        assert.is.same("initial text", dialog:getInputText())

        dialog:setInputText("new text")
        assert.is.same("new text", dialog:getInputText())
    end)
end)
