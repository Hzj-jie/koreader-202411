describe("Nextcloud Exporter target module", function()
  local NextcloudExporter, http

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    http = require("socket.http")
    NextcloudExporter = require("plugins/exporter.koplugin/target/nextcloud")
  end)

  it("should check readiness based on host, username, and password", function()
    NextcloudExporter.settings = {}
    assert.is_falsy(NextcloudExporter:isReadyToExport())

    NextcloudExporter.settings = {
      host = "https://nextcloud.example.com",
      username = "user1",
      password = "secretpassword",
    }
    assert.is_truthy(NextcloudExporter:isReadyToExport())
  end)

  it("should build menu table with configuration callbacks", function()
    NextcloudExporter.isEnabled = function() return true end
    local menu = NextcloudExporter:getMenuTable()

    assert.is_table(menu)
    assert.are.equal("Nextcloud Notes", menu.text)
    assert.is_table(menu.sub_item_table)
    assert.are.equal(3, #menu.sub_item_table)
  end)

  it("should export book notes to Nextcloud API", function()
    NextcloudExporter.settings = {
      host = "https://nextcloud.example.com",
      username = "user1",
      password = "secretpassword",
    }
    G_reader_settings:save("exporter", {
      markdown = {
        formatting_options = {
          light = 1,
        },
        highlight_formatting = false,
      },
    })

    local old_request = http.request
    http.request = function(req)
      if req.method == "GET" then
        req.sink('[{"id": 42, "title": "Author - Test Book"}]')
      else
        req.sink('{"id": 42}')
      end
      return 1, 200, {}, "200 OK"
    end

    local notes = {
      {
        title = "Test Book",
        author = "Author",
        {
          { text = "Sample clipping", page = 1, time = 1715774400, chapter = "Ch 1" },
        },
      },
    }

    assert.is_true(NextcloudExporter:export(notes))

    http.request = old_request
  end)
end)
