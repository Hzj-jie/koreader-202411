describe("OPDSPSE Kavita page stream module", function()
  local OPDSPSE, http, UIManager, RenderImage

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    http = require("socket.http")
    UIManager = require("ui/uimanager")
    RenderImage = require("ui/renderimage")
    OPDSPSE = require("plugins/opds.koplugin/opdspse")
  end)

  before_each(function()
    UIManager.setDirty = function() end
  end)

  it("should return default 0 if HTTP request fails", function()
    local old_request = http.request
    http.request = function()
      return nil
    end

    local remote_url =
      "http://example.com/api/opds/abc123key/image?chapterId=42"
    local page = OPDSPSE:getLastPage(remote_url, "user", "pass")
    assert.are.equal(0, page)

    http.request = old_request
  end)

  it("should show error and return 0 for invalid scheme", function()
    local shown_msg = nil
    local old_show = UIManager.show
    UIManager.show = function(self, w)
      shown_msg = w
    end

    local remote_url = "ftp://example.com/api/opds/abc123key/image?chapterId=42"
    local page = OPDSPSE:getLastPage(remote_url, "user", "pass")
    assert.are.equal(0, page)
    assert.is_not_nil(shown_msg)

    UIManager.show = old_show
  end)

  it("should show jump to page dialog and handle dialog callbacks", function()
    local switched_page = nil
    local mock_viewer = {
      switchToImageNum = function(self, num)
        switched_page = num
      end,
    }

    local shown_dialog = nil
    local closed_dialog = nil
    local old_show = UIManager.show
    local old_close = UIManager.close
    UIManager.show = function(self, w)
      shown_dialog = w
    end
    UIManager.close = function(self, w)
      closed_dialog = w
    end

    OPDSPSE:jumpToPage(mock_viewer, 50)
    assert.is_not_nil(shown_dialog)
    assert.is_nil(switched_page)

    -- Cancel button
    local cancel_btn = shown_dialog.buttons[1][1]
    assert.are.equal("close", cancel_btn.id)
    cancel_btn.callback()
    assert.are.equal(shown_dialog, closed_dialog)

    -- Stream button callback with valid input
    local stream_btn = shown_dialog.buttons[1][2]
    shown_dialog.getInputValue = function()
      return 25
    end
    stream_btn.callback()
    assert.are.equal(25, switched_page)

    -- Stream button callback clamps < 1 to 1
    shown_dialog.getInputValue = function()
      return -5
    end
    stream_btn.callback()
    assert.are.equal(1, switched_page)

    -- Stream button callback clamps > count to count
    shown_dialog.getInputValue = function()
      return 999
    end
    stream_btn.callback()
    assert.are.equal(50, switched_page)

    UIManager.show = old_show
    UIManager.close = old_close
  end)

  it(
    "should stream pages, construct ImageViewer, and fetch page data",
    function()
      local old_show = UIManager.show
      local old_close = UIManager.close
      local old_request = http.request
      local old_render = RenderImage.renderImageData
      local old_render_file = RenderImage.renderImageFile

      local shown_viewer = nil
      UIManager.show = function(self, w)
        shown_viewer = w
      end
      UIManager.close = function() end

      RenderImage.renderImageData = function(self, data, len)
        return { is_mock_bb = true, len = len }
      end
      RenderImage.renderImageFile = function()
        return { is_fallback_bb = true }
      end

      local requested_urls = {}
      http.request = function(req)
        table.insert(requested_urls, req.url)
        if req.url:find("Plugin/authenticate", 1, true) then
          req.sink('{"token":"mock_token_123","refresh":""}')
          return 1, 200, {}, "200 OK"
        elseif req.url:find("Reader/get-progress", 1, true) then
          req.sink('{"pageNum":3,"seriesId":1}')
          return 1, 200, {}, "200 OK"
        else
          req.sink("mock_image_bytes")
          return 1, 200, {}, "200 OK"
        end
      end

      local remote_url =
        "http://example.com/api/opds/abc123key/image?chapterId=42&page={pageNumber}&w={maxWidth}"
      OPDSPSE:streamPages(remote_url, 10, false, "user", "pass")

      assert.is_not_nil(shown_viewer)
      assert.is_table(shown_viewer._images_list)
      assert.is_table(shown_viewer.image)
      assert.is_true(shown_viewer.image.is_mock_bb)

      -- Non-number index returns fallback
      local fallback = shown_viewer._images_list["some_string"]
      assert.is_table(fallback)
      assert.is_true(fallback.is_fallback_bb)

      UIManager.show = old_show
      UIManager.close = old_close
      http.request = old_request
      RenderImage.renderImageData = old_render
      RenderImage.renderImageFile = old_render_file
    end
  )

  it(
    "should return page number as integer number type [exposes production bug in OPDSPSE:getLastPage()]",
    function()
      local old_request = http.request
      local req_count = 0

      http.request = function(req)
        req_count = req_count + 1
        if req_count == 1 then
          req.sink('{"token":"mock_token_123","refresh":""}')
          return 1, 200, {}, "200 OK"
        else
          req.sink('{"pageNum":5,"seriesId":1}')
          return 1, 200, {}, "200 OK"
        end
      end

      local remote_url =
        "http://example.com/api/opds/abc123key/image?chapterId=42"
      local page = OPDSPSE:getLastPage(remote_url, "user", "pass")

      -- Production bug: string.match returns a string ("5"), not a number (5)
      assert.is_number(page)
      assert.are.equal(5, page)

      http.request = old_request
    end
  )

  it(
    "should handle chunked HTTP responses across multiple chunks [exposes production bug in OPDSPSE:getLastPage()]",
    function()
      local old_request = http.request
      local req_count = 0

      http.request = function(req)
        req_count = req_count + 1
        if req_count == 1 then
          -- Deliver auth token in multiple chunks
          req.sink('{"token":"mock_token_')
          req.sink('multi_chunk_123","refresh":""}')
          return 1, 200, {}, "200 OK"
        else
          -- Deliver progress in multiple chunks
          req.sink('{"pageNum":')
          req.sink('8,"seriesId":1}')
          return 1, 200, {}, "200 OK"
        end
      end

      local remote_url =
        "http://example.com/api/opds/abc123key/image?chapterId=42"
      local ok, page = pcall(function()
        return OPDSPSE:getLastPage(remote_url, "user", "pass")
      end)

      -- Production bug: inspects only auth_data[1] and progress_data[1],
      -- failing to concatenate chunks, so auth fails with nil bearer token
      assert.is_true(ok)
      assert.are.equal(8, page)

      http.request = old_request
    end
  )
end)
