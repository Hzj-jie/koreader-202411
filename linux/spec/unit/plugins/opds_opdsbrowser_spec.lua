-- luacheck: ignore 122
describe("OPDS Browser plugin module", function()
  local OPDSBrowser, http, socket, UIManager

  setup(function()
    require("commonrequire")
    OPDSBrowser = require("plugins/opds.koplugin/opdsbrowser")
    http = require("socket.http")
    socket = require("socket")
    UIManager = require("ui/uimanager")
  end)

  local function create_mock_browser(servers)
    local browser = {
      opds_servers = servers or {
        {
          title = "Project Gutenberg",
          url = "https://m.gutenberg.org/ebooks.opds/?format=opds",
        },
        {
          title = "Standard Ebooks",
          url = "https://standardebooks.org/feeds/opds",
        },
      },
      catalog_type = "application/atom%+xml",
      search_type = "application/opensearchdescription%+xml",
      search_template_type = "application/atom%+xml",
      acquisition_rel = "^http://opds%-spec%.org/acquisition",
      borrow_rel = "http://opds-spec.org/acquisition/borrow",
      image_rel = "http://opds-spec.org/image",
      thumbnail_rel = "http://opds-spec.org/image/thumbnail",
      root_catalog_title = "Root",
    }
    setmetatable(browser, { __index = OPDSBrowser })
    return browser
  end

  describe("Root catalog management", function()
    it(
      "generates root catalog item table from server configurations",
      function()
        local browser = create_mock_browser({
          {
            title = "Gutenberg",
            url = "https://gutenberg.org/opds",
          },
          {
            title = "Private Library",
            url = "https://library.local/opds/%s",
            username = "user1",
            password = "secret",
          },
        })

        local items = browser:genItemTableFromRoot()
        assert.is_table(items)
        assert.are.equal(2, #items)
        assert.are.equal("Gutenberg", items[1].text)
        assert.is_false(items[1].searchable)
        assert.is_nil(items[1].mandatory)

        assert.are.equal("Private Library", items[2].text)
        assert.is_true(items[2].searchable)
        assert.is_string(items[2].mandatory)
      end
    )

    it("adds, edits, and deletes catalog entries", function()
      local browser = create_mock_browser({
        { title = "Initial", url = "http://initial.com" },
      })
      browser.init = function(self)
        self.item_table = self:genItemTableFromRoot()
      end

      -- Add new catalog
      browser:editCatalogFromInput({
        "New Catalog",
        "http://newcatalog.com",
        "myuser",
        "mypass",
      }, nil, true)
      assert.are.equal(2, #browser.opds_servers)
      assert.are.equal("New Catalog", browser.opds_servers[2].title)
      assert.are.equal("myuser", browser.opds_servers[2].username)

      -- Edit existing catalog
      local item_to_edit = {
        text = "Initial",
        url = "http://initial.com",
      }
      browser:editCatalogFromInput({
        "Updated Initial",
        "http://updated.com",
        "",
        "",
      }, item_to_edit, true)
      assert.are.equal(2, #browser.opds_servers)
      assert.are.equal("Updated Initial", browser.opds_servers[1].title)
      assert.are.equal("http://updated.com", browser.opds_servers[1].url)

      -- Delete catalog
      browser:deleteCatalog({
        text = "Updated Initial",
        url = "http://updated.com",
      })
      assert.are.equal(1, #browser.opds_servers)
      assert.are.equal("New Catalog", browser.opds_servers[1].title)
    end)
  end)

  describe("Catalog parsing and items generation", function()
    it(
      "extracts entries, acquisitions, and links from catalog table",
      function()
        local browser = create_mock_browser()
        local catalog = {
          feed = {
            entry = {
              {
                title = "Moby Dick",
                id = "urn:moby-dick",
                link = {
                  {
                    rel = "http://opds-spec.org/acquisition",
                    href = "/download/moby.epub",
                    type = "application/epub+zip",
                  },
                  {
                    rel = "http://opds-spec.org/image",
                    href = "/covers/moby.jpg",
                    type = "image/jpeg",
                  },
                },
              },
            },
          },
        }

        local items =
          browser:genItemTableFromCatalog(catalog, "https://books.org/catalog")
        assert.is_table(items)
        assert.are.equal(1, #items)
        local book = items[1]
        assert.are.equal("Moby Dick", book.text)
        assert.is_table(book.acquisitions)
        assert.are.equal(1, #book.acquisitions)
        assert.are.equal(
          "https://books.org/download/moby.epub",
          book.acquisitions[1].href
        )
      end
    )
  end)

  describe("Defect verifications", function()
    it(
      "fails: exposes genItemTableFromCatalog creating invalid search entry when getSearchTemplate returns nil",
      function()
        local browser = create_mock_browser()
        local catalog = {
          feed = {
            link = {
              {
                rel = "search",
                type = "application/opensearchdescription+xml",
                href = "/opensearch.xml",
              },
            },
            entry = {},
          },
        }

        -- Stub getSearchTemplate to return nil (e.g. unreachable search descriptor)
        browser.getSearchTemplate = function()
          return nil
        end

        -- In opdsbrowser.lua line 406:
        -- url = build_href(self:getSearchTemplate(build_href(link.href)))
        -- When getSearchTemplate returns nil, build_href(nil) returns the base catalog URL.
        -- The search entry is inserted with url = "https://books.org/catalog", which lacks %s.
        -- When tapped, searchCatalog fails to format the query into the URL.
        local res =
          browser:genItemTableFromCatalog(catalog, "https://books.org/catalog")
        assert.is_table(res)
        assert.are.equal(1, #res)
        assert.is_truthy(
          res[1].url:find("%%s"),
          "Search item URL must contain '%s' placeholder when search is available"
        )
      end
    )

    it(
      "fails: exposes fetchFeed crashing on HTTP 302 redirect when Location header is missing",
      function()
        local browser = create_mock_browser()
        local orig_request = http.request
        local orig_show = UIManager.show

        UIManager.show = function() end

        -- Mock http.request to return status 302 from HTTPS without Location header
        http.request = function(req)
          return 1, 302, {}, "HTTP/1.1 302 Found"
        end
        finally(function()
          http.request = orig_request
          UIManager.show = orig_show
        end)

        -- In opdsbrowser.lua line 277-279:
        -- if headers and code == 302 and item_url:match("^https") and headers.location:match("^http[^s]") then
        -- When headers.location is nil, headers.location:match(...) throws:
        -- attempt to index field 'location' (a nil value).
        -- The test asserts that fetchFeed handles missing location header without crashing.
        local ok, res = pcall(function()
          return browser:fetchFeed("https://secure.example.com/feed")
        end)

        assert.is_true(
          ok,
          "fetchFeed should not crash on 302 redirect with missing Location header: "
            .. tostring(res)
        )
      end
    )
  end)
end)
