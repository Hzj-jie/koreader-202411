describe("OPDSPSE module", function()
  local OPDSPSE
  local CanvasContext
  local Device
  local http
  local Screen
  local UIManager

  setup(function()
    require("commonrequire")
    CanvasContext = require("document/canvascontext")
    Device = require("device")
    CanvasContext:init(Device)
    Screen = Device.screen
    http = require("socket.http")
    OPDSPSE = require("plugins/opds.koplugin/opdspse")
    UIManager = require("ui/uimanager")
  end)

  describe("getLastPage", function()
    it("should extract bearer token and fetch chapter progress page number", function()
      local old_request = http.request
      local req_count = 0
      local captured_headers = {}

      http.request = function(req)
        req_count = req_count + 1
        table.insert(captured_headers, req.headers)
        if req_count == 1 then
          req.sink('{"token":"mock_bearer_jwt","refresh":"none"}')
          return 1, 200, {}, "200 OK"
        else
          req.sink('{"pageNum":7,"seriesId":101}')
          return 1, 200, {}, "200 OK"
        end
      end

      local remote_url = "http://kavita.example/api/opds/myapikey123/image?chapterId=99"
      local page = OPDSPSE:getLastPage(remote_url, "testuser", "testpass")
      assert.are.equal("7", page)
      assert.are.equal(2, req_count)
      assert.are.equal("Bearer mock_bearer_jwt", captured_headers[2]["Authorization"])

      http.request = old_request
    end)

    it("should return default 0 if authentication or progress request fails", function()
      local old_request = http.request
      http.request = function(_req)
        return nil, 401, {}, "401 Unauthorized"
      end

      local remote_url = "http://kavita.example/api/opds/myapikey123/image?chapterId=99"
      local page = OPDSPSE:getLastPage(remote_url, "user", "pass")
      assert.are.equal(0, page)

      http.request = old_request
    end)

    it("should show error message for invalid protocol", function()
      local shown_info
      local old_show = UIManager.show
      UIManager.show = function(_self, widget)
        shown_info = widget
      end

      local remote_url = "ftp://kavita.example/api/opds/myapikey123/image?chapterId=99"
      local page = OPDSPSE:getLastPage(remote_url, "user", "pass")
      assert.are.equal(0, page)
      assert.is_table(shown_info)
      assert.is_truthy(shown_info.text:find("Invalid protocol"))

      UIManager.show = old_show
    end)
  end)

  describe("jumpToPage", function()
    it("should display input dialog and switch page on valid input", function()
      local shown_dialog
      local old_show = UIManager.show
      UIManager.show = function(_self, widget)
        shown_dialog = widget
      end

      local switched_page
      local mock_viewer = {
        switchToImageNum = function(_self, num)
          switched_page = num
        end,
      }

      OPDSPSE:jumpToPage(mock_viewer, 50)
      assert.is_table(shown_dialog)
      assert.are.equal("(1 - 50)", shown_dialog.input_hint)

      -- Find OK/Stream button and invoke callback
      local stream_btn = shown_dialog.buttons[1][2]
      assert.are.equal("Stream", stream_btn.text)
      shown_dialog.getInputValue = function()
        return 25
      end
      stream_btn.callback()
      assert.are.equal(25, switched_page)

      -- Clamps out-of-range inputs
      shown_dialog.getInputValue = function()
        return 999
      end
      stream_btn.callback()
      assert.are.equal(50, switched_page)

      shown_dialog.getInputValue = function()
        return -5
      end
      stream_btn.callback()
      assert.are.equal(1, switched_page)

      -- Cancel button on fresh dialog
      local shown_dialog_2
      UIManager.show = function(_self, widget)
        shown_dialog_2 = widget
      end
      OPDSPSE:jumpToPage(mock_viewer, 50)
      local cancel_btn = shown_dialog_2.buttons[1][1]
      assert.are.equal("Cancel", cancel_btn.text)
      assert.has_no_errors(function()
        cancel_btn.callback()
      end)

      UIManager.show = old_show
    end)
  end)

  describe("streamPages", function()
    it("should initialize image viewer and switch to last page when continue is false", function()
      local shown_viewer
      local old_show = UIManager.show
      UIManager.show = function(_self, widget)
        shown_viewer = widget
      end

      local old_get_last = OPDSPSE.getLastPage
      OPDSPSE.getLastPage = function()
        return 4
      end

      local remote_url = "http://kavita.example/api/opds/key/image?chapterId=10&page={pageNumber}&maxWidth={maxWidth}"
      OPDSPSE:streamPages(remote_url, 20, false, "user", "pass")

      assert.is_table(shown_viewer)
      assert.are.equal(20, shown_viewer.images_list_nb)
      assert.are.equal(5, shown_viewer._images_list_cur) -- 4 + 1
      assert.is_table(shown_viewer._images_list)
      assert.is_not_nil(shown_viewer.image)

      -- Test page_table metatable index for non-number key
      local fallback = shown_viewer._images_list["not_a_number"]
      assert.is_not_nil(fallback)

      UIManager.show = old_show
      OPDSPSE.getLastPage = old_get_last
    end)

    it("should call jumpToPage when continue is true", function()
      local jump_called = false
      local old_jump = OPDSPSE.jumpToPage
      OPDSPSE.jumpToPage = function()
        jump_called = true
      end

      local old_get_last = OPDSPSE.getLastPage
      OPDSPSE.getLastPage = function()
        return 0
      end

      local remote_url = "http://kavita.example/api/opds/key/image?chapterId=10&page={pageNumber}&maxWidth={maxWidth}"
      OPDSPSE:streamPages(remote_url, 15, true, "user", "pass")
      assert.is_true(jump_called)

      OPDSPSE.jumpToPage = old_jump
      OPDSPSE.getLastPage = old_get_last
    end)
  end)
end)
