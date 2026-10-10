describe("EpubDownloadBackend module", function()
  local EpubDownloadBackend, Trapper, socketutil, http, ffiUtil
  local saved_http_request
  local saved_trapper_subprocess
  local saved_trapper_confirm

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    ffiUtil = require("ffi/util")
    http = require("socket.http")
    socketutil = require("socketutil")
    Trapper = require("ui/trapper")
    EpubDownloadBackend =
      require("plugins/newsdownloader.koplugin/epubdownloadbackend")
  end)

  before_each(function()
    saved_http_request = http.request
    saved_trapper_subprocess = Trapper.dismissableRunInSubprocess
    saved_trapper_confirm = Trapper.confirm
  end)

  after_each(function()
    http.request = saved_http_request
    Trapper.dismissableRunInSubprocess = saved_trapper_subprocess
    Trapper.confirm = saved_trapper_confirm
    EpubDownloadBackend:resetTrapWidget()
  end)

  it("should set and reset trap widget", function()
    local dummy = { name = "dummy_widget" }
    EpubDownloadBackend:setTrapWidget(dummy)
    assert.are.equal(dummy, EpubDownloadBackend.trap_widget)
    EpubDownloadBackend:resetTrapWidget()
    assert.is_nil(EpubDownloadBackend.trap_widget)
  end)

  it("should handle getResponseAsString with 200 OK and cookie headers", function()
    local req_headers_seen
    http.request = function(req)
      req_headers_seen = req.headers
      local body = "hello world content"
      if req.sink then
        req.sink(body)
      end
      return 1, 200, { ["content-length"] = tostring(#body) }, "200 OK"
    end

    local cookies = {
      { name = "sess", value = "12345" },
      { name = "uid", value = "user1" },
    }
    local res = EpubDownloadBackend:getResponseAsString("http://example.com/page", cookies)
    assert.are.equal("hello world content", res)
    assert.is_not_nil(req_headers_seen)
    assert.are.equal("sess=12345; uid=user1", req_headers_seen.cookie)
  end)

  it("should handle relative and absolute 301/302 redirects up to limit", function()
    local req_count = 0
    http.request = function(req)
      req_count = req_count + 1
      if req_count == 1 then
        return 1, 301, { location = "/relative_dest" }, "301 Moved"
      elseif req_count == 2 then
        return 1, 302, { location = "http://example.com/absolute_dest" }, "302 Found"
      else
        local body = "destination content"
        if req.sink then
          req.sink(body)
        end
        return 1, 200, { ["content-length"] = tostring(#body) }, "200 OK"
      end
    end

    local res = EpubDownloadBackend:getResponseAsString("http://example.com/start")
    assert.are.equal("destination content", res)
    assert.are.equal(3, req_count)

    -- Exceeding max redirects limit
    http.request = function(req)
      return 1, 301, { location = "http://example.com/loop" }, "301 Moved"
    end
    assert.has_error(function()
      EpubDownloadBackend:getResponseAsString("http://example.com/loop")
    end)
  end)

  it("should throw error on content-length mismatch and socket timeout", function()
    -- Content-Length mismatch
    http.request = function(req)
      local body = "short"
      if req.sink then
        req.sink(body)
      end
      return 1, 200, { ["content-length"] = "100" }, "200 OK"
    end
    assert.has_error(function()
      EpubDownloadBackend:getResponseAsString("http://example.com/mismatch")
    end)

    -- Socket timeout
    http.request = function(req)
      return 1, socketutil.TIMEOUT_CODE, {}, "Timeout"
    end
    assert.has_error(function()
      EpubDownloadBackend:getResponseAsString("http://example.com/timeout")
    end)

    -- Missing headers (network error)
    http.request = function(req)
      return nil, "connection refused"
    end
    assert.has_error(function()
      EpubDownloadBackend:getResponseAsString("http://example.com/connrefused")
    end)
  end)

  it("should handle loadPage with and without trap widget and user interruption", function()
    -- Direct loadPage without trap widget
    http.request = function(req)
      local body = "direct body"
      if req.sink then
        req.sink(body)
      end
      return 1, 200, { ["content-length"] = tostring(#body) }, "200 OK"
    end
    local content = EpubDownloadBackend:loadPage("http://example.com/direct")
    assert.are.equal("direct body", content)

    -- loadPage with trap widget
    local dummy_widget = { name = "dummy_trap" }
    EpubDownloadBackend:setTrapWidget(dummy_widget)

    Trapper.dismissableRunInSubprocess = function(self_trapper, fn, widget)
      return true, true, "trapped body"
    end
    content = EpubDownloadBackend:loadPage("http://example.com/trapped")
    assert.are.equal("trapped body", content)

    -- loadPage user interruption
    Trapper.dismissableRunInSubprocess = function(self_trapper, fn, widget)
      return false, nil, nil
    end
    local ok, err = pcall(function()
      EpubDownloadBackend:loadPage("http://example.com/interrupted")
    end)
    assert.is_false(ok)
    assert.is_not_nil(tostring(err):find(EpubDownloadBackend.dismissed_error_code, 1, true))

    EpubDownloadBackend:resetTrapWidget()
  end)

  it("should parse Set-Cookie with quoted values and attributes in getConnectionCookies", function()
    http.request = function(req)
      return 1, 200, {
        ["set-cookie"] = 'session="abc,123;xyz"; Path=/; HttpOnly, token=tok456; Secure',
      }, "200 OK"
    end

    local cookies = EpubDownloadBackend:getConnectionCookies("http://example.com/login", { user = "u", pass = "p" })
    assert.is_table(cookies)
    assert.is_true(#cookies >= 2)
    assert.are.equal("session", cookies[1].name)
    assert.are.equal("abc,123;xyz", cookies[1].value)
    assert.are.equal("token", cookies[2].name)
    assert.are.equal("tok456", cookies[2].value)
  end)

  it("should create epub with images, srcset, SVG, relative URLs, and cover detection", function()
    local tmp_epub = os.tmpname() .. "_" .. ffiUtil.getpid() .. ".epub"
    local html = [[
<html>
  <head><title>Full Article</title></head>
  <body>
    <article>
      <h1>Heading</h1>
      <img src="//example.com/img1.jpg" width="100" height="200" alt="Cover" />
      <img src="/local/img2.png" width="60" height="60" srcset="/local/img2.png 1x, /local/img2_2x.png 2x" />
      <img src="http://example.com/vector.svg" width="40" height="40" />
    </article>
  </body>
</html>
]]
    http.request = function(req)
      local data = "IMAGE_BYTES_123"
      if req.sink then
        req.sink(data)
      end
      return 1, 200, { ["content-length"] = tostring(#data) }, "200 OK"
    end

    local ok = EpubDownloadBackend:createEpub(
      tmp_epub,
      html,
      "http://example.com/full",
      true,
      "Downloading...",
      true,
      "article"
    )
    assert.is_true(ok)
    os.remove(tmp_epub)
  end)

  it("should handle user cancellation cleanup during image download in createEpub", function()
    local tmp_epub = os.tmpname() .. "_" .. ffiUtil.getpid() .. ".epub"
    local html = '<html><head><title>Failed</title></head><body><img src="http://example.com/missing.png"/></body></html>'

    http.request = function(req)
      return nil, 404, {}, "404 Not Found"
    end

    -- User cancels download and does not continue
    Trapper.confirm = function(self_trapper, msg)
      return false
    end

    local result = EpubDownloadBackend:createEpub(
      tmp_epub,
      html,
      "http://example.com/fail",
      true,
      "Downloading...",
      false
    )
    assert.is_false(result)
    os.remove(tmp_epub)
  end)

  it("should handle missing Set-Cookie header gracefully in getConnectionCookies", function()
    http.request = function(req)
      return 1, 200, {}, "200 OK"
    end

    local cookies = EpubDownloadBackend:getConnectionCookies("http://example.com/login", { user = "u" })
    assert.is_table(cookies)
    assert.are.equal(0, #cookies)
  end)

  it("should handle HTML without title tag in createEpub and set valid title", function()
    local tmp_epub = os.tmpname() .. "_" .. ffiUtil.getpid() .. ".epub"
    local html = "<html><body><article><p>Article content without title tag</p></article></body></html>"

    http.request = function(req)
      return 1, 200, {}, "200 OK"
    end

    local ok = EpubDownloadBackend:createEpub(
      tmp_epub,
      html,
      "http://example.com/article",
      false,
      "Downloading...",
      false
    )
    assert.is_true(ok)

    local p = io.popen("unzip -p " .. tmp_epub .. " OEBPS/content.opf 2>/dev/null", "r")
    local opf = p and p:read("*a")
    if p then p:close() end
    os.remove(tmp_epub)

    assert.is_not_nil(opf)
    assert.is_nil(opf:find("<dc:title>nil</dc:title>", 1, true))
  end)
end)
