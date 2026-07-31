describe("EpubDownloadBackend module", function()
  local EpubDownloadBackend, http

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    http = require("socket.http")
    EpubDownloadBackend = require("plugins/newsdownloader.koplugin/epubdownloadbackend")
  end)

  it("should set and reset trap widget", function()
    local dummy_widget = { name = "dummy" }
    EpubDownloadBackend:setTrapWidget(dummy_widget)
    assert.are.equal(dummy_widget, EpubDownloadBackend.trap_widget)
    EpubDownloadBackend:resetTrapWidget()
    assert.is_nil(EpubDownloadBackend.trap_widget)
  end)

  it("should download page content via loadPage and getResponseAsString", function()
    local old_request = http.request
    http.request = function(req)
      local body = "<html><body>Sample content</body></html>"
      req.sink(body)
      return 1, 200, { ["content-length"] = tostring(#body) }, "200 OK"
    end

    local content = EpubDownloadBackend:loadPage("http://example.com/article.html")
    assert.is_string(content)
    assert.is_true(content:find("Sample content") ~= nil)

    local str_content = EpubDownloadBackend:getResponseAsString("http://example.com/article.html")
    assert.is_string(str_content)

    http.request = old_request
  end)

  it("should raise error on loadPage failure", function()
    local old_request = http.request
    http.request = function(req)
      return nil, 500, {}, "500 Internal Server Error"
    end

    assert.has_error(function()
      EpubDownloadBackend:loadPage("http://example.com/fail.html")
    end)

    http.request = old_request
  end)

  it("should parse cookies from connection response", function()
    local old_request = http.request
    http.request = function(req)
      return 1, 200, { ["set-cookie"] = "session=abc12345; Path=/; HttpOnly" }, "200 OK"
    end

    local cookies = EpubDownloadBackend:getConnectionCookies("http://example.com/login", {
      user = "test",
      pass = "secret",
    })
    assert.is_table(cookies)
    assert.is_true(#cookies > 0)
    assert.are.equal("session", cookies[1].name)
    assert.are.equal("abc12345", cookies[1].value)

    http.request = old_request
  end)

  it("should create an epub file from HTML string", function()
    local tmp_epub = os.tmpname() .. ".epub"
    local html = "<html><head><title>Test Article</title></head><body><div class=\"content\">Article body</div></body></html>"

    local old_request = http.request
    http.request = function(req)
      return 1, 200, {}, "200 OK"
    end

    local success = pcall(function()
      EpubDownloadBackend:createEpub(
        tmp_epub,
        html,
        "http://example.com/article",
        false,
        "Downloading...",
        true,
        ".content"
      )
    end)
    assert.is_true(success)

    os.remove(tmp_epub)
    http.request = old_request
  end)
end)
