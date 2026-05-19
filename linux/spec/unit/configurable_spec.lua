describe("Configurable", function()
    local Configurable
    local original_G_reader_settings

    setup(function()
        require("commonrequire")
        Configurable = require("configurable")
        original_G_reader_settings = G_reader_settings
    end)

    teardown(function()
        G_reader_settings = original_G_reader_settings
    end)

    describe("new", function()
        it("should create a new Configurable instance", function()
            local conf = Configurable:new()
            assert.is_truthy(conf)
            assert.are.equal(Configurable, getmetatable(conf).__index)
        end)

        it("should inherit properties passed to new", function()
            local conf = Configurable:new({ key = "value" })
            assert.are.equal("value", conf.key)
        end)
    end)

    describe("hash", function()
        it("should insert only string and number values in sorted order", function()
            local conf = Configurable:new({
                c_num = 42,
                a_str = "hello",
                b_bool = true,
                d_tbl = { 1, 2 },
                e_func = function() end,
            })
            local list = {}
            conf:hash(list)

            -- sorted keys: a_str, b_bool, c_num, d_tbl, e_func
            -- only a_str (string) and c_num (number) should be inserted
            assert.are.same({ "hello", 42 }, list)
        end)
    end)

    describe("loadDefaults", function()
        local config_options

        before_each(function()
            config_options = {
                prefix = "test_pref",
                {
                    options = {
                        { name = "opt1", default_value = "default1" },
                        { name = "opt2", default_value = 2 },
                        { name = "opt3", default_value = { val = 3 } },
                        { name = "opt_nil", default_value = nil }, -- should be ignored
                    }
                }
            }
        end)

        it("should load defaults from config_options when G_reader_settings does not have them", function()
            local original_has = G_reader_settings.has
            G_reader_settings.has = function() return false end

            local conf = Configurable:new()
            conf:loadDefaults(config_options)

            G_reader_settings.has = original_has

            assert.are.equal("default1", conf.opt1)
            assert.are.equal(2, conf.opt2)
            assert.are.same({ val = 3 }, conf.opt3)
            assert.is_nil(conf.opt_nil)

            -- Verify self.defaults is a deep copy
            assert.is_truthy(conf.defaults)
            assert.are.equal("default1", conf.defaults.opt1)
            assert.are.equal(2, conf.defaults.opt2)
            assert.are.same({ val = 3 }, conf.defaults.opt3)
            -- check deep copy
            conf.opt3.val = 99
            assert.are.equal(3, conf.defaults.opt3.val)
        end)

        it("should load values from G_reader_settings when they exist", function()
            local mock_settings = {
                test_pref_opt1 = "saved1",
                test_pref_opt2 = 20,
                test_pref_opt3 = { val = 30 },
            }

            local original_has = G_reader_settings.has
            local original_read = G_reader_settings.read
            local original_readTableRef = G_reader_settings.readTableRef

            G_reader_settings.has = function(self, key)
                return mock_settings[key] ~= nil
            end
            G_reader_settings.read = function(self, key)
                return mock_settings[key]
            end
            G_reader_settings.readTableRef = function(self, key)
                return mock_settings[key]
            end

            local conf = Configurable:new()
            conf:loadDefaults(config_options)

            G_reader_settings.has = original_has
            G_reader_settings.read = original_read
            G_reader_settings.readTableRef = original_readTableRef

            assert.are.equal("saved1", conf.opt1)
            assert.are.equal(20, conf.opt2)
            assert.are.same({ val = 30 }, conf.opt3)

            -- Verify self.defaults matches what was loaded (which includes the saved values)
            assert.are.equal("saved1", conf.defaults.opt1)
            assert.are.equal(20, conf.defaults.opt2)
            assert.are.same({ val = 30 }, conf.defaults.opt3)
        end)
    end)

    describe("loadSettings", function()
        it("should load settings from provided settings object with prefix", function()
            local mock_settings_data = {
                pref_opt1 = "loaded1",
                pref_opt2 = 200,
                pref_opt3 = { val = 300 },
            }

            local mock_settings = {
                has = function(self, key)
                    return mock_settings_data[key] ~= nil
                end,
                read = function(self, key)
                    return mock_settings_data[key]
                end,
                readTableRef = function(self, key)
                    return mock_settings_data[key]
                end
            }

            local conf = Configurable:new({
                opt1 = "default1",
                opt2 = 2,
                opt3 = { val = 3 },
            })

            conf:loadSettings(mock_settings, "pref_")

            assert.are.equal("loaded1", conf.opt1)
            assert.are.equal(200, conf.opt2)
            assert.are.same({ val = 300 }, conf.opt3)
        end)

        it("should assert if loaded value is nil", function()
            local mock_settings = {
                has = function() return true end,
                read = function() return nil end, -- returns nil even if has is true
            }

            local conf = Configurable:new({
                opt1 = "default1",
            })

            assert.has_error(function()
                conf:loadSettings(mock_settings, "pref_")
            end)
        end)
    end)

    describe("saveSettings", function()
        it("should save settings to provided settings object with prefix and defaults", function()
            local saved_data = {}
            local mock_settings = {
                save = function(self, key, value, default)
                    saved_data[key] = { value = value, default = default }
                end
            }

            local conf = Configurable:new({
                opt1 = "val1",
                opt2 = 22,
                opt3 = { val = 33 },
                defaults = {
                    opt1 = "default1",
                    opt2 = 2,
                    opt3 = { val = 3 },
                }
            })

            conf:saveSettings(mock_settings, "pref_")

            assert.are.same({
                pref_opt1 = { value = "val1", default = "default1" },
                pref_opt2 = { value = 22, default = 2 },
                pref_opt3 = { value = { val = 33 }, default = { val = 3 } },
            }, saved_data)
        end)

        it("should ignore keys that are not string, number, or table", function()
            local saved_data = {}
            local mock_settings = {
                save = function(self, key, value, default)
                    saved_data[key] = { value = value, default = default }
                end
            }

            local conf = Configurable:new({
                opt1 = "val1",
                opt_bool = true, -- should assert/error in saveSettings if it tries to save it
                defaults = {
                    opt1 = "default1",
                    opt_bool = false,
                }
            })

            -- configurable.lua:83 has assert(false) for non-string/number/table
            assert.has_error(function()
                conf:saveSettings(mock_settings, "pref_")
            end)
        end)
    end)
end)
