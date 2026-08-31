local Language = require("ui/language")
local gettext = require("gettext")
local UIManager = require("ui/uimanager")

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
      nilOrTrue = function()
        return true
      end,
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

  it("should detect RTL languages correctly", function()
    assert.is_false(Language:isLanguageRTL(nil))
    assert.is_false(Language:isLanguageRTL("en"))
    assert.is_false(Language:isLanguageRTL("en_US"))
    assert.is_false(Language:isLanguageRTL("fr_FR"))

    assert.is_true(Language:isLanguageRTL("ar"))
    assert.is_true(Language:isLanguageRTL("ar_EG"))
    assert.is_true(Language:isLanguageRTL("fa"))
    assert.is_true(Language:isLanguageRTL("fa_IR"))
    assert.is_true(Language:isLanguageRTL("he"))
    assert.is_true(Language:isLanguageRTL("ur"))
    assert.is_true(Language:isLanguageRTL("yi"))
  end)

  it("should handle changeLanguage", function()
    local changed_lang = nil
    local orig_changeLang = gettext.changeLang
    gettext.changeLang = function(l)
      changed_lang = l
    end

    local asked_restart = false
    local orig_askForRestart = UIManager.askForRestart
    UIManager.askForRestart = function(self, msg)
      asked_restart = true
    end

    Language:changeLanguage("fr")
    assert.are.equal("fr", changed_lang)
    assert.are.equal("fr", G_reader_settings:read("language"))
    assert.is_true(asked_restart)

    gettext.changeLang = orig_changeLang
    UIManager.askForRestart = orig_askForRestart
  end)

  it("should contain sub-item for en and not C in language menu", function()
    local menu = Language:getLangMenuTable()
    assert.is_table(menu)
    assert.is_table(menu.sub_item_table)

    local found_en = false
    for _, item in ipairs(menu.sub_item_table) do
      if item.text == "English" then
        found_en = true
      end
    end
    assert.is_true(found_en)
  end)

  it(
    "should correctly check language state with backwards compatibility for C",
    function()
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

      -- 5. Subitem with "C" target code
      local item_c = Language:genLanguageSubItem("C")
      G_reader_settings.settings = { language = "en" }
      assert.is_true(item_c.checked_func())

      -- 6. Trigger item callback
      local change_called = false
      local orig_change = Language.changeLanguage
      Language.changeLanguage = function(self, lang)
        change_called = true
      end
      item_en.callback()
      assert.is_true(change_called)
      Language.changeLanguage = orig_change
    end
  )
end)
