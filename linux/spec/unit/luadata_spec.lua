describe("luadata module", function()
    local Settings, lfs, file
    local function cleanup()
        if file then
            os.remove(file)
            for i = 1, 9 do os.remove(file .. ".old." .. i) end
        end
    end
    setup(function()
        require("commonrequire")
        lfs = require("libs/libkoreader-lfs")
        file = "dummy-luadata-file"
        cleanup()
    end)

    describe("table wrapper", function()
        setup(function()
            cleanup()
            Settings = require("frontend/luadata"):open(file, "test")
        end)
        teardown(function()
            cleanup()
        end)
        it("should add item to table", function()
            Settings:addTableItem(1)
            Settings:addTableItem(2)
            Settings:addTableItem(3)

            assert.are.equal(1, Settings:read()[1])
            assert.are.equal(2, Settings:read()[2])
            assert.are.equal(3, Settings:read()[3])
        end)
    end)

    describe("backup data file", function()
        local d
        setup(function()
            cleanup()
            d = require("frontend/luadata"):open(file, "test")
        end)
        it("should generate data file", function()
            d:addTableItem("a")
            assert.Equals("file", lfs.attributes(d.file, "mode"))
        end)
        it("should generate backup data file on reset", function()
            d:reset()
            -- file and file.old.1 should be generated.
            assert.Equals("file", lfs.attributes(d.file, "mode"))
            assert.Equals("file", lfs.attributes(d.file .. ".old.1", "mode"))
        end)
        it("should remove garbage data file", function()
            d:addTableItem("a")
            -- write some garbage to file.
            local f_out = io.open(d.file, "w")
            f_out:write("bla bla bla")
            f_out:close()

            d = require("frontend/luadata"):open(file, "test")
            -- file should be removed.
            assert.are.not_equal("file", lfs.attributes(d.file, "mode"))
            assert.Equals("file", lfs.attributes(d.file .. ".old.1", "mode"))
            assert.Equals("a", d:read()[1])
            d:addTableItem("b")
            d:reset()
            -- reset generates file.old.1 (with b) and renames old file.old.1 (with a) to file.old.2.
            assert.Equals("file", lfs.attributes(d.file .. ".old.1", "mode"))
            assert.Equals("file", lfs.attributes(d.file .. ".old.2", "mode"))
        end)
        it("should open backup data file after garbage removal", function()
            -- write some garbage to file so open falls back to backup file.old.1.
            local f_out = io.open(d.file, "w")
            f_out:write("bla bla bla")
            f_out:close()

            d = require("frontend/luadata"):open(file, "test")
            assert.Equals("a", d:read()[1])
            assert.Equals("file", lfs.attributes(d.file .. ".old.1", "mode"))
            assert.Equals("file", lfs.attributes(d.file .. ".old.2", "mode"))
        end)
    end)
end)
