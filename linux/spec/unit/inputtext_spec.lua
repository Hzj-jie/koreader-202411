describe("InputText widget module", function()
    local InputText
    local equals
    setup(function()
        require("commonrequire")
        InputText = require("ui/widget/inputtext"):new{}

        equals = require("util").tableEquals
    end)

    describe("addChars()", function()
        it("should add regular text", function()
            InputText:initTextBox("")
            InputText:addChars("a")
            assert.is_true( equals({"a"}, InputText.charlist) )
            InputText:addChars("aa")
            assert.is_true( equals({"a", "a", "a"}, InputText.charlist) )
        end)
        it("should add unicode text", function()
            InputText:initTextBox("")
            InputText:addChars("Л")
            assert.is_true( equals({"Л"}, InputText.charlist) )
            InputText:addChars("Луа")
            assert.is_true( equals({"Л", "Л", "у", "а"}, InputText.charlist) )
        end)
        it("should assert when added_charlist contains nil", function()
            local util = require("util")
            local old_split = util.splitToChars
            local mock_called = false
            -- Mock splitToChars to inject a nil
            util.splitToChars = function(s)
                if s == "inject_nil" then
                    mock_called = true
                    return {"a", nil, "b", "c"}
                else
                    return old_split(s)
                end
            end
            
            InputText:initTextBox("")
            InputText.readonly = false
            assert.has_error(function()
                InputText:addChars("inject_nil")
            end)
            assert.is_true(mock_called)
            
            util.splitToChars = old_split
        end)
    end)

    describe("_setChar()", function()
        it("should write character at index", function()
            InputText.charlist = {"a"}
            InputText.charpos = 1
            InputText:_setChar(2, "b")
            assert.is_true( equals({"a", "b"}, InputText.charlist) )
        end)
        it("should pad gaps with spaces when writing past the end", function()
            InputText.charlist = {"a"}
            InputText.charpos = 1
            InputText:_setChar(5, "e")
            assert.is_true( equals({"a", " ", " ", " ", "e"}, InputText.charlist) )
        end)
    end)
end)
