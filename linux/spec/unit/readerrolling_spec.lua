describe("Readerrolling module", function()
  local DocumentRegistry, UIManager, ReaderUI, Event, Screen
  local readerui, rolling

  setup(function()
    require("commonrequire")
    local plugins_disabled = G_reader_settings:readTableRef("plugins_disabled")
      or {}
    plugins_disabled.statistics = true
    G_reader_settings:save("plugins_disabled", plugins_disabled)
    local PluginLoader = require("pluginloader")
    PluginLoader.enabled_plugins = nil
    PluginLoader.disabled_plugins = nil
    UIManager = require("ui/uimanager")
    stub(UIManager, "getNthTopWidget")
    UIManager.getNthTopWidget.returns({})
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Event = require("ui/event")
    Screen = require("device").screen

    local sample_epub = "spec/front/unit/data/juliet.epub"
    readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })
    rolling = readerui.rolling
    for i = #UIManager._window_stack, 1, -1 do
      local w = UIManager._window_stack[i].widget
      if w ~= readerui then
        UIManager:close(w)
      end
    end
  end)

  describe("test in portrait screen mode", function()
    it("should goto portrait screen mode", function()
      readerui:handleEvent(
        Event:new("SetRotationMode", Screen.DEVICE_ROTATED_UPRIGHT)
      )
    end)

    it("should goto certain page", function()
      for i = 1, 10, 5 do
        rolling:onGotoPage(i)
        assert.are.same(i, rolling.current_page)
      end
    end)

    it("should return last percent progress", function()
      rolling:onGotoPage(5)
      assert.is_number(rolling:getLastPercent())
    end)

    it("should goto relative page", function()
      for i = 20, 40, 5 do
        rolling:onGotoPage(i)
        rolling:onGotoViewRel(1)
        assert.are.same(i + 1, rolling.current_page)
        rolling:onGotoViewRel(-1)
        assert.are.same(i, rolling.current_page)
      end
    end)

    it("should goto next chapter", function()
      local toc = readerui.toc
      for i = 30, 50, 5 do
        rolling:onGotoPage(i)
        rolling:onGotoNextChapter()
        assert.are.same(toc:getNextChapter(i, 0), rolling.current_page)
      end
    end)

    it("should goto previous chapter", function()
      local toc = readerui.toc
      for i = 60, 80, 5 do
        rolling:onGotoPage(i)
        rolling:onGotoPrevChapter()
        assert.are.same(toc:getPreviousChapter(i, 0), rolling.current_page)
      end
    end)

    it("should emit EndOfBook event at the end of sample epub", function()
      for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.toast then
          UIManager:close(w)
        end
      end
      local called = false
      readerui.onEndOfBook = function()
        called = true
      end
      -- check beginning of the book
      rolling:onGotoPage(1)
      assert.is.falsy(called)
      rolling:onGotoViewRel(-1)
      rolling:onGotoViewRel(-1)
      assert.is.falsy(called)
      -- check end of the book
      rolling:onGotoPage(readerui.document:getPageCount())
      assert.is.falsy(called)

      rolling:onGotoViewRel(1)
      assert.is.truthy(called)
      rolling:onGotoViewRel(1)
      assert.is.truthy(called)
      local dialog = UIManager._window_stack[#UIManager._window_stack].widget
      if dialog.name == "end_document" then
        UIManager:close(dialog)
      end
      readerui.onEndOfBook = nil
    end)

    it("should emit EndOfBook event at the end sample txt", function()
      local sample_txt = "spec/front/unit/data/sample.txt"
      -- Unsafe second // ReaderUI instance!
      ReaderUI.instance = nil
      local txt_readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_txt),
      })
      local called = false
      txt_readerui.onEndOfBook = function()
        called = true
      end
      local txt_rolling = txt_readerui.rolling
      -- check beginning of the book
      txt_rolling:onGotoPage(1)
      assert.is.falsy(called)
      txt_rolling:onGotoViewRel(-1)
      txt_rolling:onGotoViewRel(-1)
      assert.is.falsy(called)
      -- not at the end of the book
      txt_rolling:onGotoPage(3)
      assert.is.falsy(called)
      txt_rolling:onGotoViewRel(1)
      assert.is.falsy(called)
      -- at the end of the book
      txt_rolling:onGotoPage(txt_readerui.document:getPageCount())
      assert.is.falsy(called)
      txt_rolling:onGotoViewRel(1)
      assert.is.truthy(called)
      local dialog = UIManager._window_stack[#UIManager._window_stack].widget
      if dialog.name == "end_document" then
        UIManager:close(dialog)
      end
      readerui.onEndOfBook = nil
      txt_readerui:onExit()
      txt_readerui:onClose()
      -- Restore the ref to the original ReaderUI instance
      ReaderUI.instance = readerui
    end)
  end)

  describe("test in landscape screen mode", function()
    it("should go to landscape screen mode", function()
      readerui:handleEvent(
        Event:new("SetRotationMode", Screen.DEVICE_ROTATED_CLOCKWISE)
      )
    end)
    it("should goto certain page", function()
      for i = 1, 10, 5 do
        rolling:onGotoPage(i)
        assert.are.same(i, rolling.current_page)
      end
    end)
    it("should goto relative page", function()
      for i = 20, 40, 5 do
        rolling:onGotoPage(i)
        rolling:onGotoViewRel(1)
        assert.are.same(i + 1, rolling.current_page)
        rolling:onGotoViewRel(-1)
        assert.are.same(i, rolling.current_page)
      end
    end)
    it("should goto next chapter", function()
      local toc = readerui.toc
      for i = 30, 50, 5 do
        rolling:onGotoPage(i)
        rolling:onGotoNextChapter()
        assert.are.same(toc:getNextChapter(i, 0), rolling.current_page)
      end
    end)
    it("should goto previous chapter", function()
      local toc = readerui.toc
      for i = 60, 80, 5 do
        rolling:onGotoPage(i)
        rolling:onGotoPrevChapter()
        assert.are.same(toc:getPreviousChapter(i, 0), rolling.current_page)
      end
    end)
    it("should emit EndOfBook event at the end", function()
      for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.toast then
          UIManager:close(w)
        end
      end
      rolling:onGotoPage(readerui.document:getPageCount())
      local called = false
      readerui.onEndOfBook = function()
        called = true
      end

      rolling:onGotoViewRel(1)
      rolling:onGotoViewRel(1)
      assert.is.truthy(called)
      local dialog = UIManager._window_stack[#UIManager._window_stack].widget
      if dialog.name == "end_document" then
        UIManager:close(dialog)
      end
      readerui.onEndOfBook = nil
    end)
  end)

  describe(
    "switching screen mode should not change current page number",
    function()
      teardown(function()
        readerui:handleEvent(
          Event:new("SetRotationMode", Screen.DEVICE_ROTATED_UPRIGHT)
        )
      end)
      it("for portrait-landscape-portrait switching", function()
        for i = 80, 100, 10 do
          readerui:handleEvent(
            Event:new("SetRotationMode", Screen.DEVICE_ROTATED_UPRIGHT)
          )
          rolling:onGotoPage(i)
          assert.are.same(i, rolling.current_page)
          readerui:handleEvent(
            Event:new("SetRotationMode", Screen.DEVICE_ROTATED_CLOCKWISE)
          )
          assert.are_not.same(i, rolling.current_page)
          readerui:handleEvent(
            Event:new("SetRotationMode", Screen.DEVICE_ROTATED_UPRIGHT)
          )
          assert.are.same(i, rolling.current_page)
        end
      end)
      it("for landscape-portrait-landscape switching", function()
        for i = 110, 130, 10 do
          readerui:handleEvent(
            Event:new("SetRotationMode", Screen.DEVICE_ROTATED_CLOCKWISE)
          )
          rolling:onGotoPage(i)
          assert.are.same(i, rolling.current_page)
          readerui:handleEvent(
            Event:new("SetRotationMode", Screen.DEVICE_ROTATED_UPRIGHT)
          )
          assert.are_not.same(i, rolling.current_page)
          readerui:handleEvent(
            Event:new("SetRotationMode", Screen.DEVICE_ROTATED_CLOCKWISE)
          )
          assert.are.same(i, rolling.current_page)
        end
      end)
    end
  )

  describe("test changing word gap - space condensing", function()
    it("should show pages for different word gap", function()
      readerui:handleEvent(Event:new("SetWordSpacing", { 100, 90 }))
      assert.are.same(252, readerui.document:getPageCount())
      readerui:handleEvent(Event:new("SetWordSpacing", { 95, 75 }))
      assert.are.same(241, readerui.document:getPageCount())
      readerui:handleEvent(Event:new("SetWordSpacing", { 75, 50 }))
      assert.are.same(231, readerui.document:getPageCount())
    end)
  end)

  describe("test goto percent and relative page navigation", function()
    it("should jump to percent position", function()
      rolling:onGotoPercent(25)
      assert.is_number(rolling:getLastPercent())
      assert.is_not_nil(rolling.xpointer)
    end)

    it("should jump to relative page", function()
      rolling:onGotoPage(10)
      rolling:onGotoRelativePage(5)
      assert.are.same(15, rolling.current_page)
      rolling:onGotoRelativePage(-3)
      assert.are.same(12, rolling.current_page)
    end)

    it("should save and restore book location", function()
      rolling:onGotoPage(15)
      local loc = { xpointer = rolling:getBookLocation() }
      assert.is_not_nil(loc.xpointer)
      rolling:onGotoPage(40)
      assert.are.same(40, rolling.current_page)
      rolling:onRestoreBookLocation(loc)
      assert.are.same(15, rolling.current_page)
    end)

    it("should handle relative page navigation boundary jumps", function()
      rolling:onGotoPage(10)
      rolling:onGotoRelativePage(-100)
      assert.is_true(rolling.current_page >= 1)
    end)
  end)

  describe("test scroll settings and panning", function()
    it("should update scroll settings", function()
      local time = require("ui/time")
      rolling:onScrollSettingsUpdated("classic", true, 200)
      assert.are.same("classic", rolling.scroll_method)
      assert.are.same(200, time.to_ms(rolling.scroll_activation_delay))
      rolling:onScrollSettingsUpdated("turbo", false, 100)
      assert.are.same("turbo", rolling.scroll_method)
      assert.are.same(100, time.to_ms(rolling.scroll_activation_delay))
    end)

    it("should handle panning in page and scroll modes", function()
      readerui.view.view_mode = "page"
      rolling:onPanning({ 0, 1 })
      readerui.view.view_mode = "scroll"
      local pos_before = rolling.current_pos
      rolling:onPanning({ 0, 1 })
      assert.are_not.same(pos_before, rolling.current_pos)
      readerui.view.view_mode = "page"
    end)
  end)

  describe("test settings handlers and mode toggles", function()
    it("should toggle hide non-linear fragments", function()
      local orig = rolling.hide_nonlinear_flows
      rolling:onToggleHideNonlinear()
      assert.are.same(not orig, rolling.hide_nonlinear_flows)
      rolling:onToggleHideNonlinear()
      assert.are.same(orig, rolling.hide_nonlinear_flows)
    end)

    it("should set status line property", function()
      rolling:onSetStatusLine(0)
      assert.is_true(rolling.cre_top_bar_enabled)
      rolling:onSetStatusLine(1)
      assert.is_false(rolling.cre_top_bar_enabled)
    end)

    it("should set visible pages count", function()
      rolling:onSetVisiblePages(2)
      assert.are.same(2, rolling.configurable.visible_pages)
      rolling:onSetVisiblePages(1)
      assert.are.same(1, rolling.configurable.visible_pages)
    end)

    it("should update view mode changes", function()
      rolling:onChangeViewMode()
      assert.is_number(rolling.current_header_height)
    end)
  end)

  describe("test swipe and gesture options", function()
    it(
      "should handle swipe gestures with normal and inverse reading order",
      function()
        rolling:onGotoPage(10)
        readerui.view.inverse_reading_order = false
        rolling:onSwipe(nil, { direction = "west" })
        assert.are.same(11, rolling.current_page)
        rolling:onSwipe(nil, { direction = "east" })
        assert.are.same(10, rolling.current_page)
        readerui.view.inverse_reading_order = true
        rolling:onSwipe(nil, { direction = "west" })
        assert.are.same(9, rolling.current_page)
        rolling:onSwipe(nil, { direction = "east" })
        assert.are.same(10, rolling.current_page)
        readerui.view.inverse_reading_order = false
      end
    )
  end)

  describe("test main menu items and battery state", function()
    it("should populate main menu items", function()
      local menu_items = {}
      rolling:addToMainMenu(menu_items)
      assert.is_table(menu_items.partial_rerendering)
      assert.is_function(menu_items.partial_rerendering.enabled_func)
      assert.is_function(menu_items.partial_rerendering.checked_func)
      assert.is_function(menu_items.partial_rerendering.callback)
    end)

    it(
      "should update battery state according to view mode and status line",
      function()
        rolling:onSetStatusLine(0)
        readerui.view.view_mode = "page"
        local batt = rolling:updateBatteryState()
        assert.is_number(batt)
        readerui.view.view_mode = "scroll"
        assert.are.same(0, rolling:updateBatteryState())
        readerui.view.view_mode = "page"
        rolling:onSetStatusLine(1)
        assert.are.same(0, rolling:updateBatteryState())
      end
    )
  end)

  describe("test key events registration", function()
    it("should register key events with left_right_keys_turn_pages", function()
      G_reader_settings:save("left_right_keys_turn_pages", true)
      rolling:registerKeyEvents()
      assert.is_table(rolling.key_events)
      G_reader_settings:save("left_right_keys_turn_pages", false)
      rolling:registerKeyEvents()
      assert.is_table(rolling.key_events)
    end)
  end)

  describe("test xpointer and position navigation", function()
    it("should navigate using xpointer", function()
      rolling:onGotoPage(5)
      local xp = rolling.xpointer
      assert.is_not_nil(xp)
      rolling:onGotoPage(12)
      assert.are.same(12, rolling.current_page)
      rolling:onGotoXPointer(xp)
      assert.are.same(5, rolling.current_page)
    end)

    it("should handle gesture reset in onHandledAsSwipe", function()
      rolling._pan_started = true
      rolling._pan_pos_at_pan_start = 50
      rolling:onHandledAsSwipe()
      assert.are.same(50, rolling.current_pos)
      assert.is_false(rolling._pan_started)
    end)

    it("should handle pan release", function()
      rolling._pan_has_scrolled = true
      rolling._pan_to_scroll_later = 0
      rolling:onPanRelease(nil, { from_mousewheel = true })
      assert.is_false(rolling._pan_started)
      assert.is_false(rolling._pan_has_scrolled)
    end)
  end)

  describe("test document events and settings persistence", function()
    it("should handle zoom event", function()
      rolling:onZoom()
    end)

    it("should handle color rendering update event", function()
      rolling:onColorRenderingUpdate()
    end)

    it("should save settings correctly", function()
      rolling:onSaveSettings()
      assert.are.same(
        rolling.xpointer,
        readerui.doc_settings:read("last_xpointer")
      )
      assert.are.same(
        rolling.hide_nonlinear_flows,
        readerui.doc_settings:read("hide_nonlinear_flows")
      )
    end)
  end)

  describe("test gestures and scrolling operations", function()
    it("should handle navigation by percentage and relative page", function()
      rolling:onGotoPercent(0.5)
      assert.is_number(rolling.current_page)
      rolling:onGotoPercent(0.1)
      assert.is_number(rolling.current_page)
      rolling:onGotoRelativePage(2)
      assert.is_number(rolling.current_page)
      rolling:onGotoRelativePage(-1)
      assert.is_number(rolling.current_page)
    end)

    it("should handle swipe gestures in various directions", function()
      rolling:onSwipe(nil, { direction = "west", distance = 120 })
      rolling:onSwipe(nil, { direction = "east", distance = 120 })
      rolling:onSwipe(nil, { direction = "north", distance = 120 })
      rolling:onSwipe(nil, { direction = "south", distance = 120 })
    end)

    it("should handle visible pages and dimensions update", function()
      rolling:onSetVisiblePages(1)
      assert.are.same(1, rolling.configurable.visible_pages)
      rolling:onSetDimensions(Screen:getSize())
      rolling:onPosUpdate(10)
      rolling:onPageUpdate(5)
      assert.are.same(5, rolling.current_page)
    end)

    it("should handle progress query and main menu items", function()
      local prog = rolling:getLastProgress()
      assert.is_not_nil(prog)
      local menu_items = {}
      rolling:addToMainMenu(menu_items)
      assert.is_not_nil(menu_items)
      rolling:updateBatteryState()
    end)
  end)

  describe("test initialization", function()
    it("should emit PageUpdate event after book is rendered", function()
      local ReaderView = require("apps/reader/modules/readerview")
      local saved_handler = ReaderView.onPageUpdate
      ReaderView.onPageUpdate = function(this, new_page_no)
        saved_handler(this, new_page_no)
        assert.are.same(6, this.ui.document:getPageCount())
      end
      local test_book = "spec/front/unit/data/sample.txt"
      require("docsettings"):open(test_book):purge()
      readerui:onExit()
      readerui:onClose()
      local tmp_readerui = ReaderUI:new({
        document = DocumentRegistry:openDocument(test_book),
      })
      ReaderView.onPageUpdate = saved_handler
      tmp_readerui:onExit()
      tmp_readerui:onClose()
    end)
  end)

  it("should check readerrolling instance state and save settings", function()
    assert.is_table(rolling)
    if type(rolling.onSaveSettings) == "function" then
      rolling:onSaveSettings()
    end
  end)
end)
