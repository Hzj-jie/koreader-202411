describe("MultiInputDialog widget", function()
    local MultiInputDialog, InputText, InputDialog
    setup(function()
        require("commonrequire")
        MultiInputDialog = require("ui/widget/multiinputdialog")
        InputText = require("ui/widget/inputtext")
        InputDialog = require("ui/widget/inputdialog")
    end)

    it("should close all input fields when closed", function()
        local Event = require("ui/event")

        local calls = 0
        local original_onClose = InputText.onClose
        InputText.onClose = function(self)
            calls = calls + 1
            return original_onClose(self)
        end

        local dialog = MultiInputDialog:new({
            title = "Test",
            fields = {
                { text = "1" },
                { text = "2" },
                { text = "3" },
            },
        })

        dialog:broadcastEvent(Event:new("Show"))
        dialog:broadcastEvent(Event:new("Close"))

        -- 1 (measurement dummy) + 1 (discarded main dummy) + 3 (fields) = 5
        assert.are.equal(5, calls)

        InputText.onClose = original_onClose
    end)
end)
