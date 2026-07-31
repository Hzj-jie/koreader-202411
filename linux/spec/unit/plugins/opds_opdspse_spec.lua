describe("OPDSPSE Kavita page stream module", function()
  local OPDSPSE, http

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    http = require("socket.http")
    OPDSPSE = require("plugins/opds.koplugin/opdspse")
  end)

  it("should attempt to fetch last page from Kavita server", function()
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

    local remote_url = "http://example.com/api/opds/abc123key/image?chapterId=42"
    local page = OPDSPSE:getLastPage(remote_url, "user", "pass")
    assert.are.equal("5", page)

    http.request = old_request
  end)

  it("should return default 0 if HTTP request fails", function()
    local old_request = http.request
    http.request = function(req)
      return nil
    end

    local remote_url = "http://example.com/api/opds/abc123key/image?chapterId=42"
    local page = OPDSPSE:getLastPage(remote_url, "user", "pass")
    assert.are.equal(0, page)

    http.request = old_request
  end)

  it("should show jump to page dialog and switch page", function()
    local switched_page = nil
    local mock_viewer = {
      switchToImageNum = function(self, num)
        switched_page = num
      end,
    }

    OPDSPSE:jumpToPage(mock_viewer, 50)
    assert.is_nil(switched_page)
  end)
end)
