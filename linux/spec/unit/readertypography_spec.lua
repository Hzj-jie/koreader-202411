describe("ReaderTypography module", function()
  local ReaderTypography, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderTypography = require("apps/reader/modules/readertypography")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it(
    "should initialize ReaderTypography class and fix language tags",
    function()
      assert.is_table(ReaderTypography)
      assert.is_nil(ReaderTypography:fixLangTag(""))
      assert.is_nil(ReaderTypography:fixLangTag(nil))
      assert.are.equal("en-US", ReaderTypography:fixLangTag("en-US"))
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
      local UIManager = require("ui/uimanager")
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
end)
