describe("EpubDownloadBackend module", function()
  local EpubDownloadBackend, http

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    http = require("socket.http")
    EpubDownloadBackend =
      require("plugins/newsdownloader.koplugin/epubdownloadbackend")
  end)

  it("should set and reset trap widget", function()
    local dummy_widget = { name = "dummy" }
    EpubDownloadBackend:setTrapWidget(dummy_widget)
    assert.are.equal(dummy_widget, EpubDownloadBackend.trap_widget)
    EpubDownloadBackend:resetTrapWidget()
    assert.is_nil(EpubDownloadBackend.trap_widget)
  end)

  it(
    "should download page content via loadPage and getResponseAsString",
    function()
      local old_request = http.request
      http.request = function(req)
        local body = "<html><body>Sample content</body></html>"
        req.sink(body)
        return 1, 200, { ["content-length"] = tostring(#body) }, "200 OK"
      end

      local content =
        EpubDownloadBackend:loadPage("http://example.com/article.html")
      assert.is_string(content)
      assert.is_true(content:find("Sample content") ~= nil)

      local str_content = EpubDownloadBackend:getResponseAsString(
        "http://example.com/article.html"
      )
      assert.is_string(str_content)

      http.request = old_request
    end
  )

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
      return 1,
        200,
        { ["set-cookie"] = "session=abc12345; Path=/; HttpOnly" },
        "200 OK"
    end

    local cookies =
      EpubDownloadBackend:getConnectionCookies("http://example.com/login", {
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
    local html =
      '<html><head><title>Test Article</title></head><body><div class="content">Article body</div></body></html>'

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

  it("should handle HTTP redirects and content-length validation", function()
    local old_request = http.request
    local req_count = 0
    http.request = function(req)
      req_count = req_count + 1
      if req_count == 1 then
        return 1, 301, { location = "/redirected_path.html" }, "301 Moved"
      else
        local body = "<html><body>Redirected Body</body></html>"
        req.sink(body)
        return 1, 200, { ["content-length"] = tostring(#body) }, "200 OK"
      end
    end

    local content = EpubDownloadBackend:loadPage("http://example.com/start.html")
    assert.is_string(content)
    assert.is_true(content:find("Redirected Body") ~= nil)

    -- Incomplete content length check
    http.request = function(req)
      local body = "Short"
      req.sink(body)
      return 1, 200, { ["content-length"] = "100" }, "200 OK"
    end

    assert.has_error(function()
      EpubDownloadBackend:loadPage("http://example.com/short.html")
    end)

    http.request = old_request
  end)

  it("should handle socket timeouts and network unavailability", function()
    local socketutil = require("socketutil")
    local old_request = http.request

    -- Timeout error code
    http.request = function(req)
      return 1, socketutil.TIMEOUT_CODE, {}, "Timeout"
    end
    assert.has_error(function()
      EpubDownloadBackend:loadPage("http://example.com/timeout.html")
    end)

    -- Missing headers
    http.request = function(req)
      return nil, "connection refused"
    end
    assert.has_error(function()
      EpubDownloadBackend:loadPage("http://example.com/down.html")
    end)

    http.request = old_request
  end)

  it("should handle loadPage under Trapper widget with dismissal", function()
    local Trapper = require("ui/trapper")
    local old_dismissable = Trapper.dismissableRunInSubprocess
    local dummy_widget = { name = "dummy_trap" }
    EpubDownloadBackend:setTrapWidget(dummy_widget)

    -- Completed run
    Trapper.dismissableRunInSubprocess = function(self_trapper, fn, widget)
      return true, true, "<html>Trapper Content</html>"
    end
    local content = EpubDownloadBackend:loadPage("http://example.com/trapped.html")
    assert.are.equal("<html>Trapper Content</html>", content)

    -- User interrupted / cancelled
    Trapper.dismissableRunInSubprocess = function(self_trapper, fn, widget)
      return false, nil, nil
    end
    local ok, err = pcall(function()
      EpubDownloadBackend:loadPage("http://example.com/cancel.html")
    end)
    assert.is_false(ok)
    assert.is_true(tostring(err):find(EpubDownloadBackend.dismissed_error_code) ~= nil)

    EpubDownloadBackend:resetTrapWidget()
    Trapper.dismissableRunInSubprocess = old_dismissable
  end)

  it("should create an epub with images, srcset, SVG, and cover selection", function()
    local tmp_epub = os.tmpname() .. ".epub"
    local html = [[
<html>
  <head><title>Full Image Article</title></head>
  <body>
    <article>
      <h1>Article Title</h1>
      <img src="//example.com/cover.jpg" width="100" height="150" alt="Cover" />
      <img src="/relative/img.png" width="80" height="80" srcset="/relative/img.png 1x, /relative/img_2x.png 2x" alt="2x image" />
      <img src="http://example.com/vector.svg" width="40" height="40" alt="Vector" />
    </article>
  </body>
</html>
]]

    local old_request = http.request
    http.request = function(req)
      local img_data = "FAKE_IMAGE_DATA_12345"
      if req.sink then
        req.sink(img_data)
      end
      return 1, 200, { ["content-length"] = tostring(#img_data) }, "200 OK"
    end

    local success = pcall(function()
      EpubDownloadBackend:createEpub(
        tmp_epub,
        html,
        "http://example.com/article/full",
        true, -- include_images
        "Downloading with images...",
        true, -- filter_enable
        "article"
      )
    end)
    assert.is_true(success)

    os.remove(tmp_epub)
    http.request = old_request
  end)

  it("should handle image download failure and cancellation in createEpub", function()
    local tmp_epub = os.tmpname() .. ".epub"
    local html = '<html><head><title>Failed Img</title></head><body><img src="http://example.com/missing.png" width="80" height="80"/></body></html>'

    local Trapper = require("ui/trapper")
    local old_confirm = Trapper.confirm
    local old_request = http.request

    -- Simulate image HTTP 404
    http.request = function(req)
      return nil, 404, {}, "404 Not Found"
    end

    -- User chooses not to continue when image fails, and not to create epub
    Trapper.confirm = function(self_trapper, msg, btn1, btn2)
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

    -- User chooses to create epub with partial images
    Trapper.confirm = function(self_trapper, msg, btn1, btn2)
      if msg:find("Continue anyway") then
        return false
      else
        return true -- Create with already downloaded images
      end
    end

    result = EpubDownloadBackend:createEpub(
      tmp_epub,
      html,
      "http://example.com/fail2",
      true,
      "Downloading...",
      false
    )
    assert.is_true(result)

    os.remove(tmp_epub)
    Trapper.confirm = old_confirm
    http.request = old_request
  end)
end)
