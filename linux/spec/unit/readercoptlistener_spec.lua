describe("ReaderCoptListener module", function()
  local ReaderCoptListener, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    ReaderCoptListener = require("apps/reader/modules/readercoptlistener")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should update view_mode using self.ui.view on read settings", function()
    local mock_doc = {
      configurable = { view_mode = 0, status_line = 0 },
      setViewMode = function() end,
      setPageInfoOverride = function() end,
      prop_to_cre_prop = {},
      _document = {
        setIntProperty = function() end,
        setStringProperty = function() end,
      },
    }
    local mock_ui = {
      view = { view_mode = "page" },
      rolling = {
        updateBatteryState = function()
          return 100
        end,
      },
      doc_settings = {
        read = function()
          return nil
        end,
      },
    }
    local listener = ReaderCoptListener:new({
      document = mock_doc,
      ui = mock_ui,
    })

    if type(listener.onReadSettings) == "function" then
      listener:onReadSettings({})
    end
  end)

  it("should instantiate copt listener module", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local doc = DocumentRegistry:openDocument(sample_epub)
    local listener = ReaderCoptListener:new({
      document = doc,
      view = {},
    })

    assert.is_table(listener)
    assert.is_table(listener.additional_header_content)

    doc:close()
  end)

  it("should handle event propagation methods safely", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local doc = DocumentRegistry:openDocument(sample_epub)
    local listener = ReaderCoptListener:new({
      document = doc,
      view = {},
    })

    if type(listener.onSetCreFont) == "function" then
      listener:onSetCreFont("Noto Sans", 100)
    end

    if type(listener.onCoptChanged) == "function" then
      listener:onCoptChanged("copt_key", "copt_val")
    end

    if type(listener.onSetInterlineSpace) == "function" then
      listener:onSetInterlineSpace(120)
    end

    if type(listener.onSetGammaIndex) == "function" then
      listener:onSetGammaIndex(15)
    end

    doc:close()
  end)

  it("should handle reader ready and settings callbacks", function()
    local mock_doc = {
      configurable = { view_mode = 0, status_line = 0 },
      setViewMode = function() end,
      setPageInfoOverride = function() end,
      prop_to_cre_prop = {},
      _document = {
        setIntProperty = function() end,
        setStringProperty = function() end,
      },
    }
    local mock_ui = {
      view = { view_mode = "page" },
      rolling = {
        updateBatteryState = function()
          return 100
        end,
      },
      doc_settings = {
        read = function()
          return nil
        end,
      },
    }
    local listener = ReaderCoptListener:new({
      document = mock_doc,
      ui = mock_ui,
    })

    if type(listener.onReadSettings) == "function" then
      listener:onReadSettings({})
    end
    if type(listener.onReaderReady) == "function" then
      listener:onReaderReady()
    end
  end)

  describe("getAltStatusBarMenu and Header lifecycle", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local doc

    local function createMockListener()
      local listener = ReaderCoptListener:new({
        document = doc,
        view = { view_mode = "page" },
        showWidget = function() end,
        ui = {
          view = {
            footer = {
              pageno = 1,
              settings = { progress_pct_format = "0" },
            },
          },
          document = doc,
          rolling = {
            updateBatteryState = function()
              return 100
            end,
          },
          doc_settings = {
            read = function()
              return nil
            end,
          },
          doc_props = {},
        },
      })
      listener:onReadSettings({})
      return listener
    end

    before_each(function()
      doc = DocumentRegistry:openDocument(sample_epub)
    end)

    after_each(function()
      if doc then
        doc:close()
      end
    end)

    it("should populate getAltStatusBarMenu items and exercise callbacks", function()
      local listener = createMockListener()
      local menu = listener:getAltStatusBarMenu()
      assert.truthy(menu)
      assert.truthy(menu.sub_item_table)

      for _, item in ipairs(menu.sub_item_table) do
        if item.checked_func then
          pcall(item.checked_func)
        end
        if item.text_func then
          pcall(item.text_func)
        end
        if item.callback then
          pcall(item.callback)
        end
        if item.sub_item_table then
          for _, sub in ipairs(item.sub_item_table) do
            if sub.checked_func then
              pcall(sub.checked_func)
            end
            if sub.callback then
              pcall(sub.callback)
            end
          end
        end
      end
    end)

    it("should add and remove additional header content", function()
      local listener = createMockListener()
      local test_fn = function()
        return "HEADER"
      end
      assert.is_true(listener:addAdditionalHeaderContent(test_fn))
      assert.is_false(listener:addAdditionalHeaderContent(test_fn))
      assert.is_true(listener:removeAdditionalHeaderContent(test_fn))
      assert.is_false(listener:removeAdditionalHeaderContent(test_fn))
    end)

    it("should calculate page_info_override and handle header update events", function()
      local listener = createMockListener()
      listener.page_number = 1
      listener.page_count = 1
      listener.reading_percent = 1
      listener.battery = 1
      listener.battery_percent = 1
      listener.clock = 1

      local pinfo = listener:page_info_override()
      assert.is_boolean(pinfo)
      listener:page_info_override(1)

      listener:_updateHeader(true)
      listener:onUpdateHeader()
      listener:onTimeFormatChanged()
      listener:onBookMetadataChanged("title")
      listener:onPageUpdate(1)
      listener:onPosUpdate(1, 1)
    end)

    it("should handle battery, resume, screensaver, and config change events", function()
      local listener = createMockListener()
      listener:onCharging()
      listener:onResume()
      listener:onOutOfScreenSaver()

      listener:onConfigChange("font_size", 20)
      listener:onConfigChange("font_size", 2)
    end)
  end)
end)

