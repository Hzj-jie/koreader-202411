describe("Games submenu integration", function()
    local ReaderMenu, FileManagerMenu, MenuSorter, common_menu_order
    setup(function()
        require("commonrequire")
        package.unloadAll()
        local Device = require("device")
        if Device.powerd then
            Device.powerd.isChargingHW = function() return false end
            Device.powerd.getCapacityHW = function() return 0 end
        end
        require("document/canvascontext"):init(Device)
        ReaderMenu = require("apps/reader/modules/readermenu")
        FileManagerMenu = require("apps/filemanager/filemanagermenu")
        MenuSorter = require("ui/menusorter")
        common_menu_order = require("ui/elements/common_menu_order")
    end)

    it("verifies the Games submenu order exists in common_menu_order", function()
        local order = common_menu_order({})
        assert.is_table(order.games)
        local contains_games = false
        for _, v in ipairs(order.tools) do
            if v == "games" then
                contains_games = true
                break
            end
        end
        assert.is_true(contains_games)
    end)

    local function verify_games_hidden(MenuClass)
        local menu = MenuClass:new{
            ui = {
                document = {},
                menu = {
                    registerToMainMenu = function() end
                },
                file_chooser = {
                    collates = {}
                }
            }
        }
        menu.registered_widgets = {}
        local mock_calculator = {
            addToMainMenu = function(self, menu_items)
                menu_items.calculator = { text = "Calculator" }
            end
        }
        table.insert(menu.registered_widgets, mock_calculator)

        menu:setUpdateItemTable()

        local tools_menu = MenuSorter:findById(menu.tab_item_table, "tools")
        assert.is_not_nil(tools_menu)
        local calculator_item = MenuSorter:findById(tools_menu, "calculator")
        assert.is_not_nil(calculator_item)

        local games_item = MenuSorter:findById(tools_menu, "games")
        assert.is_nil(games_item)
    end

    local function verify_games_appears(MenuClass)
        local menu = MenuClass:new{
            ui = {
                document = {},
                menu = {
                    registerToMainMenu = function() end
                },
                file_chooser = {
                    collates = {}
                }
            }
        }
        menu.registered_widgets = {}
        local mock_solitaire = {
            addToMainMenu = function(self, menu_items)
                menu_items.solitaire = { text = "Solitaire" }
            end
        }
        table.insert(menu.registered_widgets, mock_solitaire)

        menu:setUpdateItemTable()

        local tools_menu = MenuSorter:findById(menu.tab_item_table, "tools")
        assert.is_not_nil(tools_menu)

        local games_item = MenuSorter:findById(tools_menu, "games")
        assert.is_not_nil(games_item)
        assert.are.equal("Games", games_item.text)

        local solitaire_item = MenuSorter:findById(games_item.sub_item_table, "solitaire")
        assert.is_not_nil(solitaire_item)
        assert.are.equal("Solitaire", solitaire_item.text)
    end

    it("verifies the Games submenu is hidden if no game plugins are registered in ReaderMenu", function()
        verify_games_hidden(ReaderMenu)
    end)

    it("verifies the Games submenu is hidden if no game plugins are registered in FileManagerMenu", function()
        verify_games_hidden(FileManagerMenu)
    end)

    it("verifies the Games submenu appears if a game plugin is registered in ReaderMenu", function()
        verify_games_appears(ReaderMenu)
    end)

    it("verifies the Games submenu appears if a game plugin is registered in FileManagerMenu", function()
        verify_games_appears(FileManagerMenu)
    end)

    it("verifies SolitaireUI onClose does not crash with stack overflow", function()
        local old_path = package.path
        package.path = package.path .. ";plugins/solitaire.koplugin/?.lua"
        local SolitaireUI = require("solitaireui")
        package.path = old_path

        local UIManager = require("ui/uimanager")

        -- Create a dummy game object
        local mock_game = {
            formatTime = function() return "00:00" end,
            toSaveData = function() return {} end,
            stopTimer = function() end,
            draw_mode = 1,
            moves = 0,
            score = 0,
        }

        local ui = SolitaireUI:new{
            game = mock_game,
            stats = { current_win_streak = 0 },
            settings_path = "/tmp/dummy_solitaire_settings.lua",
            save_path = "/tmp/dummy_solitaire_save.lua",
        }

        -- Register in UIManager stack
        UIManager:show(ui)

        -- Call onClose and close widget
        assert.has_no.errors(function()
            ui:onClose()
            UIManager:close(ui)
        end)
    end)
end)
