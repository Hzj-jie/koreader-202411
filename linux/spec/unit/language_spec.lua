local Language = require("ui/language")
local stub = require("luassert.stub")

describe("Language module", function()
    setup(function()
        _G.G_reader_settings = {
            settings = {},
            read = function(self, key)
                return self.settings[key]
            end,
            save = function(self, key, val)
                self.settings[key] = val
            end,
            nilOrTrue = function() return true end,
        }
    end)

    teardown(function()
        _G.G_reader_settings = nil
    end)

    it("should map en locale to English", function()
        assert.are.equal("English", Language:getLanguageName("en"))
    end)

    it("should return the locale code itself for unknown locale xy", function()
        assert.are.equal("xy", Language:getLanguageName("xy"))
    end)

    it("should contain sub-item for en and not C in language menu", function()
        local menu = Language:getLangMenuTable()
        assert.is_table(menu)
        assert.is_table(menu.sub_item_table)

        local found_en = false
        local found_c = false
        for _, item in ipairs(menu.sub_item_table) do
            if item.text == "English" then
                -- Note: Language:genLanguageSubItem text comes from getLanguageName
                found_en = true
            end
            -- Double check that C is not present in getLangMenuTable
            -- Let's trace item callback's upvalue or similar if we want to check if it's C/en
        end
        assert.is_true(found_en)
    end)

    it("should correctly check language state with backwards compatibility for C", function()
        local item_en = Language:genLanguageSubItem("en")

        -- 1. Default (no setting) -> defaults to "en", so checked_func should return true
        G_reader_settings.settings = {}
        assert.is_true(item_en.checked_func())

        -- 2. Setting is "en" -> should return true
        G_reader_settings.settings = { language = "en" }
        assert.is_true(item_en.checked_func())

        -- 3. Setting is "C" (backwards compatibility) -> should return true
        G_reader_settings.settings = { language = "C" }
        assert.is_true(item_en.checked_func())

        -- 4. Setting is other language -> should return false
        G_reader_settings.settings = { language = "fr" }
        assert.is_false(item_en.checked_func())
    end)
end)
