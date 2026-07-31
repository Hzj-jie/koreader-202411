describe("FindHistory plugin", function()
  local FindHistory

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    FindHistory = require("plugins/findhistory.koplugin/main")
  end)

  it("should initialize FindHistory plugin instance", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
    local fh = FindHistory:new({
      ui = mock_ui,
    })
    assert.is_table(fh)
  end)

  it("should register menu item in main menu", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
    local fh = FindHistory:new({
      ui = mock_ui,
    })

    local menu_items = {}
    fh:addToMainMenu(menu_items)
    assert.is_table(menu_items.findhistory)
    assert.is_string(menu_items.findhistory.text)
    assert.is_function(menu_items.findhistory.callback)
  end)

  it("should open MultiConfirmBox on menu callback", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
    local fh = FindHistory:new({
      ui = mock_ui,
    })

    local menu_items = {}
    fh:addToMainMenu(menu_items)

    -- Execute callback to ensure it constructs dialog without crashing
    menu_items.findhistory.callback()
  end)
end)
