local socketutil

describe("socketutil", function()
    local original_version
    local original_http
    local original_https
    local original_socket

    local mock_version
    local mock_http
    local mock_https
    local mock_socket

    local mock_tcp_socket
    local settimeout_calls

    setup(function()
        -- 1. Backup real modules
        original_version = package.loaded["version"]
        original_http = package.loaded["socket.http"]
        original_https = package.loaded["ssl.https"]
        original_socket = package.loaded["socket"]

        -- 2. Define mocks
        mock_version = {
            getShortVersion = function() return "v2026.05" end
        }
        package.loaded["version"] = mock_version

        mock_http = {
            USERAGENT = "LuaSocket 3.0-rc1",
            TIMEOUT = nil
        }
        package.loaded["socket.http"] = mock_http

        mock_https = {
            TIMEOUT = nil
        }
        package.loaded["ssl.https"] = mock_https

        settimeout_calls = {}
        mock_tcp_socket = {
            settimeout = function(self, timeout, mode)
                table.insert(settimeout_calls, { timeout = timeout, mode = mode })
                return true
            end
        }

        mock_socket = {
            tcp = function()
                return mock_tcp_socket
            end
        }
        package.loaded["socket"] = mock_socket

        -- 3. Load socketutil fresh
        package.loaded["socketutil"] = nil
        socketutil = require("socketutil")
    end)

    teardown(function()
        -- 4. Restore real modules
        package.loaded["version"] = original_version
        package.loaded["socket.http"] = original_http
        package.loaded["ssl.https"] = original_https
        package.loaded["socket"] = original_socket
        package.loaded["socketutil"] = nil
    end)

    before_each(function()
        settimeout_calls = {}
    end)

    describe("UserAgent Monkey-patching", function()
        it("correctly constructs and patches UserAgent", function()
            local expected_ua = "KOReader/v2026.05 (https://koreader.rocks/) LuaSocket/3.0-rc1"
            assert.is.same(expected_ua, socketutil.USER_AGENT)
            assert.is.same(expected_ua, mock_http.USERAGENT)
        end)
    end)

    describe("Timeout Settings (set_timeout / reset_timeout)", function()
        after_each(function()
            socketutil:reset_timeout()
        end)

        it("updates timeout constants correctly via set_timeout", function()
            socketutil:set_timeout(10, 30)

            assert.is.same(10, socketutil.block_timeout)
            assert.is.same(30, socketutil.total_timeout)

            assert.is.same(10, mock_http.TIMEOUT)
            assert.is.same(10, mock_https.TIMEOUT)
        end)

        it("restores default timeouts via reset_timeout", function()
            socketutil:set_timeout(10, 30)
            socketutil:reset_timeout()

            assert.is.same(60, socketutil.block_timeout)
            assert.is.same(-1, socketutil.total_timeout)

            assert.is.same(60, mock_http.TIMEOUT)
            assert.is.same(60, mock_https.TIMEOUT)
        end)
    end)

    describe("TCP Socket Wrapping (socket.tcp)", function()
        after_each(function()
            socketutil:reset_timeout()
        end)

        it("calls settimeout on created sockets with configured timeouts", function()
            socketutil:set_timeout(5, 15)
            local sock = mock_socket.tcp()

            assert.is_not_nil(sock)
            assert.is.same({
                { timeout = 5, mode = "b" },
                { timeout = 15, mode = "t" }
            }, settimeout_calls)
        end)
    end)

    describe("Sinks", function()
        local ltn12 = require("ltn12")

        describe("table_sink", function()
            after_each(function()
                socketutil:reset_timeout()
            end)

            it("behaves like a standard ltn12 table sink if total_timeout < 0", function()
                socketutil:reset_timeout() -- total_timeout = -1
                local t = {}
                local sink = socketutil.table_sink(t)

                sink("chunk1")
                sink("chunk2")
                sink(nil)

                assert.is.same({ "chunk1", "chunk2" }, t)
            end)

            it("behaves normally if total_timeout is positive and not expired", function()
                socketutil:set_timeout(5, 10) -- block_timeout = 5, total_timeout = 10

                local original_time = os.time
                os.time = function() return 1000 end

                local t = {}
                local sink = socketutil.table_sink(t)

                sink("chunk1")
                sink("chunk2")

                os.time = original_time
                assert.is.same({ "chunk1", "chunk2" }, t)
            end)

            it("returns nil and timeout error code if total_timeout expires", function()
                socketutil:set_timeout(5, 10) -- total_timeout = 10

                local original_time = os.time
                local current_time = 1000
                os.time = function() return current_time end

                local t = {}
                local sink = socketutil.table_sink(t)

                local ok, err = sink("chunk1")
                assert.is_not_nil(ok)

                -- Simulate passage of 11 seconds (total_timeout is 10)
                current_time = 1011

                local ok2, err2 = sink("chunk2")
                os.time = original_time

                assert.is_nil(ok2)
                assert.is.same("sink timeout", err2)
                -- The second chunk should not have been inserted
                assert.is.same({ "chunk1" }, t)
            end)
        end)

        describe("file_sink", function()
            local mock_handle
            local write_calls
            local close_called

            before_each(function()
                write_calls = {}
                close_called = false
                mock_handle = {
                    write = function(self, chunk)
                        table.insert(write_calls, chunk)
                        return 1
                    end,
                    close = function(self)
                        close_called = true
                        return true
                    end
                }
            end)

            after_each(function()
                socketutil:reset_timeout()
            end)

            it("behaves like a standard ltn12 file sink if total_timeout < 0", function()
                socketutil:reset_timeout() -- total_timeout = -1
                local sink = socketutil.file_sink(mock_handle)

                sink("chunk1")
                sink("chunk2")
                sink(nil)

                assert.is.same({ "chunk1", "chunk2" }, write_calls)
                assert.is_true(close_called)
            end)

            it("returns nil and timeout error and closes handle if total_timeout expires", function()
                socketutil:set_timeout(5, 10) -- total_timeout = 10

                local original_time = os.time
                local current_time = 1000
                os.time = function() return current_time end

                local sink = socketutil.file_sink(mock_handle)

                local ok, err = sink("chunk1")
                assert.is_not_nil(ok)

                -- Simulate passage of 11 seconds (total_timeout is 10)
                current_time = 1011

                local ok2, err2 = sink("chunk2")
                os.time = original_time

                assert.is_nil(ok2)
                assert.is.same("sink timeout", err2)
                -- Handle should have been closed
                assert.is_true(close_called)
                -- The second chunk should not have been written
                assert.is.same({ "chunk1" }, write_calls)
            end)

            it("returns nil and error if handle is missing and total_timeout is active", function()
                socketutil:set_timeout(5, 10) -- total_timeout = 10
                local sink, err = socketutil.file_sink(nil, "custom error")
                assert.is_nil(sink)
                assert.is.same("custom error", err)
            end)
        end)
    end)
end)
