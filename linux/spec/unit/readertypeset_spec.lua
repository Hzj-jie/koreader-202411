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
    local applied = false
    typeset:onSetPageHorizMargins({ 10, 10 }, function() applied = true end)
    local info_msg = UIManager:getTopmostVisibleWidget()
    if info_msg and info_msg.dismiss_callback then
      info_msg.dismiss_callback()
    end
    UIManager:close(info_msg)
    assert.is_true(applied)

    -- Top/bottom margin with sync enabled
    typeset.sync_t_b_page_margins = true
    typeset:onSetPageTopMargin(15)
    assert.are.equal(typeset.unscaled_margins[4], 15)
    typeset:onSetPageBottomMargin(18)
    assert.are.equal(typeset.unscaled_margins[2], 18)

    -- Top and bottom margins different
    typeset:onSetPageTopAndBottomMargin({ 20, 25 })
    assert.is_false(typeset.sync_t_b_page_margins)

    -- Top and bottom margins equal
    typeset:onSetPageTopAndBottomMargin({ 22, 22 })

    -- Sync margins toggle
    typeset.unscaled_margins = { 10, 10, 10, 20 }
    typeset:onSyncPageTopBottomMargins(true)
    assert.is_true(typeset.sync_t_b_page_margins)
    assert.are.equal(typeset.unscaled_margins[2], 15)
    assert.are.equal(typeset.unscaled_margins[4], 15)

    -- Sync margins toggle off
    typeset:onSyncPageTopBottomMargins(false)
    assert.is_false(typeset.sync_t_b_page_margins)

    -- Page margins with callback and reclaim_height
    typeset.view.footer.reclaim_height = true
    local callback_called = false
    typeset:onSetPageMargins({ 10, 20, 10, 20 }, function() callback_called = true end)
    local top_w = UIManager:getTopmostVisibleWidget()
    if top_w and top_w.dismiss_callback then
      top_w.dismiss_callback()
    end
    UIManager:close(top_w)
    assert.is_true(callback_called)

    typeset.view.footer.reclaim_height = false
    typeset:onSetPageMargins({ 10, 20, 10, 20 })

    -- Feature toggles
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

    -- Stylesheet menu generation and application
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

    -- FB2 mode
    readerui.document.is_fb2 = true
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

    typeset:setStyleSheet("data/epub.css")
    typeset:setStyleSheet("data/epub.css") -- no-op branch
    typeset:onApplyStyleSheet()

    -- Settings persistence
    typeset:onSaveSettings()
    typeset:onReadSettings(readerui.doc_settings)

    readerui:onExit()
    readerui:onClose()
  end)
end)
