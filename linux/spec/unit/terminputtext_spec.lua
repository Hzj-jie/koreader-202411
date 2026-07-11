describe("TermInputText widget module", function()
    local TermInputText
    local equals
    setup(function()
        require("commonrequire")
        TermInputText = require("plugins/terminal.koplugin/terminputtext")
        equals = require("util").tableEquals
    end)

    describe("wrapping logic", function()
        it("should wrap text properly without extra newlines or spaces", function()
            local term = TermInputText:new{
                maxc = 10,
                maxr = 3,
                wrap = true,
            }
            -- 10 columns, 3 rows.
            -- Write 9 chars -> stays on row 1
            term:addChars("123456789")
            assert.is_true(equals({"1","2","3","4","5","6","7","8","9"}, term.charlist))
            
            -- Write 1 more -> 10 chars, fits row 1
            term:addChars("0")
            assert.is_true(equals({"1","2","3","4","5","6","7","8","9","0"}, term.charlist))
            
            -- Write 1 more -> 11th char, should wrap to row 2!
            term:addChars("a")
            local expected = {"1","2","3","4","5","6","7","8","9","0","\n","a"," "," "," "," "," "," "," "," "," ","\n"}
            assert.is_true(equals(expected, term.charlist))
            
            -- Now write "b". Since "a" was at 12, "b" should go to 13 (no wrap!).
            term:addChars("b")
            expected[13] = "b"
            assert.is_true(equals(expected, term.charlist))
        end)
    end)
end)
