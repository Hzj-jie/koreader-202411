describe("SimpleUI Plugin basic tests", function()
    local class, SimpleUI

    setup(function()
        require("commonrequire")
        package.unloadAll()
        require("document/canvascontext"):init(require("device"))
    end)

    teardown(function()
        package.unloadAll()
        require("document/canvascontext"):init(require("device"))
    end)

    it("should instantiate and initialize without crashing", function()
        local original_path = package.path
        package.path = "plugins/simpleui.koplugin/?.lua;" .. original_path

        class = dofile("plugins/simpleui.koplugin/main.lua")
        local mock_ui = {
            menu = {
                registerToMainMenu = function() end
            }
        }
        SimpleUI = class:new{ ui = mock_ui }

        -- Call init
        local ok, err = pcall(function()
            SimpleUI:init()
        end)

        package.path = original_path

        assert.is_true(ok, "Initialization failed: " .. tostring(err))
    end)
end)
