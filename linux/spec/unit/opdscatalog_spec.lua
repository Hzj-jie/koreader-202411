describe("OPDSCatalog module", function()
  local OPDSCatalog
  local ConfirmBox
  local FrameContainer
  local OPDSBrowser
  local ReaderUI
  local Screen
  local UIManager

  setup(function()
    require("commonrequire")
    OPDSCatalog = require("plugins/opds.koplugin/opdscatalog")
    ConfirmBox = require("ui/widget/confirmbox")
    FrameContainer = require("ui/widget/container/framecontainer")
    OPDSBrowser = require("plugins/opds.koplugin/opdsbrowser")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
    UIManager = require("ui/uimanager")
  end)

  describe("Initialization & Widget Structure", function()
    it("should initialize OPDSCatalog with FrameContainer and OPDSBrowser", function()
      local catalog = OPDSCatalog:new({ title = "My OPDS Catalog" })
      assert.is_table(catalog)
      assert.are.equal("My OPDS Catalog", catalog.title)

      local frame = catalog[1]
      assert.is_table(frame)
      assert.are.equal(0, frame.padding)
      assert.are.equal(0, frame.bordersize)

      local browser = frame[1]
      assert.is_table(browser)
      assert.are.equal("My OPDS Catalog", browser.title)
      assert.is_false(browser.is_popout)
      assert.is_true(browser.is_borderless)
      assert.is_function(browser.close_callback)
      assert.is_function(browser.file_downloaded_callback)
    end)
  end)

  describe("Catalog Lifecycle & Display", function()
    it("should handle onShow and onClose by updating UIManager dirty state", function()
      local catalog = OPDSCatalog:new()
      catalog[1].dimen = { x = 0, y = 0, w = 100, h = 200 }

      local dirty_calls = {}
      local old_set_dirty = UIManager.setDirty
      UIManager.setDirty = function(_self, target, func)
        table.insert(dirty_calls, { target = target, res = { func() } })
      end

      catalog:onShow()
      assert.are.equal(1, #dirty_calls)
      assert.are.equal(catalog, dirty_calls[1].target)
      assert.are.equal("ui", dirty_calls[1].res[1])

      catalog:onClose()
      assert.are.equal(2, #dirty_calls)
      assert.is_nil(dirty_calls[2].target)
      assert.are.equal("ui", dirty_calls[2].res[1])

      UIManager.setDirty = old_set_dirty
    end)

    it("should handle onExit by closing itself via UIManager", function()
      local catalog = OPDSCatalog:new()

      local closed_target
      local old_close = UIManager.close
      UIManager.close = function(_self, target)
        closed_target = target
      end

      local res = catalog:onExit()
      assert.is_true(res)
      assert.are.equal(catalog, closed_target)

      UIManager.close = old_close
    end)

    it("should handle showCatalog by displaying catalog sized to Screen", function()
      local shown_target
      local old_show = UIManager.show
      UIManager.show = function(_self, target)
        shown_target = target
      end

      OPDSCatalog:showCatalog()
      assert.is_table(shown_target)
      assert.are.equal(Screen:getWidth(), shown_target.dimen.w)
      assert.are.equal(Screen:getHeight(), shown_target.dimen.h)

      UIManager.show = old_show
    end)

    it("should invoke onExit when browser close_callback is called", function()
      local catalog = OPDSCatalog:new()
      local browser = catalog[1][1]

      local on_exit_called = false
      catalog.onExit = function()
        on_exit_called = true
        return true
      end

      assert.is_true(browser.close_callback())
      assert.is_true(on_exit_called)
    end)
  end)

  describe("File Downloaded Callback & ConfirmBox", function()
    it("should display ConfirmBox with Read Now / Read Later options on file downloaded", function()
      local catalog = OPDSCatalog:new()
      local browser = catalog[1][1]

      local shown_widget
      local old_show = UIManager.show
      UIManager.show = function(_self, widget)
        shown_widget = widget
      end

      local old_broadcast = UIManager.broadcastEvent
      local broadcasted_event
      UIManager.broadcastEvent = function(_self, ev)
        broadcasted_event = ev
      end

      local old_show_reader = ReaderUI.showReader
      local reader_opened_file
      ReaderUI.showReader = function(_self, file)
        reader_opened_file = file
      end

      local catalog_exited = false
      catalog.onExit = function()
        catalog_exited = true
      end

      browser.file_downloaded_callback("/tmp/downloaded_sample.epub")

      assert.is_table(shown_widget)
      assert.is_truthy(shown_widget.text:find("downloaded_sample%.epub"))
      assert.is_function(shown_widget.ok_callback)

      -- Trigger OK callback (Read now)
      shown_widget.ok_callback()
      assert.is_truthy(broadcasted_event)
      assert.are.equal("onSetupShowReader", broadcasted_event.handler)
      assert.is_true(catalog_exited)
      assert.are.equal("/tmp/downloaded_sample.epub", reader_opened_file)

      UIManager.show = old_show
      UIManager.broadcastEvent = old_broadcast
      ReaderUI.showReader = old_show_reader
    end)
  end)
end)
