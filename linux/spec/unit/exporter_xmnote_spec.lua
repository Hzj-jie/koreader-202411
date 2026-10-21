-- luacheck: ignore 122
local http = require("socket.http")

describe("XMNoteExporter module", function()
  local XMNoteExporter

  setup(function()
    require("commonrequire")
    XMNoteExporter = require("plugins/exporter.koplugin/target/xmnote")
  end)

  it("decodes multi-chunk JSON responses in makeRequest", function()
    local orig_request = http.request
    http.request = function(req)
      if req.sink then
        req.sink('{"code": 200, "message": ')
        req.sink('"ok", "data": 123}')
      end
      return 1, 200, {}, "OK"
    end
    finally(function()
      http.request = orig_request
    end)

    XMNoteExporter.settings = {
      ip = "127.0.0.1",
    }

    local res, err =
      XMNoteExporter:makeRequest("/test", "POST", { test = true })
    assert.is_nil(err)
    assert.is_table(res)
    assert.are.equal(200, res.code)
    assert.are.equal(123, res.data)
  end)
end)
