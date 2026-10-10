-- luacheck: ignore 122
local ffiUtil = require("ffi/util")
local http = require("socket.http")

describe("InternalDownloadBackend module", function()
  local InternalDownloadBackend
  local saved_http_request
  local tmp_file

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    InternalDownloadBackend =
      require("plugins/newsdownloader.koplugin/internaldownloadbackend")
  end)

  before_each(function()
    saved_http_request = http.request
    tmp_file = os.tmpname() .. "_" .. ffiUtil.getpid() .. ".txt"
  end)

  after_each(function()
    http.request = saved_http_request
    if tmp_file then
      os.remove(tmp_file)
    end
  end)

  it("should expose InternalDownloadBackend table and methods", function()
    assert.is_table(InternalDownloadBackend)
    assert.is_function(InternalDownloadBackend.getResponseAsString)
    assert.is_function(InternalDownloadBackend.download)
  end)

  it("should concatenate multi-chunk 200 OK response", function()
    http.request = function(req)
      if req.sink then
        req.sink("first chunk\n", nil)
        req.sink("second chunk\n", nil)
        req.sink(nil, nil)
      end
      return 1, 200, { ["content-type"] = "text/plain" }, "HTTP/1.1 200 OK"
    end

    local res = InternalDownloadBackend:getResponseAsString("https://example.com/doc")
    assert.are.equal("first chunk\nsecond chunk\n", res)
  end)

  it("should follow 301/302 redirects recursively", function()
    local urls_requested = {}
    http.request = function(req)
      table.insert(urls_requested, req.url)
      if req.url == "https://example.com/initial" then
        return 1, 301, { location = "https://example.com/redirect1" }, "HTTP/1.1 301 Moved"
      elseif req.url == "https://example.com/redirect1" then
        return 1, 302, { location = "https://example.com/final" }, "HTTP/1.1 302 Found"
      else
        if req.sink then
          req.sink("final page content")
        end
        return 1, 200, {}, "HTTP/1.1 200 OK"
      end
    end

    local res = InternalDownloadBackend:getResponseAsString("https://example.com/initial")
    assert.are.equal("final page content", res)
    assert.are.equal(3, #urls_requested)
    assert.are.equal("https://example.com/initial", urls_requested[1])
    assert.are.equal("https://example.com/redirect1", urls_requested[2])
    assert.are.equal("https://example.com/final", urls_requested[3])
  end)

  it("should download response and write to target path", function()
    http.request = function(req)
      if req.sink then
        req.sink("file content for download")
      end
      return 1, 200, {}, "HTTP/1.1 200 OK"
    end

    InternalDownloadBackend:download("https://example.com/file.epub", tmp_file)

    local f = io.open(tmp_file, "r")
    assert.is_not_nil(f)
    local content = f:read("*a")
    f:close()
    assert.are.equal("file content for download", content)
  end)

  it("should include redirect count in error message when max redirects reached", function()
    local ok, err = pcall(function()
      InternalDownloadBackend:getResponseAsString("https://example.com/loop", 5)
    end)
    assert.is_false(ok)
    assert.is_not_nil(err:find("5", 1, true))
  end)

  it("should throw informative error on HTTP 404 rather than bad argument #2 to error", function()
    http.request = function()
      return 1, 404, {}, "HTTP/1.1 404 Not Found"
    end

    local ok, err = pcall(function()
      InternalDownloadBackend:getResponseAsString("https://example.com/notfound")
    end)
    assert.is_false(ok)
    assert.is_nil(err:find("bad argument #2 to 'error'"))
    assert.is_not_nil(err:find("Don't know how to handle HTTP response status", 1, true))
    assert.is_not_nil(err:find("HTTP/1.1 404 Not Found", 1, true))
  end)
end)
