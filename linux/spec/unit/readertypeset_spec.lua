describe("ReaderTypeset module", function()
  local ReaderTypeset, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderTypeset = require("apps/reader/modules/readertypeset")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize typeset module and handle settings", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local typeset = readerui.typeset
    assert.is_table(typeset)

    local menu_items = {}
    typeset:addToMainMenu(menu_items)
    assert.is_table(menu_items.set_render_style)

    -- Margin setters
    typeset:onSetPageHorizMargins({ 10, 10 })
    typeset:onSetPageTopMargin(15)
    typeset:onSetPageBottomMargin(15)
    typeset:onSetPageTopAndBottomMargin({ 20, 20 })
    typeset:onSyncPageTopBottomMargins(true)
    typeset:onSetPageMargins({ 10, 20, 10, 20 })

    -- Feature toggles
    typeset:onToggleEmbeddedStyleSheet(true)
    typeset:onToggleEmbeddedFonts(true)
    typeset:onToggleImageScaling(true)
    typeset:onToggleNightmodeImages(true)
    typeset:onSetBlockRenderingMode(0)
    typeset:onSetRenderDPI(96)

    -- Stylesheet menu generation and application
    local sheet_menu = typeset:genStyleSheetMenu()
    assert.is_table(sheet_menu)
    typeset:onApplyStyleSheet()

    -- Settings persistence
    typeset:onSaveSettings()
    typeset:onReadSettings(readerui.doc_settings)

    readerui:onExit()
    readerui:onClose()
  end)
end)
