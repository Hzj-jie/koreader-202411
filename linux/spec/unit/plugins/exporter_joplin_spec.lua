-- luacheck: ignore 122
describe("Exporter Joplin target module", function()
  local JoplinExporter, http, UIManager, MultiInputDialog, InputDialog, json

  setup(function()
    require("commonrequire")
    JoplinExporter = require("plugins/exporter.koplugin/target/joplin")
    http = require("socket.http")
    UIManager = require("ui/uimanager")
    MultiInputDialog = require("ui/widget/multiinputdialog")
    InputDialog = require("ui/widget/inputdialog")
    json = require("json")
  end)

  local function create_mock_exporter()
    local exp = JoplinExporter:new({ name = "joplin" })
    exp.settings = {
      ip = "127.0.0.1",
      port = 41184,
      token = "test_token_123",
      enabled = true,
    }
    return exp
  end

  describe("Readiness and Menu", function()
    it("checks readiness based on ip, port, and token", function()
      local exp = JoplinExporter:new({ name = "joplin" })
      exp.settings = {}
      assert.is_falsy(exp:isReadyToExport())

      exp.settings.ip = "127.0.0.1"
      assert.is_falsy(exp:isReadyToExport())

      exp.settings.port = 41184
      assert.is_falsy(exp:isReadyToExport())

      exp.settings.token = "abc"
      assert.is_truthy(exp:isReadyToExport())
    end)

    it("constructs menu table with sub items", function()
      local exp = create_mock_exporter()
      local menu = exp:getMenuTable()
      assert.is_table(menu)
      assert.is_table(menu.sub_item_table)
      assert.are.equal(4, #menu.sub_item_table)
    end)
  end)

  describe("API requests and note export", function()
    it("handles ping and notebook existence checks", function()
      local exp = create_mock_exporter()
      local orig_request = http.request

      http.request = function(req)
        if req.url:find("/ping") then
          req.sink("JoplinClipperServer")
        elseif req.url:find("/folders") then
          req.sink(json.encode({
            items = {
              { id = "folder_1", title = "KOReader Notes" },
            },
          }))
        end
        return 1
      end
      finally(function()
        http.request = orig_request
      end)

      local exists = exp:notebookExist("KOReader Notes")
      assert.are.equal("folder_1", exists)

      local not_exists = exp:notebookExist("Nonexistent Folder")
      assert.is_false(not_exists)
    end)

    it("exports notes successfully when Joplin server responds", function()
      local exp = create_mock_exporter()
      local orig_request = http.request

      http.request = function(req)
        if req.url:find("/ping", 1, true) then
          req.sink("JoplinClipperServer")
        elseif req.method == "POST" and req.url:find("/notes", 1, true) then
          req.sink(json.encode({
            id = "new_note_1",
          }))
        elseif req.url:find("/folders", 1, true) then
          req.sink(json.encode({
            items = {
              { id = "folder_1", title = exp.notebook_name },
            },
          }))
        elseif req.url:find("/notes", 1, true) then
          req.sink(json.encode({
            has_more = false,
            items = {},
          }))
        end
        return 1
      end
      finally(function()
        http.request = orig_request
      end)

      G_reader_settings:save("exporter", {
        markdown = {
          formatting_options = {},
          highlight_formatting = false,
        },
      })

      local test_data = {
        ["Test Book"] = {
          title = "Test Book",
          author = "Author Name",
          {
            {
              chapter = "Chapter 1",
              page = 1,
              time = os.time(),
              text = "Sample highlight text",
              drawer = "lighten",
            },
          },
        },
      }

      local ok = exp:export(test_data)
      assert.is_true(ok)
    end)
  end)

  describe("Defect verifications", function()
    it("accepts valid ports up to 65535 in port validation", function()
      local exp = create_mock_exporter()
      exp.settings.port = 41184
      exp.saveSettings = function() end

      local menu = exp:getMenuTable()
      local ip_port_item = menu.sub_item_table[1]
      assert.is_table(ip_port_item)

      local orig_new = MultiInputDialog.new
      local captured_dlg = nil
      MultiInputDialog.new = function(self, args)
        captured_dlg = orig_new(self, args)
        return captured_dlg
      end
      local orig_show = UIManager.show
      local orig_close = UIManager.close
      UIManager.show = function() end
      UIManager.close = function() end
      finally(function()
        MultiInputDialog.new = orig_new
        UIManager.show = orig_show
        UIManager.close = orig_close
      end)

      ip_port_item.callback()
      assert.is_table(captured_dlg)

      captured_dlg.getFields = function()
        return { "192.168.1.50", "65500" }
      end

      -- Click OK button (button 2 in group 1)
      local ok_btn = captured_dlg.buttons[1][2]
      assert.are.equal("OK", ok_btn.text)
      ok_btn.callback()

      -- Valid port (<= 65535) is accepted
      assert.are.equal(65500, exp.settings.port)
    end)
  end)
end)
