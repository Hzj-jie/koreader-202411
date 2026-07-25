describe("ReaderKoptListener module", function()
  local ReaderKoptListener

  setup(function()
    require("commonrequire")
    ReaderKoptListener = require("apps/reader/modules/readerkoptlistener")
  end)

  it("should save settings using self.ui.doc_settings", function()
    local saved_key, saved_val
    local mock_ui = {
      doc_settings = {
        save = function(_self_ds, key, val)
          saved_key = key
          saved_val = val
        end,
      },
    }

    local listener = ReaderKoptListener:new({
      ui = mock_ui,
      normal_zoom_mode = "page",
    })

    assert.is_not_nil(listener)
    listener:onSaveSettings()
    assert.are.equal("normal_zoom_mode", saved_key)
    assert.are.equal("page", saved_val)
  end)
end)
