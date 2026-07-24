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
      read = function() return nil end,
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
