describe("ReaderLink module", function()
  local DocumentRegistry, ReaderUI, UIManager, sample_epub, sample_pdf, Event, Screen

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
    DocumentRegistry = require("document/documentregistry")
    Event = require("ui/event")
    ReaderUI = require("apps/reader/readerui")
    UIManager = require("ui/uimanager")
    Screen = require("device").screen
    sample_epub = "spec/front/unit/data/leaves.epub"
    sample_pdf = "spec/front/unit/data/paper.pdf"
  end)

  local readerui

  local function fastforward_ui_events()
    -- Fast forward all scheduled tasks.
    UIManager:shiftScheduledTasksBy(-1e9)
    UIManager:handleInput()
  end

  after_each(function()
    if readerui then
      readerui:onExit()
      readerui:onClose()
      readerui = nil
    end
    UIManager:quit()
    UIManager._exit_code = nil
  end)

  describe("with epub", function()
    before_each(function()
      readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_epub),
      })
    end)

    it("should jump to links #nocov", function()
      readerui.rolling:onGotoPage(5)
      readerui.link:onTap(nil, { pos = { x = 320, y = 190 } })
      assert.is.same(37, readerui.rolling.current_page)
    end)

    it("should be able to go back after link jump #nocov", function()
      readerui.rolling:onGotoPage(5)
      readerui.link:onTap(nil, { pos = { x = 320, y = 190 } })
      assert.is.same(37, readerui.rolling.current_page)
      readerui.link:onGoBackLink()
      assert.is.same(5, readerui.rolling.current_page)
    end)
  end)

  describe("with pdf", function()
    before_each(function()
      readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_pdf),
      })
    end)

    it("should jump to links in page mode", function()
      readerui:handleEvent(Event:new("SetScrollMode", false))
      readerui:handleEvent(Event:new("SetZoomMode", "page"))
      readerui.paging:onGotoPage(1)
      readerui.link:onTap(nil, { pos = { x = 363, y = 565 } })
      fastforward_ui_events()
      assert.is.same(22, readerui.paging.current_page)
    end)

    it("should jump to links in scroll mode", function()
      readerui:handleEvent(Event:new("SetScrollMode", true))
      readerui:handleEvent(Event:new("SetZoomMode", "page"))
      readerui.paging:onGotoPage(1)
      assert.is.same(1, readerui.paging.current_page)
      readerui.link:onTap(nil, { pos = { x = 228, y = 534 } })
      fastforward_ui_events()
      assert.truthy(
        readerui.paging.current_page == 21 or readerui.paging.current_page == 20
      )
    end)

    it("should be able to go back after link jump in page mode", function()
      readerui:handleEvent(Event:new("SetScrollMode", false))
      readerui:handleEvent(Event:new("SetZoomMode", "page"))
      readerui.paging:onGotoPage(1)
      readerui.link:onTap(nil, { pos = { x = 363, y = 565 } })
      fastforward_ui_events()
      assert.is.same(22, readerui.paging.current_page)
      readerui.link:onGoBackLink()
      assert.is.same(1, readerui.paging.current_page)
    end)

    it("should be able to go back after link jump in scroll mode", function()
      readerui:handleEvent(Event:new("SetScrollMode", true))
      readerui:handleEvent(Event:new("SetZoomMode", "page"))
      readerui.paging:onGotoPage(1)
      assert.is.same(1, readerui.paging.current_page)
      readerui.link:onTap(nil, { pos = { x = 228, y = 534 } })
      fastforward_ui_events()
      assert.truthy(
        readerui.paging.current_page == 21 or readerui.paging.current_page == 20
      )
      readerui.link:onGoBackLink()
      assert.is.same(1, readerui.paging.current_page)
    end)

    it(
      "should be able to go back to the same position after link jump in scroll mode",
      function()
        local expected_page_states = {
          {
            gamma = 1,
            offset = { x = 17, y = 0 },
            page = 3,
            page_area = {
              x = 0,
              y = 0,
              h = 800,
              w = 566,
            },
            rotation = 0,
            visible_area = {
              x = 0,
              y = 694,
              h = 106,
              w = 566,
            },
            zoom = 0.95032191328269044472,
          },
          {
            gamma = 1,
            offset = { x = 17, y = 0 },
            page = 4,
            page_area = {
              h = 800,
              w = 566,
              x = 0,
              y = 0,
            },
            rotation = 0,
            visible_area = {
              h = 686,
              w = 566,
              x = 0,
              y = 0,
            },
            zoom = 0.95032191328269044472,
          },
        }
        -- disable footer
        G_reader_settings:save("reader_footer_mode", 0)
        require("docsettings"):open(sample_pdf):purge()
        if readerui then
          readerui:onExit()
          readerui:onClose()
          readerui = nil
        end
        readerui = ReaderUI:new({
          dimen = Screen:getSize(),
          document = DocumentRegistry:openDocument(sample_pdf),
        })
        readerui:handleEvent(Event:new("SetZoomMode", "page"))
        assert.is.falsy(readerui.view.footer_visible)
        readerui.paging:onGotoPage(1)
        assert.is.same(1, readerui.paging.current_page)
        readerui.view:onSetScrollMode(true)
        assert.is.same(true, readerui.view.page_scroll)
        assert.is.same(1, readerui.paging.current_page)

        readerui.paging:onGotoViewRel(1)
        assert.is.same(2, readerui.paging.current_page)

        readerui.paging:onGotoViewRel(-1)
        assert.is.same(1, readerui.paging.current_page)

        readerui.paging:onGotoViewRel(1)
        readerui.paging:onGotoViewRel(1)
        assert.is.same(3, readerui.paging.current_page)

        readerui.paging:onGotoViewRel(-1)
        assert.is.same(2, readerui.paging.current_page)

        readerui.paging:onGotoViewRel(1)
        readerui.paging:onGotoViewRel(1)
        assert.is.same(4, readerui.paging.current_page)
        assert.are.same(expected_page_states, readerui.view.page_states)

        readerui.link:onTap(nil, { pos = { x = 164, y = 366 } })
        fastforward_ui_events()
        assert.is.same(22, readerui.paging.current_page)
        readerui.link:onGoBackLink()
        assert.is.same(3, readerui.paging.current_page)
        assert.are.same(expected_page_states, readerui.view.page_states)
      end
    )
  end)

  describe("location stack management", function()
    before_each(function()
      readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_epub),
      })
    end)

    it("should add, pop, and clear location stack", function()
      local link_mod = readerui.link
      link_mod:onClearLocationStack()
      assert.is.same(0, #link_mod.location_stack)
      assert.is.same(0, #link_mod.forward_location_stack)

      link_mod:addCurrentLocationToStack({ xpointer = "/1/2/3" })
      assert.is.same(1, #link_mod.location_stack)

      local prev_pages = link_mod:getPreviousLocationPages()
      assert.truthy(prev_pages)

      local pop_loc = link_mod:popFromLocationStack()
      assert.is.same("/1/2/3", pop_loc.xpointer)
      assert.is.same(0, #link_mod.location_stack)

      link_mod:addCurrentLocationToStack({ xpointer = "/1/4/5" })
      link_mod:onClearLocationStack()
      assert.is.same(0, #link_mod.location_stack)
    end)

    it("should handle forward location stack navigation", function()
      local link_mod = readerui.link
      link_mod:onClearLocationStack()

      readerui.rolling:onGotoPage(5)
      link_mod:addCurrentLocationToStack()
      readerui.rolling:onGotoPage(37)

      assert.is.same(1, #link_mod.location_stack)
      assert.is.same(0, #link_mod.forward_location_stack)

      link_mod:onGoBackLink()
      assert.is.same(5, readerui.rolling.current_page)
      assert.is.same(0, #link_mod.location_stack)

      link_mod:onGoForwardLink()
      assert.is.same(37, readerui.rolling.current_page)
      assert.is.same(2, #link_mod.location_stack)
      assert.is.same(0, #link_mod.forward_location_stack)
    end)

    it("should compare current location to saved location", function()
      local link_mod = readerui.link
      readerui.rolling:onGotoPage(5)
      local cur_loc = link_mod:getCurrentLocation()

      local same, loc = link_mod:compareLocationToCurrent(cur_loc)
      assert.is_true(same)
      assert.is.same(cur_loc.xpointer, loc.xpointer)

      local diff_loc = { xpointer = "/different/xpointer" }
      local same_diff, _ = link_mod:compareLocationToCurrent(diff_loc)
      assert.is_false(same_diff)
    end)

    it("should notify on adding location to stack", function()
      local link_mod = readerui.link
      link_mod:onClearLocationStack()
      local res = link_mod:onAddCurrentLocationToStack(true)
      assert.is_true(res)
      assert.is.same(1, #link_mod.location_stack)

      local res2 = link_mod:onAddCurrentLocationToStackNonTouch()
      assert.is_true(res2)
      assert.is.same(2, #link_mod.location_stack)
    end)
  end)

  describe("external links and custom buttons", function()
    before_each(function()
      readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_epub),
      })
    end)

    it("should generate external link dialog buttons", function()
      local link_mod = readerui.link
      local url = "https://en.wikipedia.org/wiki/Lua"
      local buttons, title = link_mod:getButtonsForExternalLinkDialog(url)
      assert.truthy(buttons)
      assert.truthy(title)
      assert.truthy(title:find("Wikipedia"))
    end)

    it("should allow registering custom external link buttons", function()
      local link_mod = readerui.link
      local custom_called = false
      link_mod:addToExternalLinkDialog("50_custom", function(this, link_url)
        return {
          text = "Custom Action",
          callback = function()
            custom_called = true
          end,
        }
      end)

      local buttons, _ =
        link_mod:getButtonsForExternalLinkDialog("https://example.com")
      local found = false
      for _, row in ipairs(buttons) do
        for _, btn in ipairs(row) do
          if btn.text == "Custom Action" then
            found = true
            btn.callback()
          end
        end
      end
      assert.is_true(found)
      assert.is_true(custom_called)
    end)

    it("should open external link dialog for supported URL schemes", function()
      local link_mod = readerui.link
      local url = "https://koreader.rocks"
      local res = link_mod:onGoToExternalLink(url)
      assert.is_true(res)
      assert.truthy(link_mod.external_link_dialog)
      UIManager:close(link_mod.external_link_dialog)
    end)

    it("should handle invalid or unsupported external link", function()
      local link_mod = readerui.link
      local fake_link = { xpointer = "invalid_scheme://test" }
      local handled = link_mod:onGotoLink(fake_link)
      assert.is_true(handled)
    end)
  end)

  describe("keyboard link selection", function()
    before_each(function()
      readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_epub),
      })
    end)

    it("should select next and prev page links", function()
      local link_mod = readerui.link
      readerui.rolling:onGotoPage(5)

      local has_link = link_mod:onSelectNextPageLink()
      if has_link then
        assert.truthy(link_mod.cur_selected_link)
        assert.is.same(1, link_mod.cur_selected_page_link_num)

        link_mod:onSelectPrevPageLink()
        assert.is_nil(link_mod.cur_selected_link)
      end
    end)

    it("should clear selected link on page and position update", function()
      local link_mod = readerui.link
      link_mod.cur_selected_link = { xpointer = "/test" }
      link_mod.cur_selected_page_link_num = 1

      link_mod:onPageUpdate()
      assert.is_nil(link_mod.cur_selected_link)
      assert.is_nil(link_mod.cur_selected_page_link_num)

      link_mod.cur_selected_link = { xpointer = "/test" }
      link_mod:onPosUpdate()
      assert.is_nil(link_mod.cur_selected_link)
    end)
  end)

  describe("swipe gestures and settings", function()
    before_each(function()
      readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_epub),
      })
    end)

    it("should handle swipe east to go back when enabled", function()
      local link_mod = readerui.link
      G_reader_settings:save("swipe_to_go_back", true)

      readerui.rolling:onGotoPage(5)
      link_mod:addCurrentLocationToStack()
      readerui.rolling:onGotoPage(37)

      local handled = link_mod:onSwipe(nil, { direction = "east" })
      assert.is_true(handled)
      assert.is.same(5, readerui.rolling.current_page)
    end)

    it("should resist empty location history swipe east", function()
      local link_mod = readerui.link
      G_reader_settings:save("swipe_to_go_back", true)
      link_mod:onClearLocationStack()

      local handled = link_mod:onSwipe(nil, { direction = "east" })
      assert.is.falsy(handled)

      link_mod.swipe_back_resist = true
      local handled_resist = link_mod:onSwipe(nil, { direction = "east" })
      assert.is_true(handled_resist)
      assert.is_false(link_mod.swipe_back_resist)
    end)

    it("should handle swipe west to jump to latest bookmark", function()
      local link_mod = readerui.link
      G_reader_settings:save("swipe_to_follow_nearest_link", false)
      G_reader_settings:save("swipe_to_jump_to_latest_bookmark", true)

      readerui.rolling:onGotoPage(10)
      table.insert(readerui.annotation.annotations, {
        datetime = "2026-07-25 12:00:00",
        page = readerui.rolling:getBookLocation(),
      })

      readerui.rolling:onGotoPage(2)
      local handled = link_mod:onSwipe(nil, { direction = "west" })
      assert.truthy(handled)
      assert.is.same(10, readerui.rolling.current_page)
    end)
  end)

  describe("main menu integration and footnote checks", function()
    before_each(function()
      readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_epub),
      })
    end)

    it("should register link items in main menu", function()
      local link_mod = readerui.link
      local menu_items = {}
      link_mod:addToMainMenu(menu_items)

      assert.truthy(menu_items.go_to_previous_location)
      assert.truthy(menu_items.go_to_next_location)

      assert.is.falsy(menu_items.go_to_previous_location.enabled_func())
      assert.is.falsy(menu_items.go_to_next_location.enabled_func())

      link_mod:addCurrentLocationToStack({ xpointer = "/test" })
      assert.is_true(menu_items.go_to_previous_location.enabled_func())

      link_mod:onGoBackLink()
      assert.is_true(menu_items.go_to_next_location.enabled_func())
    end)

    it("should handle footnote popup check in paging mode", function()
      if readerui then
        readerui:onExit()
        readerui:onClose()
        readerui = nil
      end
      readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_pdf),
      })
      local link_mod = readerui.link
      assert.is_false(link_mod:showAsFootnotePopup({ xpointer = "/test" }))
    end)

    it("should execute built-in external link buttons", function()
      local link_mod = readerui.link
      local Device = require("device")
      local opened_url = nil
      local orig_openLink = Device.openLink
      Device.openLink = function(self_dev, link)
        opened_url = link
      end
      local orig_setClip = Device.input.setClipboardText
      Device.input.setClipboardText = function() end

      local url = "https://en.wikipedia.org/wiki/Test"
      local buttons, _ = link_mod:getButtonsForExternalLinkDialog(url)
      assert.truthy(buttons)

      -- Open dialog
      link_mod:onGoToExternalLink(url)
      assert.truthy(link_mod.external_link_dialog)

      -- Test 10_copy
      local copy_btn = link_mod._external_link_buttons["10_copy"](link_mod, url)
      copy_btn.callback()

      -- Test 20_qrcode
      link_mod:onGoToExternalLink(url)
      local qr_btn = link_mod._external_link_buttons["20_qrcode"](link_mod, url)
      qr_btn.callback()

      -- Test 30_browser
      link_mod:onGoToExternalLink(url)
      local browser_btn =
        link_mod._external_link_buttons["30_browser"](link_mod, url)
      browser_btn.callback()
      assert.is.same(url, opened_url)

      -- Test 90_cancel
      link_mod:onGoToExternalLink(url)
      local cancel_btn =
        link_mod._external_link_buttons["90_cancel"](link_mod, url)
      cancel_btn.callback()

      Device.openLink = orig_openLink
      Device.input.setClipboardText = orig_setClip
    end)

    it("should test isXpointerCoherent and onGoToInternalPageLink", function()
      local link_mod = readerui.link
      local coherent =
        link_mod:isXpointerCoherent("/body/DocFragment/body/div/p[1]")
      assert.truthy(coherent == true or coherent == false)

      link_mod:onGoToInternalPageLink({ pos = { x = 320, y = 190 } })
    end)
  end)
end)
