describe("sort", function()
    local sort

    setup(function()
        require("commonrequire")
        sort = require("sort")
    end)

    describe("natsort_cmp", function()
        it("should return a comparison function and a cache table", function()
            local cmp, cache = sort.natsort_cmp()
            assert.is_function(cmp)
            assert.is_table(cache)
        end)

        it("should sort standard strings alphabetically", function()
            local cmp = sort.natsort_cmp()
            local t = { "banana", "cherry", "apple" }
            table.sort(t, cmp)
            assert.are.same({ "apple", "banana", "cherry" }, t)
        end)

        it("should sort numbers naturally (numerically, not alphabetically)", function()
            local cmp = sort.natsort_cmp()
            local t = { "10", "2", "1", "20" }
            table.sort(t, cmp)
            assert.are.same({ "1", "2", "10", "20" }, t)
        end)

        it("should sort mixed text and numbers naturally", function()
            local cmp = sort.natsort_cmp()
            local t = { "file10.txt", "file2.txt", "file1.txt", "file20.txt" }
            table.sort(t, cmp)
            assert.are.same({ "file1.txt", "file2.txt", "file10.txt", "file20.txt" }, t)
        end)

        it("should sort version-like strings correctly (treating dot-numbers as decimals)", function()
            local cmp = sort.natsort_cmp()
            local t = { "1.10", "1.2", "1.1", "1.20" }
            table.sort(t, cmp)
            -- KOReader natsort treats .10 as decimal 0.10 (which is 0.1) and .2 as 0.2.
            -- So "1.1" < "1.10" < "1.2" < "1.20"
            assert.are.same({ "1.1", "1.10", "1.2", "1.20" }, t)
        end)

        it("should handle leading zeros in numerical sorting", function()
            local cmp = sort.natsort_cmp()
            local t = { "file02.txt", "file2.txt", "file01.txt", "file1.txt" }
            table.sort(t, cmp)
            assert.are.same({ "file01.txt", "file1.txt", "file02.txt", "file2.txt" }, t)
        end)

        describe("caching", function()
            it("should populate the cache during sorting", function()
                local cmp, cache = sort.natsort_cmp()
                local t = { "b", "a" }
                assert.is_nil(cache["a"])
                assert.is_nil(cache["b"])

                table.sort(t, cmp)

                assert.is_not_nil(cache["a"])
                assert.is_not_nil(cache["b"])
            end)

            it("should use provided cache", function()
                local my_cache = {}
                local cmp, cache = sort.natsort_cmp(my_cache)
                assert.are.equal(my_cache, cache)

                local t = { "b", "a" }
                table.sort(t, cmp)

                assert.is_not_nil(my_cache["a"])
                assert.is_not_nil(my_cache["b"])
            end)

            it("should reuse cache values to avoid re-evaluation (proven by injection)", function()
                local my_cache = {
                    -- Inject fake values to reverse sorting
                    -- We want "a" to be sorted AFTER "b".
                    -- So we make "a"'s cached value larger than "b"'s cached value alphabetically.
                    a = "z_fake_large",
                    b = "y_fake_small",
                }
                local cmp = sort.natsort_cmp(my_cache)
                local t = { "a", "b" }
                table.sort(t, cmp)

                -- Since we mocked the cache, "b" (y_fake_small) should come before "a" (z_fake_large)
                assert.are.same({ "b", "a" }, t)
            end)
        end)
    end)
end)
