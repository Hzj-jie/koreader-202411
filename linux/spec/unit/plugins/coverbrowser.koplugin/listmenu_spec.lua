describe("Coverbrowser ListMenu module", function()
  local ListMenu, Geom, BookInfoManager, UIManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Geom = require("ui/geometry")
    UIManager = require("ui/uimanager")
    BookInfoManager = require("plugins/coverbrowser.koplugin/bookinfomanager")
    BookInfoManager:init()
    ListMenu = require("plugins/coverbrowser.koplugin/listmenu")
  end)

  after_each(function()
    UIManager._task_queue = {}
    UIManager._next_tick_tasks = {}
  end)

  describe("Initialization & Mixin", function()
    it("should expose ListMenu methods table", function()
      assert.is_table(ListMenu)
      assert.is_function(ListMenu._recalculateDimen)
      assert.is_function(ListMenu._updateItemsBuildUI)
    end)

    it("should recalculate dimensions in portrait and landscape", function()
      local mock_menu = {
        item_table = {
          { text = "Book 1", path = "/tmp/book1.epub" },
        },
        page = 1,
        perpage = 1,
        width = 400,
        height = 600,
        item_group = { clear = function() end, appendWidget = function() end },
        layout = {},
        items_to_update = {},
        path_items = {},
        inner_dimen = Geom:new({ x = 0, y = 0, w = 400, h = 600 }),
        item_dimen = Geom:new({ x = 0, y = 0, w = 400, h = 50 }),
      }
      setmetatable(mock_menu, { __index = ListMenu })

      mock_menu:_recalculateDimen()
      assert.is_boolean(mock_menu.portrait_mode)
      assert.is_number(mock_menu.perpage)
      assert.is_number(mock_menu.item_height)
    end)

    it("should build UI items for directories and files", function()
      local mock_menu = {
        item_table = {
          { text = "Folder 1", path = "/tmp", is_directory = true },
          { text = "Book 1", path = "/tmp/book1.epub" },
        },
        page = 1,
        perpage = 5,
        width = 400,
        height = 600,
        item_group = {},
        layout = {},
        items_to_update = {},
        path_items = {},
        inner_dimen = Geom:new({ x = 0, y = 0, w = 400, h = 600 }),
        item_dimen = Geom:new({ x = 0, y = 0, w = 400, h = 60 }),
        select_number = 1,
        is_path_chooser = false,
        _do_cover_images = true,
        _do_filename_only = false,
        _do_hint_opened = true,
        onMenuSelect = function() end,
        onMenuHold = function() end,
      }
      setmetatable(mock_menu, { __index = ListMenu })

      mock_menu:_recalculateDimen()
      local sel = mock_menu:_updateItemsBuildUI()
      assert.is_nil(sel or nil)
      assert.is_true(#mock_menu.item_group >= 1)

      -- Exercise items
      for _, item_widget in ipairs(mock_menu.item_group) do
        if item_widget.getHoldMessage then
          pcall(function() item_widget:getHoldMessage() end)
        end
        if item_widget.onTapSelect then
          pcall(function() item_widget:onTapSelect() end)
        end
        if item_widget.onHoldSelect then
          pcall(function() item_widget:onHoldSelect() end)
        end
      end
    end)

    it("should build and paint items with rich bookinfo, covers, and sidecar data", function()
      local Blitbuffer = require("ffi/blitbuffer")
      local DocSettings = require("docsettings")

      local sample_cover = Blitbuffer.new(60, 90, Blitbuffer.TYPE_BB8)
      local mock_bookinfo = {
        title = "Rich Sample Book",
        authors = "Author One\nAuthor Two",
        series = "Test Series",
        series_index = 3,
        has_cover = "Y",
        cover_w = 60,
        cover_h = 90,
        cover_sizetag = "60x90",
        cover_bb = sample_cover,
        description = "A detailed book description for testing list item widgets.",
        pages = 420,
        cover_fetched = "Y",
      }

      local get_stub = stub(BookInfoManager, "getBookInfo", function() return mock_bookinfo end)
      local sidecar_stub = stub(DocSettings, "hasSidecarFile", function() return true end)

      local mock_menu = {
        item_table = {
          { text = "Rich Book 1", path = "/tmp/rich_book1.epub", is_file = true, mandatory = "1.2 MB" },
          { text = "Rich Book 2", path = "/tmp/rich_book2.epub", is_file = true, mandatory = "2.5 MB" },
        },
        page = 1,
        perpage = 5,
        width = 400,
        height = 600,
        item_group = {},
        layout = {},
        items_to_update = {},
        path_items = {},
        inner_dimen = Geom:new({ x = 0, y = 0, w = 400, h = 600 }),
        item_dimen = Geom:new({ x = 0, y = 0, w = 400, h = 100 }),
        select_number = 1,
        is_path_chooser = false,
        _do_cover_images = true,
        _do_filename_only = false,
        _do_hint_opened = true,
        updateCache = function(self_m, path, _, _, pages)
          self_m.cover_info_cache[path] = { pages or 420, 0.5, "reading", true }
          self_m.cover_info_cache[path].n = 4
        end,
        cover_info_cache = {},
        onMenuSelect = function() end,
        onMenuHold = function() end,
      }
      setmetatable(mock_menu, { __index = ListMenu })

      mock_menu:_recalculateDimen()
      mock_menu:_updateItemsBuildUI()
      assert.is_true(#mock_menu.item_group >= 2)

      local bb = Blitbuffer.new(400, 600)
      for _, item_widget in ipairs(mock_menu.item_group) do
        if item_widget.paintTo then
          item_widget:paintTo(bb, 0, 0)
        end
        if item_widget.getHoldMessage then
          local msg = item_widget:getHoldMessage()
          assert.is_string(msg)
        end
        if item_widget.onTapSelect then
          item_widget:onTapSelect()
        end
        if item_widget.onHoldSelect then
          item_widget:onHoldSelect()
        end
      end

      get_stub:revert()
      sidecar_stub:revert()
      sample_cover:free()
    end)
  end)
end)
