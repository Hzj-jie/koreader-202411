describe("LuaDefaults", function()
    local LuaDefaults
    local DataStorage
    local TEST_FILE

    setup(function()
        require("commonrequire")
        LuaDefaults = require("luadefaults")
        DataStorage = require("datastorage")
        TEST_FILE = DataStorage:getDataDir() .. "/defaults.spec_test.lua"
    end)

    before_each(function()
        os.remove(TEST_FILE)
    end)

    after_each(function()
        os.remove(TEST_FILE)
    end)

    describe("initialization and defaults", function()
        it("should correctly open defaults file and load defaults.lua as read-only", function()
            local defaults = LuaDefaults:open(TEST_FILE)
            assert.is_truthy(defaults)
            assert.are.same(TEST_FILE, defaults.file)

            local ro, rw = defaults:getDataTables()
            assert.is_truthy(ro)
            assert.is_truthy(rw)
            -- rw is a dictionary loaded from file; since file is deleted/absent, it should be empty
            assert.are.same(nil, next(rw))

            assert.are.same(1, ro.DHINTCOUNT)
            assert.is_false(ro.DSHOWOVERLAP)

            assert.are.same(1, defaults:readDefaultSetting("DHINTCOUNT"))
            assert.is_false(defaults:readDefaultSetting("DSHOWOVERLAP"))
        end)
    end)

    describe("reading settings", function()
        it("should read from ro defaults when no customization is set", function()
            local defaults = LuaDefaults:open(TEST_FILE)
            assert.are.same(1, defaults:read("DHINTCOUNT"))
            assert.is_false(defaults:read("DSHOWOVERLAP"))
        end)

        it("should write parameter default to rw table if not customized and return it", function()
            local defaults = LuaDefaults:open(TEST_FILE)
            assert.is_false(defaults:has("DNEW_KEY"))
            assert.is_false(defaults:hasBeenCustomized("DNEW_KEY"))

            local val = defaults:read("DNEW_KEY", "my_default_val")
            assert.are.same("my_default_val", val)
            assert.is_true(defaults:hasBeenCustomized("DNEW_KEY"))
            assert.are.same("my_default_val", defaults:read("DNEW_KEY"))
        end)

        it("should return custom rw value if key has been customized", function()
            local defaults = LuaDefaults:open(TEST_FILE)
            assert.are.same(1, defaults:read("DHINTCOUNT"))

            defaults.rw.DHINTCOUNT = 5
            assert.is_true(defaults:hasBeenCustomized("DHINTCOUNT"))
            assert.are.same(5, defaults:read("DHINTCOUNT"))
        end)
    end)

    describe("saving and deleting", function()
        it("should save customized key to rw table", function()
            local defaults = LuaDefaults:open(TEST_FILE)
            defaults:save("DHINTCOUNT", 10)
            assert.is_true(defaults:hasBeenCustomized("DHINTCOUNT"))
            assert.are.same(10, defaults:read("DHINTCOUNT"))
        end)

        it("should optimize out customization if it matches the default ro value", function()
            local defaults = LuaDefaults:open(TEST_FILE)
            defaults:save("DHINTCOUNT", 10)
            assert.is_true(defaults:hasBeenCustomized("DHINTCOUNT"))

            defaults:save("DHINTCOUNT", 1)
            assert.is_false(defaults:hasBeenCustomized("DHINTCOUNT"))
            assert.are.same(1, defaults:read("DHINTCOUNT"))
        end)

        it("should delete key from rw table and return back to ro default", function()
            local defaults = LuaDefaults:open(TEST_FILE)
            defaults:save("DHINTCOUNT", 10)
            assert.is_true(defaults:hasBeenCustomized("DHINTCOUNT"))

            defaults:delete("DHINTCOUNT")
            assert.is_false(defaults:hasBeenCustomized("DHINTCOUNT"))
            assert.are.same(1, defaults:read("DHINTCOUNT"))
        end)

        it("should correctly report customized status via helpers", function()
            local defaults = LuaDefaults:open(TEST_FILE)
            assert.is_true(defaults:hasNotBeenCustomized("DHINTCOUNT"))
            assert.is_false(defaults:hasBeenCustomized("DHINTCOUNT"))

            defaults:save("DHINTCOUNT", 10)
            assert.is_false(defaults:hasNotBeenCustomized("DHINTCOUNT"))
            assert.is_true(defaults:hasBeenCustomized("DHINTCOUNT"))
        end)
    end)

    describe("boolean helpers", function()
        it("should check true/false correctly with customization fallback", function()
            local defaults = LuaDefaults:open(TEST_FILE)
            assert.is_false(defaults:isTrue("DSHOWOVERLAP"))
            assert.is_true(defaults:isFalse("DSHOWOVERLAP"))

            defaults:save("DSHOWOVERLAP", true)
            assert.is_true(defaults:isTrue("DSHOWOVERLAP"))
            assert.is_false(defaults:isFalse("DSHOWOVERLAP"))
        end)
    end)

    describe("disk flushing", function()
        it("should write customizations to file on flush and load them back", function()
            local defaults = LuaDefaults:open(TEST_FILE)
            defaults:save("DHINTCOUNT", 5)
            defaults:save("DSHOWOVERLAP", true)
            defaults:flush()

            local defaults2 = LuaDefaults:open(TEST_FILE)
            assert.is_true(defaults2:hasBeenCustomized("DHINTCOUNT"))
            assert.are.same(5, defaults2:read("DHINTCOUNT"))
            assert.is_true(defaults2:isTrue("DSHOWOVERLAP"))
        end)
    end)
end)
