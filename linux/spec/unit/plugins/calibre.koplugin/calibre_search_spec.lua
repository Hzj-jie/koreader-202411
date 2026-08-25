describe("Calibre Search plugin module", function()
  local CalibreSearch, CalibreMetadata, DataStorage, Device, UIManager, Persist, Calibre
  local mock_ui, search_instance

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    DataStorage = require("datastorage")
    Device = require("device")
    UIManager = require("ui/uimanager")
    Persist = require("persist")
    Calibre = require("plugins/calibre.koplugin/main")
    CalibreMetadata = require("plugins/calibre.koplugin/metadata")
    CalibreSearch = require("plugins/calibre.koplugin/search")
  end)

  before_each(function()
    stub(UIManager, "show")
    stub(UIManager, "close")

    mock_ui = {
      menu = { registerToMainMenu = stub() },
      document = nil,
    }
    search_instance = CalibreSearch
    search_instance.search_menu = nil
    search_instance.search_dialog = nil
    search_instance.search_value = ""
    search_instance.books = {
      {
        title = "The Hobbit",
        authors = { "J.R.R. Tolkien" },
        series = "Middle Earth",
        series_index = 1,
        tags = { "Fantasy", "Classic" },
        size = 1048576,
        filepath = "Middle Earth/The Hobbit.epub",
        lpath = "Middle Earth/The Hobbit.epub",
        rootpath = "/books",
      },
      {
        title = "The Fellowship of the Ring",
        authors = { "J.R.R. Tolkien" },
        series = "Middle Earth",
        series_index = 2,
        tags = { "Fantasy", "Adventure" },
        size = 2097152,
        filepath = "Middle Earth/Fellowship.epub",
        lpath = "Middle Earth/Fellowship.epub",
        rootpath = "/books",
      },
      {
        title = "Dune",
        authors = { "Frank Herbert" },
        series = "Dune Chronicles",
        series_index = 1,
        tags = { "Sci-Fi", "Classic" },
        size = 1572864,
        filepath = "Sci-Fi/Dune.epub",
        lpath = "Sci-Fi/Dune.epub",
        rootpath = "/books",
      },
    }
    search_instance.libraries = {
      "/books",
      ["/books"] = true,
    }
    search_instance.cache_libs = {
      load = function()
        return { "/books", ["/books"] = true }
      end,
      save = function() end,
    }
  end)

  after_each(function()
    UIManager.show:revert()
    UIManager.close:revert()
  end)

  describe("Searching by Fields and Nested Fields", function()
    it("should browse series correctly", function()
      search_instance.search_value = ""
      search_instance:find("series")
      assert.is_table(search_instance.search_menu)
      assert.is_table(search_instance.search_menu.item_table)
    end)

    it("should browse tags correctly", function()
      search_instance.search_value = ""
      search_instance:find("tags")
      assert.is_table(search_instance.search_menu)
      assert.is_table(search_instance.search_menu.item_table)
    end)

    it("should browse authors correctly", function()
      search_instance.search_value = ""
      search_instance:find("authors")
      assert.is_table(search_instance.search_menu)
      assert.is_table(search_instance.search_menu.item_table)
    end)

    it("should browse titles correctly", function()
      search_instance.search_value = ""
      search_instance:find("title")
      assert.is_table(search_instance.search_menu)
      assert.is_table(search_instance.search_menu.item_table)
    end)

    it("should find books matching search value", function()
      search_instance.search_value = "Hobbit"
      search_instance:find("find")
      assert.is_table(search_instance.search_menu)
      assert.is_table(search_instance.search_menu.item_table)
    end)
  end)

  describe("Expanding Search Results", function()
    it("should expand series results", function()
      search_instance:find("series")
      search_instance:expandSearchResults("series", "Middle Earth")
      assert.is_table(search_instance.search_menu)
    end)

    it("should expand tag results", function()
      search_instance:find("tags")
      search_instance:expandSearchResults("tags", "Fantasy")
      assert.is_table(search_instance.search_menu)
    end)

    it("should expand author results", function()
      search_instance:find("authors")
      search_instance:expandSearchResults("authors", "Frank Herbert")
      assert.is_table(search_instance.search_menu)
    end)

    it("should expand title results", function()
      search_instance:find("title")
      search_instance:expandSearchResults("title", "Dune")
      assert.is_table(search_instance.search_menu)
    end)
  end)

  describe("Search Dialog and UI Interaction", function()
    it("should open search dialog and trigger browse buttons", function()
      search_instance:ShowSearch()
      assert.stub(UIManager.show).was.called()
      local dialog = UIManager.show.calls[1].vals[2]
      assert.is_table(dialog)

      -- Browse series callback
      dialog.buttons[1][1].callback()
      assert.are.equal("series", search_instance.lastsearch)

      -- Browse tags callback
      dialog.buttons[1][2].callback()
      assert.are.equal("tags", search_instance.lastsearch)

      -- Browse authors callback
      dialog.buttons[2][1].callback()
      assert.are.equal("authors", search_instance.lastsearch)

      -- Browse titles callback
      dialog.buttons[2][2].callback()
      assert.are.equal("title", search_instance.lastsearch)

      -- Search books callback
      dialog.buttons[3][2].callback()
      assert.are.equal("find", search_instance.lastsearch)

      -- Cancel button callback
      dialog.buttons[3][1].callback()
    end)

    it("should populate Main Menu with Calibre entries", function()
      local calibre = Calibre:new({ ui = mock_ui })
      local menu_items = {}
      calibre:addToMainMenu(menu_items)

      assert.is_table(menu_items.calibre)
      assert.is_table(menu_items.calibre.sub_item_table)
      assert.is_true(#menu_items.calibre.sub_item_table >= 3)
    end)

    it("should handle dispatcher actions and browse helpers", function()
      local calibre = Calibre:new({ ui = mock_ui })
      calibre:onDispatcherRegisterActions()
      calibre:onCalibreSearch()
      calibre:onCalibreBrowseBy("series")
      calibre:onNetworkDisconnected()
      calibre:onSuspend()
      calibre:onExit()
    end)
  end)
end)
