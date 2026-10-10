describe("HttpClient module", function()
  local HttpClient, UIManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    UIManager = require("ui/uimanager")
    HttpClient = require("httpclient")
  end)

  it("should instantiate HttpClient instance", function()
    local client = HttpClient:new()
    assert.is_table(client)
    assert.are.equal(0, client.input_timeouts)
  end)

  it("should handle request submission and looper callback", function()
    local cb_called = false
    local mock_looper = {
      add_callback = function(self, func)
        -- execute callback within coroutine context
        local co = coroutine.create(func)
        coroutine.resume(co)
      end,
    }

    local old_init = UIManager.initLooper
    local old_set_to = UIManager.setInputTimeout
    local old_reset_to = UIManager.resetInputTimeout

    UIManager.initLooper = function()
      UIManager.looper = mock_looper
    end
    UIManager.setInputTimeout = function() end
    UIManager.resetInputTimeout = function() end

    package.loaded.turbo = {
      log = { categories = {} },
      async = {
        HTTPClient = function()
          return {
            fetch = function()
              return { code = 200, body = "OK" }
            end,
          }
        end,
      },
    }

    local client = HttpClient:new()
    client:request({ url = "http://example.com" }, function(res)
      cb_called = true
    end)

    UIManager.initLooper = old_init
    UIManager.setInputTimeout = old_set_to
    UIManager.resetInputTimeout = old_reset_to
    package.loaded.turbo = nil
  end)

  it("should preserve custom connect_timeout and request_timeout", function()
    local client = HttpClient:new()
    local req = {
      url = "http://example.com",
      connect_timeout = 5,
      request_timeout = 60,
    }
    client:request(req)
    assert.are.equal(5, req.connect_timeout)
    assert.are.equal(60, req.request_timeout)
  end)
end)
