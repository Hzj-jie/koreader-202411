describe("LibLipcs module", function()
    setup(function()
        require("commonrequire")
    end)

    before_each(function()
        -- Ensure we start with a clean state and unload liblipcs
        package.loaded["liblipcs"] = nil
        package.loaded["liblipclua"] = nil
        package.loaded["libopenlipclua"] = nil
    end)

    after_each(function()
        package.loaded["liblipclua"] = nil
        package.loaded["libopenlipclua"] = nil
        package.loaded["liblipcs"] = nil
    end)

    describe("Without Lipc Support (Default Linux)", function()
        local LibLipcs
        before_each(function()
            -- liblipclua is not available, so require("liblipcs") will load in fake mode
            LibLipcs = require("liblipcs")
        end)

        it("should not be supported", function()
            assert.is_false(LibLipcs:supported())
        end)

        it("accessor should return Fake", function()
            local accessor = LibLipcs:accessor()
            assert.truthy(accessor)
            assert.is_true(LibLipcs:isFake(accessor))
        end)

        it("hash_accessor should return Fake", function()
            local accessor = LibLipcs:hash_accessor()
            assert.truthy(accessor)
            assert.is_true(LibLipcs:isFake(accessor))
        end)

        it("Fake methods should be safe to call", function()
            local Fake = LibLipcs:accessor()
            -- Should not crash, just return nil or do nothing
            assert.is_nil(Fake:get_string_property())
            assert.is_nil(Fake:set_string_property())
            assert.is_nil(Fake:get_int_property())
            assert.is_nil(Fake:set_int_property())
            assert.is_nil(Fake:access_hash_property())
            assert.is_nil(Fake:new_hasharray())
            assert.is_nil(Fake:register_int_property())
            assert.is_nil(Fake:close())
            assert.is_nil(Fake:read_hash_property())
        end)
    end)

    describe("With Lipc Support (Mocked)", function()
        local LibLipcs
        local mock_lipc_handle
        local mock_openlipc_handle
        local mock_hasharray_input
        local mock_hasharray_result
        local input_destroyed = false
        local result_destroyed = false
        local access_hash_property_called = false

        before_each(function()
            input_destroyed = false
            result_destroyed = false
            access_hash_property_called = false

            -- Setup mock hasharrays
            mock_hasharray_input = {
                destroy = function() input_destroyed = true end
            }
            mock_hasharray_result = {
                to_table = function() return { key = "value" } end,
                destroy = function() result_destroyed = true end
            }

            -- Setup mock handles
            mock_lipc_handle = {
                get_string_property = function(self, prop)
                    if prop == "valid_prop" then
                        return "hello"
                    elseif prop == "error_prop" then
                        error("lipc error")
                    end
                end,
                set_string_property = function(self, prop, _)
                    if prop == "error_prop" then
                        error("lipc error")
                    end
                end,
                new_hasharray = function()
                    return mock_hasharray_input
                end,
                access_hash_property = function(self, _, _, input)
                    access_hash_property_called = true
                    assert.are.equal(mock_hasharray_input, input)
                    return mock_hasharray_result
                end
            }

            mock_openlipc_handle = {
                get_int_property = function(self, _)
                    return 42
                end
            }

            -- Pre-populate package.loaded to simulate library availability
            package.loaded["liblipclua"] = {
                init = function(name)
                    assert.are.equal("com.github.koreader", name)
                    return mock_lipc_handle
                end
            }
            package.loaded["libopenlipclua"] = {
                open_no_name = function()
                    return mock_openlipc_handle
                end
            }

            LibLipcs = require("liblipcs")
        end)

        it("should be supported", function()
            assert.is_true(LibLipcs:supported())
        end)

        it("accessor should return wrapped mock handle", function()
            local accessor = LibLipcs:accessor()
            assert.truthy(accessor)
            assert.is_false(LibLipcs:isFake(accessor))

            -- Test wrapped methods
            assert.are.equal("hello", accessor:get_string_property("valid_prop"))
            assert.is_nil(accessor:get_string_property("error_prop")) -- should handle error gracefully

            -- Test set (should not crash even if it errors internally due to pcall wrapper)
            accessor:set_string_property("valid_prop", "world")
            accessor:set_string_property("error_prop", "world")
        end)

        it("hash_accessor should return wrapped mock handle", function()
            local accessor = LibLipcs:hash_accessor()
            assert.truthy(accessor)
            assert.is_false(LibLipcs:isFake(accessor))

            assert.are.equal(42, accessor:get_int_property("some_prop"))
        end)

        it("should support read_hash_property with correct lifecycle", function()
            local accessor = LibLipcs:accessor()
            local t = accessor:read_hash_property("pub", "prop")

            assert.is_true(access_hash_property_called)
            assert.are.same({ key = "value" }, t)
            assert.is_true(input_destroyed)
            assert.is_true(result_destroyed)
        end)
    end)
end)
