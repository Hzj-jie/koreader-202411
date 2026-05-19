describe("Version module", function()
    local Version
    setup(function()
        require("commonrequire")
        Version = require("version")
    end)
    it("should get current revision", function()
        local rev = Version:getCurrentRevision()
        local year, month, point, revision = rev:match("v(%d%d%d%d)%.(%d%d)%.?(%d?)-?(%d*)") -- luacheck: ignore 211
        local commit = rev:match("-%d*-g(%x*)[%d_%-]*") -- luacheck: ignore 211
        assert.is_truthy(year)
        assert.is_truthy(month)
        assert.is_true(4 == year:len())
        assert.is_true(2 == month:len())
    end)
    describe("normalized", function()
        it("should get current version", function()
            assert.is_true(12 == tostring(Version:getNormalizedCurrentVersion()):len())
        end)
        it("should get version with 7-character hash", function()
            local rev = "v2015.11-982-g704d4238"
            local version, commit = Version:getNormalizedVersion(rev)
            local expected_version = 201511000982
            local expected_commit = "704d4238"
            assert.are.same(expected_version, version)
            assert.are.same(expected_commit, commit)
        end)
        it("should get version with 8-character hash", function()
            local rev = "v2021.05-70-gae544b74"
            local version, commit = Version:getNormalizedVersion(rev)
            local expected_version = 202105000070
            local expected_commit = "ae544b74"
            assert.are.same(expected_version, version)
            assert.are.same(expected_commit, commit)
        end)
        it("should get version with four number revision", function()
            local rev = "v2015.11-1755-gecd7b5b_2018-07-02"
            local version, commit = Version:getNormalizedVersion(rev)
            local expected_version = 201511001755
            local expected_commit = "ecd7b5b"
            assert.are.same(expected_version, version)
            assert.are.same(expected_commit, commit)
        end)
        it("should get stable version", function()
            local rev = "v2018.11"
            local version, commit = Version:getNormalizedVersion(rev)
            local expected_version = 201811000000
            local expected_commit = nil
            assert.are.same(expected_version, version)
            assert.are.same(expected_commit, commit)
        end)
        it("should get stable point release version", function()
            local rev = "v2018.11.1"
            local version, commit = Version:getNormalizedVersion(rev)
            local expected_version = 201811010000
            local expected_commit = nil
            assert.are.same(expected_version, version)
            assert.are.same(expected_commit, commit)
        end)
        it("should get point release nightly version", function()
            local rev = "v2018.11.1-1755-gecd7b5b_2018-07-02"
            local version, commit = Version:getNormalizedVersion(rev)
            local expected_version = 201811011755
            local expected_commit = "ecd7b5b"
            assert.are.same(expected_version, version)
            assert.are.same(expected_commit, commit)
        end)
    end)
    it("should fail gracefully", function()
        local version, commit = Version:getNormalizedVersion()
        local expected_version = nil
        local expected_commit = nil
        assert.are.same(expected_version, version)
        assert.are.same(expected_commit, commit)
    end)

    describe("short version", function()
        local orig_rev, orig_short
        before_each(function()
            orig_rev = Version.rev
            orig_short = Version.short
        end)
        after_each(function()
            Version.rev = orig_rev
            Version.short = orig_short
        end)

        it("should parse standard nightly revision strings", function()
            Version.rev = "v2021.05-70-gae544b74"
            Version.short = nil
            assert.are.same("2021.05-70", Version:getShortVersion())
        end)

        it("should parse stable revision strings", function()
            Version.rev = "v2018.11"
            Version.short = nil
            assert.are.same("2018.11", Version:getShortVersion())
        end)

        it("should parse point release nightly strings", function()
            Version.rev = "v2018.11.1-1755-gecd7b5b_2018-07-02"
            Version.short = nil
            assert.are.same("2018.11.1-1755", Version:getShortVersion())
        end)

        it("should return unknown on empty/nil", function()
            Version.rev = ""
            Version.short = nil
            assert.are.same("unknown", Version:getShortVersion())

            local orig_getUncached = Version.getUncachedCurrentRevision
            Version.getUncachedCurrentRevision = function() return nil end
            Version.rev = nil
            Version.short = nil
            assert.are.same("unknown", Version:getShortVersion())
            Version.getUncachedCurrentRevision = orig_getUncached
        end)
    end)

    describe("version log file", function()
        local original_io_open = io.open
        local TEST_LOG_FILE = "version.tests.log"
        local orig_rev, orig_last_version, orig_last_model

        setup(function()
            os.remove(TEST_LOG_FILE)
            io.open = function(filename, mode)
                if filename == "version.log" then
                    return original_io_open(TEST_LOG_FILE, mode)
                end
                return original_io_open(filename, mode)
            end
        end)

        teardown(function()
            io.open = original_io_open
            os.remove(TEST_LOG_FILE)
        end)

        before_each(function()
            orig_rev = Version.rev
            orig_last_version = Version.last_version
            orig_last_model = Version.last_model
            os.remove(TEST_LOG_FILE)
        end)

        after_each(function()
            Version.rev = orig_rev
            Version.last_version = orig_last_version
            Version.last_model = orig_last_model
        end)

        it("should return empty string when log file does not exist", function()
            assert.are.same("", Version:getLastLogLine())
        end)

        it("should append and retrieve lines from log file", function()
            assert.truthy(Version:appendToLogFile("first log line"))
            assert.truthy(Version:appendToLogFile("second log line"))
            assert.are.same("second log line", Version:getLastLogLine())
        end)

        it("should update version log only if version or model changed", function()
            Version.rev = "v2026.05-1"
            Version:updateVersionLog("Kindle")

            local line = Version:getLastLogLine()
            assert.truthy(line:match("Kindle"))
            assert.truthy(line:match("v2026%.05%-1"))

            local last_write_time = line:match("^(.-), ") -- luacheck: ignore 211

            Version:updateVersionLog("Kindle")
            local line2 = Version:getLastLogLine()
            assert.are.same(line, line2)

            Version:updateVersionLog("Kobo")
            local line3 = Version:getLastLogLine()
            assert.truthy(line3:match("Kobo"))
            assert.are.not_equal(line2, line3)
        end)
    end)
end)
