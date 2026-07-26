describe("ReaderCoptListener module", function()
  local ReaderCoptListener

  setup(function()
    require("commonrequire")
    ReaderCoptListener = require("apps/reader/modules/readercoptlistener")
  end)

  it("should update view_mode using self.ui.view on read settings", function()
    local mock_ui = {
      view = {
        view_mode = "page",
      },
      rolling = {
        updateBatteryState = function() end,
      },
    }
    local mock_config = {
      read = function()
        return nil
      end,
    }

    local listener = ReaderCoptListener:new({
      ui = mock_ui,
      document = {
        configurable = { view_mode = 0 },
        setViewMode = function() end,
        setPageInfoOverride = function() end,
        _document = {
          setIntProperty = function() end,
        },
      },
    })

    assert.is_not_nil(listener)
    listener:onReadSettings(mock_config)
    assert.are.equal("page", mock_ui.view.view_mode)
  end)
end)

describe("ReaderCoptListener module", function()
  local ReaderCoptListener, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderCoptListener = require("apps/reader/modules/readercoptlistener")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
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

    doc:close()
  end)
end)
