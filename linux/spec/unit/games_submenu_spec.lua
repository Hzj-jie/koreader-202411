describe("Games submenu integration", function()
    local ReaderMenu, MenuSorter, common_menu_order
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

    it("verifies the Games submenu is hidden if no game plugins are registered", function()
        local reader_menu = ReaderMenu:new{
            ui = {
                document = {},
                menu = {
                    registerToMainMenu = function() end
                }
            }
        }
        reader_menu.registered_widgets = {}
        -- No game widgets are registered, but say we have calculator
        local mock_calculator = {
            addToMainMenu = function(self, menu_items)
                menu_items.calculator = { text = "Calculator" }
            end
        }
        table.insert(reader_menu.registered_widgets, mock_calculator)

        reader_menu:setUpdateItemTable()

        -- Retrieve the sorted tools menu items
        local tools_menu = MenuSorter:findById(reader_menu.tab_item_table, "tools")
        assert.is_not_nil(tools_menu)
        -- Calculator should be present
        local calculator_item = MenuSorter:findById(tools_menu, "calculator")
        assert.is_not_nil(calculator_item)

        -- Games submenu should NOT be present (since it's empty and hidden!)
        local games_item = MenuSorter:findById(tools_menu, "games")
        assert.is_nil(games_item)
    end)

    it("verifies the Games submenu appears if a game plugin is registered", function()
        local reader_menu = ReaderMenu:new{
            ui = {
                document = {},
                menu = {
                    registerToMainMenu = function() end
                }
            }
        }
        reader_menu.registered_widgets = {}

        -- Mock a solitaire game plugin registering itself
        local mock_solitaire = {
            addToMainMenu = function(self, menu_items)
                menu_items.solitaire = { text = "Solitaire" }
            end
        }
        table.insert(reader_menu.registered_widgets, mock_solitaire)

        reader_menu:setUpdateItemTable()

        local tools_menu = MenuSorter:findById(reader_menu.tab_item_table, "tools")
        assert.is_not_nil(tools_menu)

        -- Games submenu SHOULD be present now!
        local games_item = MenuSorter:findById(tools_menu, "games")
        assert.is_not_nil(games_item)
        assert.are.equal("Games", games_item.text)

        -- Solitaire should be inside the Games submenu!
        local solitaire_item = MenuSorter:findById(games_item.sub_item_table, "solitaire")
        assert.is_not_nil(solitaire_item)
        assert.are.equal("Solitaire", solitaire_item.text)
    end)
end)
