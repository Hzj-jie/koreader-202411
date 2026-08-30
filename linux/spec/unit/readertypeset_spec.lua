describe("ReaderTypeset module", function()
  local ReaderTypeset, DocumentRegistry, ReaderUI, Screen, UIManager

  setup(function()
    require("commonrequire")
    ReaderTypeset = require("apps/reader/modules/readertypeset")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
    UIManager = require("ui/uimanager")
  end)

  local function createReaderUI()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    return ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })
  end

  after_each(function()
    while #UIManager._window_stack > 0 do
      local top = UIManager._window_stack[#UIManager._window_stack]
      UIManager:close(top.widget)
    end
    UIManager._dirty = {}
  end)

  it("should initialize typeset module and register to main menu", function()
    local readerui = createReaderUI()
    local typeset = readerui.typeset
    assert.is_table(typeset)

    local menu_items = {}
    typeset:addToMainMenu(menu_items)
    assert.is_table(menu_items.set_render_style)

    readerui:onExit()
    readerui:onClose()
  end)

  it("should handle horizontal and top/bottom page margin settings", function()
    local readerui = createReaderUI()
    local typeset = readerui.typeset

    local applied = false
    typeset:onSetPageHorizMargins({ 10, 10 }, function() applied = true end)
    local info_msg = UIManager:getTopmostVisibleWidget()
    if info_msg and info_msg.dismiss_callback then
      info_msg.dismiss_callback()
    end
    UIManager:close(info_msg)
    assert.is_true(applied)

    typeset.sync_t_b_page_margins = true
    typeset:onSetPageTopMargin(15)
    assert.are.equal(typeset.unscaled_margins[4], 15)
    typeset:onSetPageBottomMargin(18)
    assert.are.equal(typeset.unscaled_margins[2], 18)

    typeset:onSetPageTopAndBottomMargin({ 20, 25 })
    assert.is_false(typeset.sync_t_b_page_margins)

    typeset:onSetPageTopAndBottomMargin({ 22, 22 })

    readerui:onExit()
    readerui:onClose()
  end)

  it("should synchronize top and bottom page margins when toggled", function()
    local readerui = createReaderUI()
    local typeset = readerui.typeset

    typeset.unscaled_margins = { 10, 10, 10, 20 }
    typeset:onSyncPageTopBottomMargins(true)
    assert.is_true(typeset.sync_t_b_page_margins)
    assert.are.equal(typeset.unscaled_margins[2], 15)
    assert.are.equal(typeset.unscaled_margins[4], 15)

    typeset:onSyncPageTopBottomMargins(false)
    assert.is_false(typeset.sync_t_b_page_margins)

    readerui:onExit()
    readerui:onClose()
  end)

  it("should handle page margins with callback and reclaim_height", function()
    local readerui = createReaderUI()
    local typeset = readerui.typeset

    readerui.view.footer.reclaim_height = true
    local callback_called = false
    typeset:onSetPageMargins({ 10, 20, 10, 20 }, function() callback_called = true end)
    local top_w = UIManager:getTopmostVisibleWidget()
    if top_w and top_w.dismiss_callback then
      top_w.dismiss_callback()
    end
    UIManager:close(top_w)
    assert.is_true(callback_called)

    readerui.view.footer.reclaim_height = false
    typeset:onSetPageMargins({ 10, 20, 10, 20 })

    readerui:onExit()
    readerui:onClose()
  end)

  it("should toggle rendering and styling feature flags", function()
    local readerui = createReaderUI()
    local typeset = readerui.typeset

    typeset:onToggleEmbeddedStyleSheet(true)
    typeset:onToggleEmbeddedStyleSheet(false)
    typeset:onToggleEmbeddedFonts(true)
    typeset:onToggleEmbeddedFonts(false)
    typeset:onToggleImageScaling(true)
    typeset:onToggleImageScaling(false)
    typeset:onToggleNightmodeImages(true)
    typeset:onToggleNightmodeImages(false)
    typeset:onSetBlockRenderingMode(0)
    typeset:onSetBlockRenderingMode(1)
    typeset:onSetBlockRenderingMode(2)
    typeset:onSetBlockRenderingMode(3)
    typeset:onSetBlockRenderingMode(10)
    typeset:ensureSanerBlockRenderingFlags()
    typeset:onSetRenderDPI(96)
    typeset:onSetRenderDPI(120)

    readerui:onExit()
    readerui:onClose()
  end)

  it("should generate stylesheet menu and handle item callbacks", function()
    local readerui = createReaderUI()
    local typeset = readerui.typeset

    local sheet_menu = typeset:genStyleSheetMenu()
    assert.is_table(sheet_menu)

    local mock_menu = { updateItems = function() end }
    for _, item in ipairs(sheet_menu) do
      if item.text_func then item:text_func() end
      if item.checked_func then item:checked_func() end
      if item.enabled_func then item:enabled_func() end
      if item.callback then item:callback() end
      if item.hold_callback then
        item.hold_callback(mock_menu)
        local confirm = UIManager:getTopmostVisibleWidget()
        if confirm and confirm.ok_callback then
          confirm.ok_callback()
        end
        UIManager:close(confirm)
      end
      if item.sub_item_table then
        for _, sub in ipairs(item.sub_item_table) do
          if sub.text_func then sub:text_func() end
          if sub.checked_func then sub:checked_func() end
          if sub.enabled_func then sub:enabled_func() end
          if sub.callback then sub:callback() end
          if sub.hold_callback then
            sub.hold_callback(mock_menu)
            local confirm = UIManager:getTopmostVisibleWidget()
            if confirm and confirm.ok_callback then
              confirm.ok_callback()
            end
            UIManager:close(confirm)
          end
        end
      end
    end

    readerui:onExit()
    readerui:onClose()
  end)

  it("should generate stylesheet menu for FB2 documents", function()
    local readerui = createReaderUI()
    local typeset = readerui.typeset

    readerui.document.is_fb2 = true
    local mock_menu = { updateItems = function() end }
    local fb2_menu = typeset:genStyleSheetMenu()
    for _, item in ipairs(fb2_menu) do
      if item.text_func then item:text_func() end
      if item.checked_func then item:checked_func() end
      if item.enabled_func then item:enabled_func() end
      if item.hold_callback then
        item.hold_callback(mock_menu)
        local confirm = UIManager:getTopmostVisibleWidget()
        if confirm and confirm.ok_callback then
          confirm.ok_callback()
        end
        UIManager:close(confirm)
      end
    end
    readerui.document.is_fb2 = false

    readerui:onExit()
    readerui:onClose()
  end)

  it("should apply stylesheets and persist settings", function()
    local readerui = createReaderUI()
    local typeset = readerui.typeset

    typeset:setStyleSheet("data/epub.css")
    typeset:setStyleSheet("data/epub.css")
    typeset:onApplyStyleSheet()

    typeset:onSaveSettings()
    typeset:onReadSettings(readerui.doc_settings)

    readerui:onExit()
    readerui:onClose()
  end)
end)
