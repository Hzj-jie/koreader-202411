describe("MoveToArchive main plugin module", function()
  local MoveToArchive

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    MoveToArchive = require("plugins/movetoarchive.koplugin/main")
  end)

  it("should initialize MoveToArchive plugin and register actions", function()
    local mock_menu = { registerToMainMenu = function() end }
    local instance = MoveToArchive:new({ ui = { menu = mock_menu } })
    assert.is_table(instance)
    assert.are.equal("movetoarchive", instance.name)

    local menu_items = {}
    if type(instance.addToMainMenu) == "function" then
      instance:addToMainMenu(menu_items)
      assert.is_table(menu_items.move_to_archive)
    end

    if type(instance.onDispatcherRegisterActions) == "function" then
      instance:onDispatcherRegisterActions()
    end
  end)
end)
