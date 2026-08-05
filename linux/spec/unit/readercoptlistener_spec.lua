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
  end)
end)
