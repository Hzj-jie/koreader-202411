local logger
local serpent = require("ffi/serpent")

describe("logger", function()
    local original_date
    local original_io_write

    setup(function()
        require("commonrequire")
        logger = require("logger")
        original_date = os.date
        original_io_write = io.write

        -- Mock os.date for predictable timestamps
        os.date = function(format)
            if format == "%x-%X" then
                return "05/18/26-21:22:39"
            end
            return original_date(format)
        end
    end)

    teardown(function()
        os.date = original_date
        io.write = original_io_write
    end)

    -- Helper to capture io.write output
    local function capture_log(fn)
        local captured = nil
        io.write = function(str)
            captured = str
            return true
        end
        local success, err = pcall(fn)
        io.write = original_io_write -- restore immediately
        if not success then
            error(err)
        end
        return captured
    end

    describe("setLevel", function()
        after_each(function()
            logger:setLevel(logger.levels.info)
        end)

        it("disables lower priority levels and enables higher ones", function()
            logger:setLevel(logger.levels.warn)

            -- dbg and info should be noop (no output)
            assert.is_nil(capture_log(function() logger.dbg("debug msg") end))
            assert.is_nil(capture_log(function() logger.info("info msg") end))

            -- warn and err should be active (have output)
            assert.is_not_nil(capture_log(function() logger.warn("warn msg") end))
            assert.is_not_nil(capture_log(function() logger.err("err msg") end))
        end)

        it("enables all levels when set to dbg", function()
            logger:setLevel(logger.levels.dbg)

            assert.is_not_nil(capture_log(function() logger.dbg("debug msg") end))
            assert.is_not_nil(capture_log(function() logger.info("info msg") end))
            assert.is_not_nil(capture_log(function() logger.warn("warn msg") end))
            assert.is_not_nil(capture_log(function() logger.err("err msg") end))
        end)

        it("disables all except err when set to err", function()
            logger:setLevel(logger.levels.err)

            assert.is_nil(capture_log(function() logger.dbg("debug msg") end))
            assert.is_nil(capture_log(function() logger.info("info msg") end))
            assert.is_nil(capture_log(function() logger.warn("warn msg") end))
            assert.is_not_nil(capture_log(function() logger.err("err msg") end))
        end)
    end)

    describe("output formatting", function()
        before_each(function()
            logger:setLevel(logger.levels.dbg)
        end)

        after_each(function()
            logger:setLevel(logger.levels.info)
        end)

        it("formats debug logs correctly", function()
            local out = capture_log(function() logger.dbg("hello") end)
            assert.is.same("05/18/26-21:22:39 DEBUG hello \n", out)
        end)

        it("formats info logs correctly", function()
            local out = capture_log(function() logger.info("hello") end)
            assert.is.same("05/18/26-21:22:39 INFO  hello \n", out)
        end)

        it("formats warn logs correctly", function()
            local out = capture_log(function() logger.warn("hello") end)
            assert.is.same("05/18/26-21:22:39 WARN  hello \n", out)
        end)

        it("formats error logs correctly", function()
            local out = capture_log(function() logger.err("hello") end)
            assert.is.same("05/18/26-21:22:39 ERROR hello \n", out)
        end)

        it("handles multiple arguments with spaces", function()
            local out = capture_log(function() logger.info("A", "B", 3, true) end)
            assert.is.same("05/18/26-21:22:39 INFO  A B 3 true \n", out)
        end)

        it("serializes tables using serpent", function()
            local tbl = { a = 1, b = "two" }
            local out = capture_log(function() logger.info(tbl) end)

            -- Serpent options in logger.lua:
            -- maxlevel = 10, indent = "  ", nocode = true
            -- We expect serpent.block(tbl, opts)
            local expected_tbl_str = serpent.block(tbl, {
                maxlevel = 10,
                indent = "  ",
                nocode = true,
            })
            local expected_out = "05/18/26-21:22:39 INFO  " .. expected_tbl_str .. " \n"
            assert.is.same(expected_out, out)
        end)
    end)
end)
