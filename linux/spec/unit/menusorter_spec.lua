describe("MenuSorter module", function()
    local MenuSorter
    setup(function()
        require("commonrequire")
        MenuSorter = require("ui/menusorter")
    end)

    it("should put menu items in the defined order", function()
        local menu_items = {
            ["KOMenu:menu_buttons"] = {},
            main = {},
            search = {},
            tools = {},
            setting = {},
        }
        local order = {
            ["KOMenu:menu_buttons"] = {
                "setting",
                "tools",
                "search",
                "main",
            },
            main = {},
            search = {},
            tools = {},
            setting = {},
        }

        local test_menu = MenuSorter:sort(menu_items, order)

        assert.is_true(test_menu[1].id == "setting")
        assert.is_true(test_menu[2].id == "tools")
        assert.is_true(test_menu[3].id == "search")
        assert.is_true(test_menu[4].id == "main")
    end)
    it("should attach submenus correctly", function()
        local menu_items = {
            ["KOMenu:menu_buttons"] = {},
            first = {},
            second = {},
            third1 = {},
            third2 = {},
        }
        local order = {
            ["KOMenu:menu_buttons"] = {"first",},
            first = {"second"},
            second = {"third1", "third2"},
        }

        local test_menu = MenuSorter:sort(menu_items, order)

        assert.is_true(test_menu[1].id == "first")
        assert.is_true(test_menu[1][1].id == "second")
        assert.is_true(test_menu[1][1].sub_item_table[1].id == "third1")
        assert.is_true(test_menu[1][1].sub_item_table[2].id == "third2")
    end)
    it("should error if orphans do not have sorting_hint", function()
        local menu_items = {
            ["KOMenu:menu_buttons"] = {},
            main = {text="Main"},
            search = {text="Search"},
            tools = {text="Tools"},
            setting = {text="Settings"},
        }
        local order = {
            ["KOMenu:menu_buttons"] = {
                "setting",
            },
            setting = {},
        }

        assert.has_error(function()
            MenuSorter:sort(menu_items, order)
        end)
    end)
    it("should put orphans with sorting_hint in the right menu", function()
        local menu_items = {
            ["KOMenu:menu_buttons"] = {},
            main = {text="Main", sorting_hint="setting"},
            search = {text="Search", sorting_hint="tools",},
            tools = {text="Tools"},
            setting = {text="Settings"},
            submenu = {text="Submenu"},
            submenu_item1 = {text="Submenu item 1", sorting_hint="submenu",},
            submenu_item2 = {text="Submenu item 2"},
        }
        local order = {
            ["KOMenu:menu_buttons"] = {
                "setting",
            },
            tools = {},
            setting = {
                "tools",
                "submenu"
            },
            submenu = {
                "submenu_item2",
            },
        }

        local test_menu = MenuSorter:sort(menu_items, order)
        local result_menu = {
            [1] = {
                [1] = {
                    ["id"] = "tools",
                    ["sub_item_table"] = {
                        [1] = {
                            ["sorting_hint"] = "tools",
                            ["new"] = true,
                            ["id"] = "search",
                            ["text"] = "Search"
                        },
                        ["text"] = "Tools",
                        ["id"] = "tools"
                    },
                    ["text"] = "Tools"
                },
                [2] = {
                    ["id"] = "submenu",
                    ["sub_item_table"] = {
                        [1] = {
                            ["id"] = "submenu_item2",
                            ["text"] = "Submenu item 2"
                        },
                        [2] = {
                            ["sorting_hint"] = "submenu",
                            ["new"] = true,
                            ["id"] = "submenu_item1",
                            ["text"] = "Submenu item 1"
                        },
                        ["text"] = "Submenu",
                        ["id"] = "submenu"
                    },
                    ["text"] = "Submenu"
                },
                [3] = {
                    ["sorting_hint"] = "setting",
                    ["new"] = true,
                    ["text"] = "Main",
                    ["id"] = "main"
                },
                ["id"] = "setting",
                ["text"] = "Settings"
            },
            ["id"] = "KOMenu:menu_buttons"
        }

        assert.is_same(result_menu, test_menu)
    end)
    it("should display submenu of orphaned submenu", function()
        local menu_items = {
            ["KOMenu:menu_buttons"] = {},
            main = {text="Main", sorting_hint="setting"},
            search = {text="Search", sorting_hint="setting"},
            tools = {text="Tools", sorting_hint="setting"},
            setting = {text="Settings"},
            submenu = {text="Submenu", sorting_hint="setting"},
            submenu_item1 = {text="Submenu item 1"},
            submenu_item2 = {text="Submenu item 2"},
        }
        local order = {
            ["KOMenu:menu_buttons"] = {
                "setting",
            },
            setting = {},
            submenu = {
                "submenu_item2",
                "submenu_item1",
            },
        }

        local test_menu = MenuSorter:sort(menu_items, order)
        --- @fixme: Currently broken because pairs (c.f., https://github.com/koreader/koreader/pull/6371#issuecomment-657251137)
        --print(require("dump")(test_menu))

        -- all four should be in the first menu
        assert.is_true(#test_menu[1] == 4)
        assert.is_truthy(test_menu[1][3].sub_item_table)
        assert.equals(test_menu[1][3].sub_item_table[1].id, "submenu_item2")
        assert.equals(test_menu[1][3].sub_item_table[2].id, "submenu_item1")
    end)
    it("should not treat disabled as orphans", function()
        local menu_items = {
            ["KOMenu:menu_buttons"] = {},
            main = {text="Main"},
            search = {text="Search"},
            tools = {text="Tools", sorting_hint="setting"},
            setting = {text="Settings"},
        }
        local order = {
            ["KOMenu:menu_buttons"] = {
                "setting",
            },
            setting = {},
            ["KOMenu:disabled"] = {"main", "search"},
        }

        local test_menu = MenuSorter:sort(menu_items, order)

        -- only "tools" should be placed in the first menu
        assert.is_true(#test_menu[1] == 1)
        assert.is_true(test_menu[1][1].id == "tools")
    end)
    it("should attach separator=true to previous item", function()
        local menu_items = {
            ["KOMenu:menu_buttons"] = {},
            first = {},
            second = {},
            third1 = {},
            third2 = {},
        }
        local order = {
            ["KOMenu:menu_buttons"] = {"first",},
            first = {"second", "----------------------------", "third1", "----------------------------", "third2"},
        }

        local test_menu = MenuSorter:sort(menu_items, order)

        assert.is_true(test_menu[1].id == "first")
        assert.is_true(test_menu[1][1].id == "second")
        assert.is_true(test_menu[1][1].separator == true)
        assert.is_true(test_menu[1][2].id == "third1")
        assert.is_true(test_menu[1][2].separator == true)
        assert.is_true(test_menu[1][3].id == "third2")
    end)
    it("should ignore separator as first item", function()
        local menu_items = {
            ["KOMenu:menu_buttons"] = {},
            first = {},
            second = {},
            third1 = {},
            third2 = {},
        }
        local order = {
            ["KOMenu:menu_buttons"] = {"first",},
            first = {"----------------------------", "second", "third1", "----------------------------", "third2"},
        }

        local test_menu = MenuSorter:sort(menu_items, order)

        assert.is_true(test_menu[1].id == "first")
        assert.is_true(test_menu[1][1].id == "second")
        assert.is_nil(test_menu[1][1].separator)
        assert.is_true(test_menu[1][2].id == "third1")
        assert.is_true(test_menu[1][2].separator == true)
        assert.is_true(test_menu[1][3].id == "third2")
    end)
    it("should compress menus when items from order are missing", function()
        local menu_items = {
            ["KOMenu:menu_buttons"] = {},
            first = {},
            second = {},
            third2 = {},
            third4 = {},
        }
        local order = {
            ["KOMenu:menu_buttons"] = {"first",},
            first = {"second", "third1", "third2", "third3", "third4"},
        }

        local test_menu = MenuSorter:sort(menu_items, order)

        assert.is_true(test_menu[1].id == "first")
        assert.is_true(test_menu[1][1].id == "second")
        assert.is_true(test_menu[1][2].id == "third2")
        assert.is_true(test_menu[1][3].id == "third4")
    end)
end)
