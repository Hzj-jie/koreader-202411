describe("ReaderPageMap module", function()
  local ReaderPageMap

  setup(function()
    require("commonrequire")
    ReaderPageMap = require("apps/reader/modules/readerpagemap")
  end)

  it("should initialize and register view module via self.ui.view", function()
    local registered_menu = false
    local registered_view = false

    local mock_ui = {
      menu = {
        registerToMainMenu = function()
          registered_menu = true
        end,
      },
      view = {
        registerViewModule = function(_self_view, _name, _module)
          registered_view = true
        end,
      },
      document = {
        info = { has_pages = false },
        hasPageMap = function()
          return true
        end,
      },
    }

    local pagemap = ReaderPageMap:new({
      ui = mock_ui,
    })

    assert.is_not_nil(pagemap)
    pagemap:_postInit()
    assert.is_true(registered_menu)
    assert.is_true(registered_view)
  end)
end)
