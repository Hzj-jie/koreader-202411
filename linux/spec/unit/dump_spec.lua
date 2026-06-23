describe("dump", function()
    local dump

    setup(function()
        require("commonrequire")
        dump = require("dump")
    end)

    describe("basic datatypes", function()
        it("should serialize nil", function()
            assert.are.equal("nil", dump(nil))
        end)

        it("should serialize booleans", function()
            assert.are.equal("true", dump(true))
            assert.are.equal("false", dump(false))
        end)

        it("should serialize numbers", function()
            assert.are.equal("123", dump(123))
            assert.are.equal("-45.67", dump(-45.67))
            assert.are.equal("0", dump(0))
        end)

        it("should serialize strings with escaping", function()
            assert.are.equal('"hello"', dump("hello"))
            assert.are.equal('"hello \\"world\\""', dump('hello "world"'))
            assert.are.equal('"line1\\\nline2"', dump("line1\nline2"))
        end)

        it("should serialize functions using tostring", function()
            local func = function() end
            local expected = tostring(func)
            assert.are.equal(expected, dump(func))
        end)
    end)

    describe("tables", function()
        it("should serialize empty tables", function()
            assert.are.equal("{}", dump({}))
        end)

        it("should serialize simple flat tables with sorted keys", function()
            local t = { b = "two", a = 1 }
            local expected = "{\n" ..
                '  ["a"] = 1,\n' ..
                '  ["b"] = "two",\n' ..
                "}"
            assert.are.equal(expected, dump(t))
        end)

        it("should serialize mixed type keys in correct sorted order", function()
            -- SortedIteration sorts same types via <, and different types by tostring.
            -- Let's test a table with string and numeric keys.
            local t = { [2] = "num_two", b = "str_b", [1] = "num_one", a = "str_a" }
            -- SortedIteration order will sort:
            -- 1 < 2 (numbers)
            -- "a" < "b" (strings)
            -- Wait, if we have mixed types:
            -- 1, 2, "a", "b". Let's see how type mismatch is handled:
            -- "1" < "a" (tostring comparison for mixed types, or table.sort handles them?)
            -- Actually:
            -- type(1) == type(2) -> 1 < 2.
            -- type("a") == type("b") -> "a" < "b".
            -- type(1) ~= type("a") -> tostring(1) < tostring("a") -> "1" < "a".
            -- So sorted order should be: 1, 2, "a", "b".
            local expected = "{\n" ..
                '  [1] = "num_one",\n' ..
                '  [2] = "num_two",\n' ..
                '  ["a"] = "str_a",\n' ..
                '  ["b"] = "str_b",\n' ..
                "}"
            assert.are.equal(expected, dump(t))
        end)

        it("should serialize nested tables with correct indentation and sorting", function()
            local t = {
                z_val = 10,
                a_tbl = {
                    c = "nested_c",
                    b = "nested_b"
                }
            }
            local expected = "{\n" ..
                '  ["a_tbl"] = {\n' ..
                '    ["b"] = "nested_b",\n' ..
                '    ["c"] = "nested_c",\n' ..
                "  },\n" ..
                '  ["z_val"] = 10,\n' ..
                "}"
            assert.are.equal(expected, dump(t))
        end)
    end)

    describe("loop detection", function()
        it("should detect self-referential table loops and output placeholder", function()
            local t = {}
            t[1] = t

            local expected = "{\n" ..
                "  [1] = nil --[[ LOOP:\n" ..
                "^------- ]],\n" ..
                "}"
            assert.are.equal(expected, dump(t))
        end)

        it("should detect deep table loops", function()
            local a = {}
            local b = {}
            a.next_node = b
            b.next_node = a

            -- a is serialized.
            -- keys: "next_node" -> b
            --   b's keys: "next_node" -> a (LOOP)
            -- Let's trace:
            -- _serialize(a, out, 0, {})
            --   history: { a }
            --   key "next_node", value b
            --   _serialize(b, out, 1, { a })
            --     history: { b, a }
            --     key "next_node", value a
            --     _serialize(a, out, 2, { b, a })
            --       history contains a!
            --       up = 2 (since a is second element, next_node history unpack order: a was added first, b second, so history = { b, a })
            --       Wait, new_history = { what, unpack(history) }
            --       First call: _serialize(a, {}, 0, {}) -> new_history = { a }
            --       Second call: _serialize(b, {}, 1, { a }) -> new_history = { b, a }
            --       Third call: _serialize(a, {}, 2, { b, a })
            --       Loops ipairs(history):
            --         up=1, item=b
            --         up=2, item=a -> MATCH!
            --       Outputs loop comment:
            --         indent = 2
            --         up = 2
            --         indent - up = 0.
            --         No prefix indent for ^-------.
            local expected = "{\n" ..
                '  ["next_node"] = {\n' ..
                '    ["next_node"] = nil --[[ LOOP:\n' ..
                "^------- ]],\n" ..
                "  },\n" ..
                "}"
            assert.are.equal(expected, dump(a))
        end)
    end)
end)
