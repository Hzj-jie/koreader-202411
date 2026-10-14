describe("NewsDownloader InternalDownloadBackend module", function()
  local InternalDownloadBackend, http, socket

  setup(function()
    require("commonrequire")
    package.unloadAll()

    http = require("socket.http")
    socket = require("socket")
    InternalDownloadBackend =
      require("plugins/newsdownloader.koplugin/internaldownloadbackend")
  end)

  it("should handle maximum redirect limits", function()
    assert.has_error(function()
      InternalDownloadBackend:getResponseAsString("http://example.com", 5)
    end)
  end)

  it("should handle successful HTTP 200 responses", function()
    local old_request = http.request
    http.request = function(req)
      req.sink("Sample Response Body")
      return 1, 200, {}, "200 OK"
    end

    local result =
      InternalDownloadBackend:getResponseAsString("http://example.com/feed")
    assert.are.equal("Sample Response Body", result)

    http.request = old_request
  end)

  it("should follow 3xx redirects up to max_redirects limit", function()
    local old_request = http.request
    local calls = 0
    http.request = function(req)
      calls = calls + 1
      if calls == 1 then
        return 1,
          302,
          { location = "http://example.com/redirected" },
          "302 Found"
      else
        req.sink("Redirected Content")
        return 1, 200, {}, "200 OK"
      end
    end

    local result =
      InternalDownloadBackend:getResponseAsString("http://example.com/initial")
    assert.are.equal("Redirected Content", result)
    assert.are.equal(2, calls)

    http.request = old_request
  end)

  it("should raise error on unhandled HTTP response codes", function()
    local old_request = http.request
    http.request = function(req)
      return 1, 500, {}, "500 Internal Error"
    end

    assert.has_error(function()
      InternalDownloadBackend:getResponseAsString("http://example.com/error")
    end)

    http.request = old_request
  end)

  it("should download content to specified file path", function()
    local old_request = http.request
    http.request = function(req)
      req.sink("Downloaded File Data")
      return 1, 200, {}, "200 OK"
    end

    local tmp_path = os.tmpname()
    InternalDownloadBackend:download("http://example.com/file", tmp_path)

    local f = io.open(tmp_path, "r")
    assert.is_not_nil(f)
    local content = f:read("*a")
    f:close()

    assert.are.equal("Downloaded File Data", content)
    os.remove(tmp_path)

    http.request = old_request
  end)
end)
