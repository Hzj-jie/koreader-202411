describe("ReaderTypography module", function()
  local ReaderTypography, DocumentRegistry, ReaderUI, Screen, UIManager

  setup(function()
    require("commonrequire")
    ReaderTypography = require("apps/reader/modules/readertypography")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
    UIManager = require("ui/uimanager")
  end)

  it(
    "should initialize ReaderTypography class and fix language tags",
    function()
      assert.is_table(ReaderTypography)
      assert.is_nil(ReaderTypography:fixLangTag(""))
      assert.is_nil(ReaderTypography:fixLangTag(nil))
      assert.are.equal("en-US", ReaderTypography:fixLangTag("en-US"))
      assert.are.equal("en-US", ReaderTypography:fixLangTag("eng"))
      assert.are.equal("fr", ReaderTypography:fixLangTag("fre"))
      assert.are.equal("zh-CN", ReaderTypography:fixLangTag("zh-Hans"))
      assert.are.equal("custom-xyz", ReaderTypography:fixLangTag("custom-xyz"))
    end
  )

  it(
    "should handle typography settings, menu, and floating punctuation",
    function()
      local sample_epub = "spec/front/unit/data/leaves.epub"
      local readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_epub),
      })

      local typo = readerui.typography
      assert.is_table(typo)

      local menu_items = {}
      typo:addToMainMenu(menu_items)
      assert.is_table(menu_items.typography)
      assert.is_string(menu_items.typography.text_func())

      -- Floating punctuation toggles
      typo:onToggleFloatingPunctuation(true)
      typo:onToggleFloatingPunctuation(false)
      typo:onToggleFloatingPunctuation(1)

      -- Make default floating punctuation
      local shown_widget
      local orig_show = UIManager.show
      UIManager.show = function(self, w)
        shown_widget = w
      end

      typo:makeDefaultFloatingPunctuation()
      assert.is_not_nil(shown_widget)
      if shown_widget.choice1_callback then
        shown_widget.choice1_callback()
      end
      if shown_widget.choice2_callback then
        shown_widget.choice2_callback()
      end
      UIManager.show = orig_show

      -- Default hyph dict language
      local hyph_lang = typo:getCurrentDefaultHyphDictLanguage()
      assert.is_string(hyph_lang)

      -- Settings persistence
      typo:onSaveSettings()
      typo:onReadSettings(readerui.doc_settings)

      readerui:onExit()
      readerui:onClose()
    end
  )

  it("should exercise all menu items, submenus, and dialog callbacks", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local typo = readerui.typography
    local dummy_menu = {
      updateItems = function() end,
    }

    local function walkMenu(items)
      for _, item in ipairs(items) do
        if item.text_func then pcall(item.text_func) end
        if item.checked_func then pcall(item.checked_func) end
        if item.enabled_func then pcall(item.enabled_func) end
        if item.callback then
          pcall(item.callback, dummy_menu)
          while #UIManager._window_stack > 0 do
            local top = UIManager._window_stack[#UIManager._window_stack].widget
            if top and top ~= readerui then
              if top.callback then pcall(top.callback, 2, 2) end
              UIManager:close(top)
            else
              break
            end
          end
        end
        if item.hold_callback then
          pcall(item.hold_callback, dummy_menu)
          while #UIManager._window_stack > 0 do
            local top = UIManager._window_stack[#UIManager._window_stack].widget
            if top and top ~= readerui then
              if top.choice1_callback then pcall(top.choice1_callback) end
              if top.choice2_callback then pcall(top.choice2_callback) end
              if top.choice1_text_func then pcall(top.choice1_text_func) end
              if top.choice2_text_func then pcall(top.choice2_text_func) end
              UIManager:close(top)
            else
              break
            end
          end
        end
        if item.sub_item_table then
          walkMenu(item.sub_item_table)
        end
      end
    end

    walkMenu(typo.menu_table)

    readerui:onExit()
    readerui:onClose()
  end)

  it("should exercise onReadSettings migration and fallback branches", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local typo = readerui.typography

    -- Test hyph_alg migrations
    local dummy_config = {
      _data = {
        hyph_alg = "@none",
      },
      has = function(self, k) return self._data[k] ~= nil end,
      hasNot = function(self, k) return self._data[k] == nil end,
      read = function(self, k) return self._data[k] end,
      save = function(self, k, v) self._data[k] = v end,
      makeFalse = function(self, k) self._data[k] = false end,
      makeTrue = function(self, k) self._data[k] = true end,
      isTrue = function(self, k) return self._data[k] == true end,
      nilOrTrue = function(self, k) return self._data[k] ~= false end,
    }
    typo:onReadSettings(dummy_config)
    assert.are.equal("en", dummy_config:read("text_lang"))

    dummy_config._data = { hyph_alg = "@softhyphens" }
    typo:onReadSettings(dummy_config)
    assert.is_true(dummy_config:read("hyph_soft_hyphens_only"))

    dummy_config._data = { hyph_alg = "@algorithm" }
    typo:onReadSettings(dummy_config)
    assert.is_true(dummy_config:read("hyph_force_algorithmic"))

    -- Test text_lang_default and text_lang_fallback
    dummy_config._data = {}
    G_reader_settings:save("text_lang_default", "fr")
    typo:onReadSettings(dummy_config)
    assert.are.equal("fr", typo.text_lang_tag)
    G_reader_settings:delete("text_lang_default")

    dummy_config._data = {}
    G_reader_settings:save("text_lang_fallback", "de")
    typo:onReadSettings(dummy_config)
    assert.are.equal("de", typo.text_lang_tag)
    G_reader_settings:delete("text_lang_fallback")


    -- Test onPreRenderDocument branches
    typo.allow_doc_lang_tag_override = true
    typo.book_lang_tag = nil
    typo:onPreRenderDocument(dummy_config)

    typo.allow_doc_lang_tag_override = false
    typo.book_lang_tag = "en-US"
    typo:onPreRenderDocument(dummy_config)

    typo.allow_doc_lang_tag_override = true
    typo.book_lang_tag = "en-US"
    typo.text_lang_tag = "fr"
    typo:onPreRenderDocument(dummy_config)
    assert.are.equal("en-US", typo.text_lang_tag)

    -- Test book language menu item callback in language_submenu
    if typo.language_submenu[1] and typo.language_submenu[1].callback then
      typo.language_submenu[1].callback()
      local top = UIManager._window_stack[#UIManager._window_stack].widget
      if top and top ~= readerui then
        UIManager:close(top)
      end
    end

    readerui:onExit()
    readerui:onClose()
  end)
end)

