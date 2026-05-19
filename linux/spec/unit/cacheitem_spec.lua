describe("cacheitem", function()
    local CacheItem

    setup(function()
        require("commonrequire")
        CacheItem = require("cacheitem")
    end)

    it("should have default size", function()
        assert.are.equal(128, CacheItem.size)
    end)

    it("should extend correctly using extend()", function()
        local MyItem = CacheItem:extend({
            size = 256,
            custom_prop = "custom",
        })
        assert.are.equal(256, MyItem.size)
        assert.are.equal("custom", MyItem.custom_prop)
        
        local instance = MyItem:new()
        assert.are.equal(256, instance.size)
        assert.are.equal("custom", instance.custom_prop)
    end)

    it("should instantiate correctly using new()", function()
        local instance = CacheItem:new({
            size = 512,
        })
        assert.are.equal(512, instance.size)
        
        -- Verifying inheritance fallback
        local instance_default = CacheItem:new()
        assert.are.equal(128, instance_default.size)
    end)

    it("should have onFree as a callable method", function()
        local instance = CacheItem:new()
        assert.is_function(instance.onFree)
        assert.has_no.errors(function()
            instance:onFree()
        end)
    end)
end)
