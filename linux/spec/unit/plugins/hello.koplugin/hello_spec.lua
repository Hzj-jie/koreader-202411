describe("Hello World plugin module", function()
  local Hello, HelloModule

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Hello = dofile("plugins/hello.koplugin/main.lua")

    -- Load active plugin definition by stripping early return guard
    local f = io.open("plugins/hello.koplugin/main.lua", "r")
    local code = f:read("*a")
    f:close()
    code = code:gsub("if true then%s+return %{ disabled = true %}%s+end", "")
    local fn = loadstring(code, "plugins/hello.koplugin/main.lua")
    HelloModule = fn()
  end)

  describe("Initialization & Defaults", function()
    it("should expose Hello plugin module or disabled state", function()
      assert.is_table(Hello)
      assert.is_true(Hello.disabled)

      assert.is_table(HelloModule)
      assert.are.equal("hello", HelloModule.name)
    end)

    it("should register actions and add to main menu", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local inst = HelloModule:new({ ui = mock_ui })

      inst:init()

      local menu_items = {}
      inst:addToMainMenu(menu_items)
      assert.is_table(menu_items.hello_world)
      assert.is_function(menu_items.hello_world.callback)
    end)

    it("should handle event callback for HelloWorld", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local inst = HelloModule:new({ ui = mock_ui })
      inst:onHelloWorld()
    end)
  end)
end)
