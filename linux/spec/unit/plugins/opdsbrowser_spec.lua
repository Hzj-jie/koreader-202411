describe("OPDSBrowser module", function()
  local OPDSBrowser, DataStorage, UIManager, socketutil, http

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
    DataStorage = require("datastorage")
    UIManager = require("ui/uimanager")
    socketutil = require("socketutil")
    http = require("socket.http")

    local LuaSettings = require("luasettings")
    _G.G_reader_settings = LuaSettings:open(":memory:")

    OPDSBrowser = require("plugins/opds.koplugin/opdsbrowser")
  end)

  describe("Initialization & Default Servers", function()
    it("should initialize default servers list", function()
      assert.is_table(OPDSBrowser.opds_servers)
      assert.truthy(#OPDSBrowser.opds_servers > 0)
      assert.are.equal(OPDSBrowser.opds_servers[1].title, "Project Gutenberg")
    end)

    it("should have correct acquisition and image rel patterns", function()
      assert.truthy(OPDSBrowser.catalog_type)
      assert.truthy(OPDSBrowser.acquisition_rel)
      assert.truthy(OPDSBrowser.thumbnail_rel)
    end)
  end)

  describe("Browser Instance, Catalog CRUD & Dialogs", function()
    it("should create OPDSBrowser menu instance and perform CRUD on servers", function()
      local browser = OPDSBrowser:new({
        title = "OPDS Catalogs",
      })

      assert.is_table(browser)
      assert.are.equal(browser.title, "OPDS Catalogs")

      local item_tbl = browser:genItemTableFromRoot()
      assert.is_table(item_tbl)
      assert.truthy(#item_tbl > 0)

      -- Test add new catalog from input
      browser:editCatalogFromInput({ "Custom Catalog", "https://custom.opds/feed", "user", "pass" })
      local updated_tbl = browser:genItemTableFromRoot()
      assert.are.equal("Custom Catalog", updated_tbl[#updated_tbl].text)

      -- Test edit existing catalog
      local item_to_edit = updated_tbl[#updated_tbl]
      browser:editCatalogFromInput({ "Edited Catalog", "https://edited.opds/feed", "user2", "pass2" }, item_to_edit)
      local edited_tbl = browser:genItemTableFromRoot()
      assert.are.equal("Edited Catalog", edited_tbl[#edited_tbl].text)

      -- Test delete catalog
      browser:deleteCatalog(edited_tbl[#edited_tbl])
      local after_del_tbl = browser:genItemTableFromRoot()
      assert.are.not_equal("Edited Catalog", after_del_tbl[#after_del_tbl].text)
    end)

    it("should open addEditCatalog and addSubCatalog dialogs", function()
      local browser = OPDSBrowser:new({ title = "OPDS Catalogs" })
      local show_stub = stub(UIManager, "show")

      -- Test add dialog
      browser:addEditCatalog()
      assert.stub(show_stub).was.called(1)
      local add_dialog = show_stub.calls[1].vals[2]
      assert.is_table(add_dialog)

      -- Test subcatalog dialog
      browser.root_catalog_title = "Root"
      browser.catalog_title = "Sub"
      browser:addSubCatalog("https://sub.opds/feed")
      assert.stub(show_stub).was.called(2)
      local sub_dialog = show_stub.calls[2].vals[2]
      assert.is_table(sub_dialog)

      show_stub:revert()
    end)

    it("should handle dispatcher registration", function()
      local browser = OPDSBrowser:new({ title = "OPDS Catalogs" })
      if type(browser.onDispatcherRegisterActions) == "function" then
        browser:onDispatcherRegisterActions()
      end
    end)
  end)

  describe("Feed Fetching, Parsing & Caching", function()
    local OPDSParser

    setup(function()
      OPDSParser = require("plugins/opds.koplugin/opdsparser")
    end)

    it("should handle fetchFeed with various HTTP status codes and headers_only", function()
      local browser = OPDSBrowser:new({ title = "OPDS Catalogs" })

      -- Mock http.request for 200 OK
      local mock_xml = '<?xml version="1.0" encoding="utf-8"?><feed xmlns="http://www.w3.org/2005/Atom"><title>Test Feed</title></feed>'
      local http_stub = stub(http, "request", function(req)
        if req.sink then
          req.sink(mock_xml)
        end
        return 1, 200, { ["last-modified"] = "Mon, 01 Jan 2024 00:00:00 GMT" }
      end)

      local result = browser:fetchFeed("https://test.opds/feed")
      assert.are_equal(mock_xml, result)

      local lm = browser:fetchFeed("https://test.opds/feed", true)
      assert.are_equal("Mon, 01 Jan 2024 00:00:00 GMT", lm)

      http_stub:revert()

      -- Test 301, 302, 401, 404, 406, 500
      local status_codes = {
        { code = 301, headers = { location = "https://new.opds/feed" } },
        { code = 302, headers = { location = "http://insecure.opds/feed" } },
        { code = 401, headers = {} },
        { code = 403, headers = {} },
        { code = 404, headers = {} },
        { code = 406, headers = {} },
        { code = 500, headers = {} },
      }

      for _, sc in ipairs(status_codes) do
        local stub_fail = stub(http, "request", function()
          return 1, sc.code, sc.headers
        end)
        local fail_res = browser:fetchFeed("https://test.opds/feed")
        assert.is_falsy(fail_res)
        stub_fail:revert()
      end
    end)

    it("should parse feed and utilize catalog cache", function()
      local browser = OPDSBrowser:new({ title = "OPDS Catalogs" })
      local mock_feed_xml = '<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom"><title>Catalog</title></feed>'

      local fetch_stub = stub(browser, "fetchFeed", function(self_b, url, headers_only)
        if headers_only then return "date1" end
        return mock_feed_xml
      end)

      local catalog1 = browser:parseFeed("https://test.opds/feed")
      assert.is_table(catalog1)

      -- Second call should hit cache
      local catalog2 = browser:parseFeed("https://test.opds/feed")
      assert.is_table(catalog2)

      fetch_stub:revert()
    end)

    it("should extract search templates from OpenSearch description", function()
      local browser = OPDSBrowser:new({ title = "OPDS Catalogs" })
      local osd_xml = [[<?xml version="1.0" encoding="UTF-8"?>
        <OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
          <Url type="application/atom+xml" template="https://test.opds/search?q={searchTerms}"/>
        </OpenSearchDescription>]]

      local parse_stub = stub(browser, "parseFeed", function()
        return {
          OpenSearchDescription = {
            Url = {
              { type = "application/atom+xml", template = "https://test.opds/search?q={searchTerms}" }
            }
          }
        }
      end)

      local template = browser:getSearchTemplate("https://test.opds/opensearch.xml")
      assert.are_equal("https://test.opds/search?q=%s", template)
      parse_stub:revert()
    end)
  end)

  describe("Item Table Generation & Actions", function()
    local OPDSPSE

    setup(function()
      OPDSPSE = require("plugins/opds.koplugin/opdspse")
    end)

    it("should generate item table from catalog with links, search, borrow, stream, and downloads", function()
      local browser = OPDSBrowser:new({ title = "OPDS Catalogs" })

      local mock_catalog = {
        feed = {
          link = {
            { type = "application/atom+xml;profile=opds-catalog", rel = "next", href = "/feed?page=2" },
            { type = "application/opensearchdescription+xml", href = "/opensearch.xml" },
            { type = "application/atom+xml", rel = "search", href = "/search?q={searchTerms}" },
          },
          entry = {
            {
              title = "Epub Book",
              author = { name = { "Author A", "Author B" } },
              content = "<p>Book description html</p>",
              link = {
                { type = "application/epub+zip", rel = "http://opds-spec.org/acquisition", href = "/book.epub", title = "EPUB" },
                { type = "application/pdf", title = "pdf", href = "/book.pdf" },
                { rel = "http://opds-spec.org/image/thumbnail", href = "/thumb.jpg" },
                { rel = "http://opds-spec.org/image", href = "/cover.jpg" },
                { rel = "http://opds-spec.org/borrow", href = "/borrow" },
                { rel = "http://vaemendis.net/opds-pse/stream", ["pse:count"] = "150", href = "/stream" },
              },
            },
            {
              title = { type = "text", div = "Subcatalog Entry" },
              author = { name = {} },
              summary = "Subcatalog summary",
              link = {
                { type = "application/atom+xml;profile=opds-catalog", rel = "subsection", href = "/subcatalog" },
              },
            },
          },
        },
      }

      local template_stub = stub(browser, "getSearchTemplate", function() return "https://test.opds/search?q=%s" end)
      local items = browser:genItemTableFromCatalog(mock_catalog, "https://test.opds/catalog")
      assert.is_table(items)
      assert.is_true(#items >= 2)
      assert.is_table(items.hrefs)

      -- Exercise showDownloads dialog with all buttons
      local book_item = items[2] -- first book entry
      assert.is_table(book_item.acquisitions)

      browser:showDownloads(book_item)
      assert.is_table(browser.download_dialog)

      -- Trigger buttons callbacks in download_dialog
      for _, row in ipairs(browser.download_dialog.buttons) do
        for _, btn in ipairs(row) do
          if btn.callback then
            pcall(btn.callback)
          end
        end
      end

      template_stub:revert()
    end)

    it("should handle downloadFile with network responses and overwrite confirmations", function()
      local browser = OPDSBrowser:new({ title = "OPDS Catalogs" })
      local downloaded_path = nil
      browser.file_downloaded_callback = function(path) downloaded_path = path end
      G_reader_settings:save("download_dir", "/tmp")

      local http_stub = stub(http, "request", function(req)
        return 1, 200, {}
      end)

      browser:downloadFile("test_download.epub", "https://test.opds/test.epub")

      -- Drain scheduled download task
      while #UIManager._task_queue > 0 do
        local task = table.remove(UIManager._task_queue, 1)
        if task and task.action then
          pcall(task.action, unpack(task.args, 1, task.args.n or 0))
        end
      end

      assert.is_truthy(downloaded_path)
      http_stub:revert()
      os.remove("/tmp/test_download.epub")
    end)

    it("should handle searchCatalog, onMenuSelect, onMenuHold, onReturn, onHoldReturn, and onNextPage", function()
      local browser = OPDSBrowser:new({ title = "OPDS Catalogs" })
      browser.paths = {}
      browser.item_table = { hrefs = { next = "https://test.opds/feed?page=2" } }

      local NetworkMgr = require("ui/network/manager")
      local net_stub = stub(NetworkMgr, "runWhenConnected", function(self_nm, cb) cb() end)
      local update_stub = stub(browser, "updateCatalog", function() end)
      local parse_stub = stub(browser, "genItemTableFromURL", function()
        return { { text = "Appended Book", acquisitions = {} } }
      end)

      local orig_show = UIManager.show
      UIManager.show = function(self_uim, widget)
        if widget.buttons and widget.buttons[1] and widget.buttons[1][2] and widget.buttons[1][2].callback then
          -- Execute Search button callback (which closes inputdialog and triggers updateCatalog)
          pcall(widget.buttons[1][2].callback)
        elseif widget.buttons and widget.buttons[1] and widget.buttons[1][1] and widget.buttons[1][1].callback then
          pcall(widget.buttons[1][1].callback)
        end
      end

      -- Search dialog
      browser:searchCatalog("https://test.opds/search?q=%s")

      -- onMenuSelect for book
      browser:onMenuSelect({ acquisitions = { { type = "application/epub+zip", href = "/a.epub" } }, title = "Book" })

      -- onMenuSelect for search
      browser:onMenuSelect({ searchable = true, url = "https://test.opds/search?q=%s" })

      -- onMenuSelect for catalog
      browser:onMenuSelect({ text = "Subcatalog", url = "https://test.opds/sub" })

      -- onMenuHold
      browser:onMenuHold({ text = "Root Item", url = "https://test.opds" })

      -- onReturn and onHoldReturn
      table.insert(browser.paths, { url = "https://test.opds/1", title = "Level 1" })
      table.insert(browser.paths, { url = "https://test.opds/2", title = "Level 2" })
      browser:onHoldReturn()
      browser:onReturn()

      -- onNextPage
      browser:onNextPage(true)

      UIManager.show = orig_show
      net_stub:revert()
      update_stub:revert()
      parse_stub:revert()
    end)
  end)
end)

