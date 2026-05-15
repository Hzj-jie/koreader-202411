describe("luasettings module", function()
    local Settings
    setup(function()
        require("commonrequire")
        Settings = require("frontend/luasettings"):open("this-is-not-a-valid-file")
    end)

    it("should handle undefined keys", function()
        Settings:delete("abc")

        assert.True(Settings:hasNot("abc"))
        assert.True(Settings:nilOrTrue("abc"))
        assert.False(Settings:isTrue("abc"))
        Settings:save("abc", true)
        assert.True(Settings:has("abc"))
        assert.True(Settings:nilOrTrue("abc"))
        assert.True(Settings:isTrue("abc"))
    end)

    it("should flip bool values", function()
        Settings:delete("abc")

        assert.True(Settings:hasNot("abc"))
        Settings:flipNilOrTrue("abc")
        assert.False(Settings:nilOrTrue("abc"))
        assert.True(Settings:has("abc"))
        assert.False(Settings:isTrue("abc"))
        Settings:flipNilOrTrue("abc")
        assert.True(Settings:nilOrTrue("abc"))
        assert.True(Settings:hasNot("abc"))
        assert.False(Settings:isTrue("abc"))

        Settings:flipNilOrFalse("abc")
        assert.True(Settings:has("abc"))
        assert.True(Settings:isTrue("abc"))
        assert.True(Settings:nilOrTrue("abc"))
        Settings:flipNilOrFalse("abc")
        assert.False(Settings:has("abc"))
        assert.False(Settings:isTrue("abc"))
        assert.True(Settings:nilOrTrue("abc"))
    end)

    it("should handle child table settings", function()
        Settings:delete("key")

        Settings:save("key", {
            a = "b",
            c = "True",
            d = false,
        })

        local child = Settings:readTableRef("key")

        assert.is_not_nil(child)
        assert.are.equal(child.a, "b")
        assert.are.equal(child.c, "True")
        assert.are.equal(child.d, false)
        assert.is_nil(child.e)
        child.e = true
        Settings:save("key", child)

        child = Settings:readTableRef("key")
        assert.True(child.e == true)
    end)

    describe("table wrapper", function()
        setup(function()
            Settings:delete("key")
        end)

        it("should add item to table", function()
            local t = Settings:readTableRef("key")
            table.insert(t, 1)
            table.insert(t, 2)
            table.insert(t, 3)

            assert.are.equal(1, Settings:read("key")[1])
            assert.are.equal(2, Settings:read("key")[2])
            assert.are.equal(3, Settings:read("key")[3])
        end)

        it("should remove item from table", function()
            local t = Settings:readTableRef("key")
            table.remove(t, 1)

            assert.are.equal(2, Settings:read("key")[1])
            assert.are.equal(3, Settings:read("key")[2])
        end)
    end)
end)
