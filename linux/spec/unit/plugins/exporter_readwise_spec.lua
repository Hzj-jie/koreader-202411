describe("ReadwiseExporter plugin target module", function()
  local ReadwiseExporter, http

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    http = require("socket.http")
    ReadwiseExporter = require("plugins/exporter.koplugin/target/readwise")
  end)

  it(
    "should check ready to export state based on authorization token",
    function()
      local exp = setmetatable(
        { settings = {} },
        { __index = ReadwiseExporter }
      )
      assert.is_false(exp:isReadyToExport())

      exp.settings.token = "test_auth_token"
      assert.is_true(exp:isReadyToExport())
    end
  )

  it("should generate menu table for Readwise exporter", function()
    local exp = setmetatable(
      { settings = { token = "token123" } },
      { __index = ReadwiseExporter }
    )
    exp.isEnabled = function()
      return true
    end
    exp.toggleEnabled = function() end

    local menu = exp:getMenuTable()
    assert.is_table(menu)
    assert.is_table(menu.sub_item_table)
    assert.are.equal(2, #menu.sub_item_table)
  end)

  it("should format highlights and export booknotes to Readwise API", function()
    local exp = setmetatable(
      { settings = { token = "test_token" } },
      { __index = ReadwiseExporter }
    )

    local old_request = http.request
    http.request = function(req)
      req.sink([[{"status": "ok"}]])
      return 1, 200, {}, "200 OK"
    end

    local booknotes = {
      title = "Test Book",
      author = "Author One\nAuthor Two",
      {
        {
          text = "Highlight content",
          note = "Some note",
          page = 42,
          time = 1600000000,
        },
      },
    }

    local success = exp:export({ booknotes })
    assert.is_true(success)

    http.request = old_request
  end)
end)
