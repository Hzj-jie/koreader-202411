describe("PluginLoader module", function()
    local PluginLoader
    local lfs
    local orig_dir, orig_attributes, orig_dofile
    local orig_read, orig_readTableRef
    local mock_disabled_plugins = {}
    local mock_extra_paths = nil
    local mock_files_exist = {}

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
                local list = { "mock1.koplugin", "mock2.koplugin", "zsync.koplugin", ".", ".." }
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
            local mock_ret
            if string.find(path_str, "mock1.koplugin") or
               string.find(path_str, "mock2.koplugin") or
               string.find(path_str, "zsync.koplugin") or
               string.find(path_str, "extra1.koplugin") then
                if request == "mode" or not request then
                    if string.match(path_str, "%.koplugin$") or path_str == "/extra/plugins" then
                        mock_ret = "directory"
                    elseif string.find(path_str, "README.koreader-202411.md", 1, true) then
                        mock_ret = mock_files_exist[path_str] and "file" or nil
                    else
                        mock_ret = "file"
                    end
                end
            elseif path_str == "/extra/plugins" then
                if request == "mode" or not request then
                    mock_ret = "directory"
                end
            end
            local final_ret = mock_ret
            if final_ret == nil then
                final_ret = orig_attributes(path, request)
            end
            return final_ret
        end

        -- Mock dofile
        _G.dofile = function(path)
            local path_str = tostring(path)
            if string.find(path_str, "mock1.koplugin") then
                if string.find(path_str, "main.lua") then
                    return {
                        name = "Mock1",
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
                        fullname = "Mock 1 Plugin",
                        description = "Description for Mock 1",
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
        PluginLoader.loaded_plugins = {}
        PluginLoader.all_plugins = nil
        mock_disabled_plugins = {}
        mock_extra_paths = nil
        mock_files_exist = {}
    end)

    describe("loadPlugins", function()
        it("should load enabled plugins and ignore obsolete ones", function()
            local enabled, disabled = PluginLoader:loadPlugins()
            assert.truthy(enabled)
            assert.truthy(disabled)

            -- Should load mock1 and mock2 (both enabled by default)
            -- Obsolete should be ignored
            assert.are.equal(2, #enabled)
            assert.are.equal(0, #disabled)

            local names = {}
            for _, p in ipairs(enabled) do
                names[p.name] = p
            end
            assert.truthy(names["Mock1"])
            assert.truthy(names["Mock2"])
            assert.are.equal("Mock 1 Plugin", names["Mock1"].fullname)
        end)

        it("should handle disabled plugins", function()
            mock_disabled_plugins["mock2"] = true

            local enabled, disabled = PluginLoader:loadPlugins()
            assert.are.equal(1, #enabled)
            assert.are.equal(1, #disabled)

            assert.are.equal("Mock1", enabled[1].name)
            -- Disabled plugin module is the meta module in our mock
            assert.are.equal("Mock 2 Plugin (Disabled)", disabled[1].fullname)
        end)

        it("should load plugins from extra_plugin_paths", function()
            mock_extra_paths = "/extra/plugins"

            local enabled, disabled = PluginLoader:loadPlugins()
            -- mock1, mock2, and extra1
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
            PluginLoader:loadPlugins()
        end)

        it("should create and manage plugin instances", function()
            local plugin_class = PluginLoader.enabled_plugins[1] -- Mock1
            assert.are.equal("Mock1", plugin_class.name)

            assert.is_false(PluginLoader:isPluginLoaded("Mock1"))
            assert.is_nil(PluginLoader:getPluginInstance("Mock1"))

            local success, instance = PluginLoader:createPluginInstance(plugin_class, { attr1 = "val1" })
            assert.is_true(success)
            assert.truthy(instance)
            assert.are.equal("val1", instance.attr1)

            -- PluginLoader:createPluginInstance doesn't automatically register it in loaded_plugins,
            -- it seems. Let's check how it is registered.
            -- In pluginloader.lua, loaded_plugins is just initialized to {} and finalized to {}.
            -- Wait, where is loaded_plugins populated?
            -- Let's check pluginloader.lua again.
            -- Ah, loaded_plugins is NOT populated in createPluginInstance!
            -- Let's search where loaded_plugins is populated in the codebase.
        end)
    end)

    describe("genPluginManagerSubItem", function()
        it("should generate menu items for plugins", function()
            mock_disabled_plugins["mock2"] = true
            local menu = PluginLoader:genPluginManagerSubItem()
            assert.truthy(menu)
            -- mock1 and mock2 should be in the menu
            assert.are.equal(2, #menu)

            -- They should be sorted by fullname
            -- "Mock 1 Plugin" vs "Mock 2 Plugin (Disabled)"
            assert.are.equal("Mock 1 Plugin", menu[1].text)
            assert.are.equal("Mock 2 Plugin (Disabled)", menu[2].text)

            assert.is_true(menu[1].checked_func())
            assert.is_false(menu[2].checked_func())
        end)
    end)

    describe("default-disable via versioned README", function()
        it("should dynamically disable plugin by default when README exists on first start", function()
            -- Simulate README exists
            mock_files_exist["plugins/mock1.koplugin/README.koreader-202411.md"] = true

            local enabled, disabled = PluginLoader:loadPlugins()
            assert.are.equal(1, #enabled)
            assert.are.equal(1, #disabled)
            assert.are.equal("Mock2", enabled[1].name)
            assert.are.equal("mock1", disabled[1].name)
        end)

        it("should preserve enabled status when toggled to true/enabled by user", function()
            -- Simulate README exists
            mock_files_exist["plugins/mock1.koplugin/README.koreader-202411.md"] = true

            -- 1. Initial start: plugin is disabled by default
            local enabled, disabled = PluginLoader:loadPlugins()
            assert.are.equal(1, #disabled)
            assert.are.equal("mock1", disabled[1].name)

            -- 2. Simulate User toggles it to enable in the Plugin Manager
            local menu = PluginLoader:genPluginManagerSubItem()
            -- menu[1] is Mock1 (since it is sorted: "Mock 1 Plugin" vs "Mock 2 Plugin")
            assert.are.equal("Mock 1 Plugin", menu[1].text)
            assert.is_false(menu[1].checked_func()) -- Currently disabled
            
            -- Trigger the toggle callback
            menu[1].callback()

            -- The toggle should set it to false (meaning not disabled) in G_reader_settings
            assert.is_false(mock_disabled_plugins["mock1"])

            -- 3. Reset loader state for next startup simulation
            PluginLoader.enabled_plugins = nil
            PluginLoader.disabled_plugins = nil
            PluginLoader.loaded_plugins = {}
            PluginLoader.all_plugins = nil

            -- 4. Next start: should load as enabled because state is false (not nil)
            local new_enabled, new_disabled = PluginLoader:loadPlugins()
            assert.are.equal(2, #new_enabled)
            assert.are.equal(0, #new_disabled)

            local names = {}
            for _, p in ipairs(new_enabled) do
                names[p.name] = true
            end
            assert.is_true(names["Mock1"])
            assert.is_true(names["Mock2"])
        end)
    end)
end)
