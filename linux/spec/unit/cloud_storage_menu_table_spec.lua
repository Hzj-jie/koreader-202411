describe("Cloud Storage Menu Table Spec", function()
  local CloudStorageMenuTable
  local UIManager

  setup(function()
    require("commonrequire")
    UIManager = require("ui/uimanager")
    CloudStorageMenuTable = require("ui/elements/cloud_storage_menu_table")
  end)

  it("should provide cloud storage menu table and callback", function()
    assert.is_table(CloudStorageMenuTable)
    assert.is_string(CloudStorageMenuTable.text)
    assert.is_function(CloudStorageMenuTable.callback)

    local shown_widget
    local closed_widget
    local orig_show = UIManager.show
    local orig_close = UIManager.close
    UIManager.show = function(self, w)
      shown_widget = w
    end
    UIManager.close = function(self, w)
      closed_widget = w
    end

    CloudStorageMenuTable.callback()
    assert.is_table(shown_widget)
    assert.is_function(shown_widget.onExit)

    shown_widget:onExit()
    assert.are_equal(shown_widget, closed_widget)

    UIManager.show = orig_show
    UIManager.close = orig_close
  end)
end)
