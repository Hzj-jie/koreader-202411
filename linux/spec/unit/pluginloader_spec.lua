describe("PluginLoader module", function()
    local PluginLoader
    local lfs
    local orig_dir, orig_attributes, orig_dofile
    local orig_read, orig_readTableRef
    local mock_disabled_plugins = {}
    local mock_extra_paths = nil

    setup(function()
        require("commonrequire")
        PluginLoader = require("pluginloader")
        lfs = require("libs/libkoreader-lfs")

        orig_dir = lfs.dir
        orig_attributes = lfs.attributes
        orig_dofile = _G.dofile
        orig_read = G_reader_settings.read
        orig_readTableRef = G_reader_settings.readTableRef

        -- Mock lfs.dir
        lfs.dir = function(path)
            if path == "plugins" then
                local list = { "checkers.koplugin", "mock2.koplugin", "zsync.koplugin", ".", ".." }
                local i = 0
                return function()
                    i = i + 1
                    return list[i]
                end
            elseif path == "/extra/plugins" then
                local list = { "extra1.koplugin", ".", ".." }
                local i = 0
                return function()
                    i = i + 1
                    return list[i]
                end
            end
            return orig_dir(path)
        end

        -- Mock lfs.attributes
        lfs.attributes = function(path, request)
            local path_str = tostring(path)
            if string.find(path_str, "checkers.koplugin") or
               string.find(path_str, "mock2.koplugin") or
               string.find(path_str, "zsync.koplugin") or
               string.find(path_str, "extra1.koplugin") then
                if request == "mode" or not request then
                    if string.match(path_str, "%.koplugin$") or path_str == "/extra/plugins" then
                        return "directory"
                    else
                        return "file"
                    end
                end
            elseif path_str == "/extra/plugins" then
                if request == "mode" or not request then
                    return "directory"
                end
            end
            return orig_attributes(path, request)
        end

        -- Mock dofile
        _G.dofile = function(path)
            local path_str = tostring(path)
            if string.find(path_str, "checkers.koplugin") then
                if string.find(path_str, "main.lua") then
                    return {
                        name = "checkers",
                        disabled = false,
                        new = function(self, o)
                            o = o or {}
                            setmetatable(o, self)
                            self.__index = self
                            return o
                        end,
                    }
                elseif string.find(path_str, "_meta.lua") then
                    return {
                        fullname = "Checkers Game",
                        description = "Classic checkers board game",
                    }
                end
            elseif string.find(path_str, "mock2.koplugin") then
                -- mock2 might be loaded as meta if disabled
                if string.find(path_str, "main.lua") or string.find(path_str, "_meta.lua") then
                    if mock_disabled_plugins["mock2"] and string.find(path_str, "_meta.lua") then
                        return {
                            fullname = "Mock 2 Plugin (Disabled)",
                            description = "Description for Mock 2 (Disabled)",
                        }
                    end
                    return {
                        name = "Mock2",
                        disabled = false,
                        new = function(self, o)
                            o = o or {}
                            setmetatable(o, self)
                            self.__index = self
                            return o
                        end,
                    }
                end
            elseif string.find(path_str, "extra1.koplugin") then
                if string.find(path_str, "main.lua") then
                    return {
                        name = "Extra1",
                        disabled = false,
                    }
                elseif string.find(path_str, "_meta.lua") then
                    return {
                        fullname = "Extra 1 Plugin",
                        description = "Description for Extra 1",
                    }
                end
            end
            return orig_dofile(path)
        end

        -- Mock G_reader_settings
        G_reader_settings.read = function(self, key)
            if key == "extra_plugin_paths" then
                return mock_extra_paths
            end
            return orig_read(self, key)
        end

        G_reader_settings.readTableRef = function(self, key)
            if key == "plugins_disabled" then
                return mock_disabled_plugins
            end
            return orig_readTableRef(self, key)
        end
    end)

    teardown(function()
        lfs.dir = orig_dir
        lfs.attributes = orig_attributes
        _G.dofile = orig_dofile
        G_reader_settings.read = orig_read
        G_reader_settings.readTableRef = orig_readTableRef
    end)

    before_each(function()
        -- Reset PluginLoader state
        PluginLoader.enabled_plugins = nil
        PluginLoader.disabled_plugins = nil
        PluginLoader.all_plugins = nil
        PluginLoader.show_info = true
        mock_disabled_plugins = {}
        mock_extra_paths = nil
    end)

    describe("loadPlugins", function()
        it("should load enabled plugins and ignore obsolete ones", function()
            mock_disabled_plugins["checkers"] = false
            local enabled, disabled = PluginLoader:loadPlugins()
            assert.truthy(enabled)
            assert.truthy(disabled)

            -- Should load checkers and mock2 (both enabled by default/settings)
            -- Obsolete should be ignored
            assert.are.equal(2, #enabled)
            assert.are.equal(0, #disabled)

            local names = {}
            for _, p in ipairs(enabled) do
                names[p.name] = p
            end
            assert.truthy(names["checkers"])
            assert.truthy(names["Mock2"])
            assert.are.equal("Checkers Game", names["checkers"].fullname)
        end)

        it("should handle disabled plugins", function()
            mock_disabled_plugins["checkers"] = false
            mock_disabled_plugins["mock2"] = true

            local enabled, disabled = PluginLoader:loadPlugins()
            assert.are.equal(1, #enabled)
            assert.are.equal(1, #disabled)

            assert.are.equal("checkers", enabled[1].name)
            -- Disabled plugin module is the meta module in our mock
            assert.are.equal("Mock 2 Plugin (Disabled)", disabled[1].fullname)
        end)

        it("should load plugins from extra_plugin_paths", function()
            mock_disabled_plugins["checkers"] = false
            mock_extra_paths = "/extra/plugins"

            local enabled, disabled = PluginLoader:loadPlugins()
            -- checkers, mock2, and extra1
            assert.are.equal(3, #enabled)

            local found_extra = false
            for _, p in ipairs(enabled) do
                if p.name == "Extra1" then
                    found_extra = true
                    assert.are.equal("Extra 1 Plugin", p.fullname)
                end
            end
            assert.is_true(found_extra)
        end)
    end)

    describe("Plugin Lifecycle and Instance Management", function()
        before_each(function()
            mock_disabled_plugins["checkers"] = false
            PluginLoader:loadPlugins()
        end)

        it("should create plugin instances", function()
            local plugin_class = PluginLoader.enabled_plugins[1] -- checkers
            assert.are.equal("checkers", plugin_class.name)

            local success, instance = PluginLoader:createPluginInstance(plugin_class, { attr1 = "val1" })
            assert.is_true(success)
            assert.truthy(instance)
            assert.are.equal("val1", instance.attr1)
        end)
    end)

    describe("genPluginManagerSubItem", function()
        it("should generate menu items for plugins", function()
            mock_disabled_plugins["checkers"] = false
            mock_disabled_plugins["mock2"] = true
            local menu = PluginLoader:genPluginManagerSubItem()
            assert.truthy(menu)
            -- checkers and mock2 should be in the menu
            assert.are.equal(2, #menu)

            -- They should be sorted by fullname
            -- "Checkers Game" vs "Mock 2 Plugin (Disabled)"
            assert.are.equal("Checkers Game", menu[1].text)
            assert.are.equal("Mock 2 Plugin (Disabled)", menu[2].text)

            assert.is_true(menu[1].checked_func())
            assert.is_false(menu[2].checked_func())
        end)
    end)

    describe("default-disable via list", function()
        it("should dynamically disable plugin by default when present in default disabled list on first start", function()
            local enabled, disabled = PluginLoader:loadPlugins()
            assert.are.equal(1, #enabled)
            assert.are.equal(1, #disabled)
            assert.are.equal("Mock2", enabled[1].name)
            assert.are.equal("checkers", disabled[1].name)
        end)

        it("should preserve enabled status when toggled to true/enabled by user", function()
            -- 1. Initial start: plugin is disabled by default
            local enabled, disabled = PluginLoader:loadPlugins()
            assert.are.equal(1, #disabled)
            assert.are.equal("checkers", disabled[1].name)

            -- 2. Simulate User toggles it to enable in the Plugin Manager
            local menu = PluginLoader:genPluginManagerSubItem()
            -- menu[1] is checkers (since it is sorted: "Checkers Game" vs "Mock2")
            assert.are.equal("Checkers Game", menu[1].text)
            assert.is_false(menu[1].checked_func()) -- Currently disabled

            -- Trigger the toggle callback
            menu[1].callback()

            -- The toggle should set it to false (meaning not disabled) in G_reader_settings
            assert.is_false(mock_disabled_plugins["checkers"])

            -- 3. Reset loader state for next startup simulation
            PluginLoader.enabled_plugins = nil
            PluginLoader.disabled_plugins = nil
            PluginLoader.all_plugins = nil

            -- 4. Next start: should load as enabled because state is false (not nil)
            local new_enabled, new_disabled = PluginLoader:loadPlugins()
            assert.are.equal(2, #new_enabled)
            assert.are.equal(0, #new_disabled)

            local names = {}
            for _, p in ipairs(new_enabled) do
                names[p.name] = true
            end
            assert.is_true(names["checkers"])
            assert.is_true(names["Mock2"])
        end)
    end)

    describe("Settings Storage and Defaults", function()
        local orig_ask
        local UIManager

        setup(function()
            UIManager = require("ui/uimanager")
            orig_ask = UIManager.askForRestart
            UIManager.askForRestart = function() end
        end)

        teardown(function()
            UIManager.askForRestart = orig_ask
        end)

        it("should respect DEFAULT_DISABLED_PLUGINS and store nil if value matches default", function()
            -- Reset all_plugins cache first
            PluginLoader.all_plugins = nil
            PluginLoader.enabled_plugins = nil
            PluginLoader.disabled_plugins = nil

            -- 1. Initialize enabled mock2, disabled checkers
            mock_disabled_plugins["checkers"] = true
            mock_disabled_plugins["mock2"] = nil -- nil means default (enabled)

            local menu_items = PluginLoader:genPluginManagerSubItem()
            local checkers_item, mock2_item
            for _, item in ipairs(menu_items) do
                if item.text == "Checkers Game" then
                    checkers_item = item
                elseif item.text == "Mock 2 Plugin" then
                    mock2_item = item
                elseif item.text == "Mock2" then
                    mock2_item = item
                end
            end
            assert.truthy(checkers_item)
            assert.truthy(mock2_item)

            -- Toggle mock2 to disabled (custom disable) -> should store true
            mock2_item.callback()
            assert.is_true(mock_disabled_plugins["mock2"])

            -- Toggle mock2 back to enabled (default state) -> should store nil
            mock2_item.callback()
            assert.is_nil(mock_disabled_plugins["mock2"])

            -- Toggle checkers to enabled (custom enable) -> should store false
            checkers_item.callback()
            assert.is_false(mock_disabled_plugins["checkers"])

            -- Toggle checkers back to disabled (default state) -> should store nil
            checkers_item.callback()
            assert.is_nil(mock_disabled_plugins["checkers"])
        end)
    end)
end)
