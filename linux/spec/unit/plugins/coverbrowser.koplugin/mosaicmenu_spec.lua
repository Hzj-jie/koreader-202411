local Geom = require("ui/geometry")

describe("Coverbrowser MosaicMenu unit tests", function()
  local MosaicMenu
  local Device, Screen
  local orig_getWidth, orig_getHeight, orig_scaleBySize

  setup(function()
    require("commonrequire")
    if not _G.G_reader_settings then
      local LuaSettings = require("luasettings")
      _G.G_reader_settings = LuaSettings:open(":memory:")
    end
    MosaicMenu = require("plugins/coverbrowser.koplugin/mosaicmenu")
    Device = require("device")
    Screen = Device.screen

    orig_getWidth = Screen.getWidth
    orig_getHeight = Screen.getHeight
    orig_scaleBySize = Screen.scaleBySize
  end)

  after_each(function()
    Screen.getWidth = orig_getWidth
    Screen.getHeight = orig_getHeight
    Screen.scaleBySize = orig_scaleBySize
  end)

  local function createMockMenu(opts)
    opts = opts or {}
    local menu = {
      nb_cols_portrait = opts.nb_cols_portrait or 3,
      nb_rows_portrait = opts.nb_rows_portrait or 4,
      nb_cols_landscape = opts.nb_cols_landscape or 4,
      nb_rows_landscape = opts.nb_rows_landscape or 3,
      item_table = opts.item_table or {},
      page = opts.page or 1,
      inner_dimen = opts.inner_dimen
        or Geom:new({ x = 0, y = 0, w = 600, h = 800 }),
      layout = {},
      item_group = {},
      items_to_update = {},
      title_bar = opts.title_bar,
      page_info = opts.page_info,
      is_borderless = opts.is_borderless or false,
      no_title = opts.no_title or false,
      _do_center_partial_rows = opts.center_partial or false,
      _do_cover_images = opts.do_covers or false,
      _do_hint_opened = opts.do_hint or false,
      itemnumber = opts.itemnumber,
      cover_info_cache = opts.cover_info_cache or {},
      updateCache = opts.updateCache or function(self_m, path, _, _, pages)
        self_m.cover_info_cache[path] = { pages or 100, 0.5, "reading" }
        self_m.cover_info_cache[path].n = 3
      end,
    }
    menu._recalculateDimen = MosaicMenu._recalculateDimen
    menu._updateItemsBuildUI = MosaicMenu._updateItemsBuildUI
    return menu
  end

  describe("Module initialization", function()
    it("should export required methods", function()
      assert.is_table(MosaicMenu)
      assert.is_function(MosaicMenu._recalculateDimen)
      assert.is_function(MosaicMenu._updateItemsBuildUI)
    end)
  end)

  describe("Grid & Item Sizing Calculations (_recalculateDimen)", function()
    it("should calculate dimensions in portrait mode", function()
      Screen.getWidth = function()
        return 600
      end
      Screen.getHeight = function()
        return 800
      end
      Screen.scaleBySize = function(_, size)
        return size
      end

      local items = {}
      for i = 1, 25 do
        table.insert(items, { text = "Item " .. i, is_file = true })
      end

      local menu = createMockMenu({
        nb_cols_portrait = 3,
        nb_rows_portrait = 4,
        nb_cols_landscape = 5,
        nb_rows_landscape = 3,
        item_table = items,
        inner_dimen = Geom:new({ x = 0, y = 0, w = 600, h = 800 }),
      })

      menu:_recalculateDimen()

      assert.True(menu.portrait_mode)
      assert.are.equal(3, menu.nb_cols)
      assert.are.equal(4, menu.nb_rows)
      assert.are.equal(12, menu.perpage)
      assert.are.equal(3, menu.page_num) -- math.ceil(25 / 12)
      assert.is_table(menu.item_dimen)
      assert.are.equal(menu.item_width, menu.item_dimen.w)
      assert.are.equal(menu.item_height, menu.item_dimen.h)
    end)

    it(
      "should calculate exact item width and height from inner_dimen",
      function()
        Screen.getWidth = function()
          return 600
        end
        Screen.getHeight = function()
          return 800
        end
        Screen.scaleBySize = function(_, size)
          return size
        end

        local menu = createMockMenu({
          nb_cols_portrait = 2,
          nb_rows_portrait = 3,
          inner_dimen = Geom:new({ x = 0, y = 0, w = 600, h = 900 }),
          no_title = true,
        })

        menu:_recalculateDimen()

        -- margin = 10
        -- item_width = floor((600 - (1 + 2) * 10) / 2) = floor(570 / 2) = 285
        -- item_height = floor((900 - 0 - (1 + 3) * 10) / 3) = floor(860 / 3) = 286
        assert.are.equal(285, menu.item_width)
        assert.are.equal(286, menu.item_height)
      end
    )

    it("should calculate dimensions in landscape mode", function()
      Screen.getWidth = function()
        return 1024
      end
      Screen.getHeight = function()
        return 768
      end
      Screen.scaleBySize = function(_, size)
        return size
      end

      local items = {}
      for i = 1, 20 do
        table.insert(items, { text = "Item " .. i, is_file = true })
      end

      local menu = createMockMenu({
        nb_cols_portrait = 3,
        nb_rows_portrait = 4,
        nb_cols_landscape = 5,
        nb_rows_landscape = 2,
        item_table = items,
        inner_dimen = Geom:new({ x = 0, y = 0, w = 1024, h = 768 }),
      })

      menu:_recalculateDimen()

      assert.False(menu.portrait_mode)
      assert.are.equal(5, menu.nb_cols)
      assert.are.equal(2, menu.nb_rows)
      assert.are.equal(10, menu.perpage)
      assert.are.equal(2, menu.page_num) -- math.ceil(20 / 10)
    end)

    it("should adjust page number if current page exceeds page_num", function()
      Screen.getWidth = function()
        return 600
      end
      Screen.getHeight = function()
        return 800
      end
      Screen.scaleBySize = function(_, size)
        return size
      end

      local items = {}
      for i = 1, 10 do
        table.insert(items, { text = "Item " .. i, is_file = true })
      end

      local menu = createMockMenu({
        nb_cols_portrait = 2,
        nb_rows_portrait = 3,
        page = 5, -- out of range (max pages = math.ceil(10 / 6) = 2)
        item_table = items,
      })

      menu:_recalculateDimen()

      assert.are.equal(2, menu.page_num)
      assert.are.equal(2, menu.page)
    end)

    it(
      "should account for title bar and page info in available height",
      function()
        Screen.getWidth = function()
          return 600
        end
        Screen.getHeight = function()
          return 800
        end
        Screen.scaleBySize = function(_, size)
          return size
        end

        local mock_title = {
          getSize = function()
            return { h = 40 }
          end,
        }
        local mock_page_info = {
          getSize = function()
            return { h = 30 }
          end,
        }

        local menu = createMockMenu({
          nb_cols_portrait = 2,
          nb_rows_portrait = 2,
          inner_dimen = Geom:new({ x = 0, y = 0, w = 600, h = 800 }),
          title_bar = mock_title,
          page_info = mock_page_info,
          is_borderless = false,
          no_title = false,
        })

        menu:_recalculateDimen()

        -- others_height = 2 (border) + 40 (title) + 30 (page_info) = 72
        assert.are.equal(72, menu.others_height)
      end
    )
  end)

  describe("Grid Layout Generation (_updateItemsBuildUI)", function()
    it("should build grid layout for page 1", function()
      Screen.getWidth = function()
        return 600
      end
      Screen.getHeight = function()
        return 800
      end
      Screen.scaleBySize = function(_, size)
        return size
      end

      local items = {}
      for i = 1, 15 do
        table.insert(items, {
          text = "Book " .. i,
          path = "/tmp/book" .. i .. ".epub",
          is_file = true,
        })
      end

      local menu = createMockMenu({
        nb_cols_portrait = 3,
        nb_rows_portrait = 2,
        item_table = items,
        page = 1,
      })

      menu:_recalculateDimen()
      local select_idx = menu:_updateItemsBuildUI()

      assert.is_nil(select_idx)
      assert.are.equal(2, #menu.layout) -- 2 rows
      assert.are.equal(3, #menu.layout[1]) -- 3 cols in row 1
      assert.are.equal(3, #menu.layout[2]) -- 3 cols in row 2

      assert.are.equal("Book 1", menu.layout[1][1].text)
      assert.are.equal("Book 3", menu.layout[1][3].text)
      assert.are.equal("Book 4", menu.layout[2][1].text)
      assert.are.equal("Book 6", menu.layout[2][3].text)
    end)

    it("should build grid layout for page navigation (page 2)", function()
      Screen.getWidth = function()
        return 600
      end
      Screen.getHeight = function()
        return 800
      end
      Screen.scaleBySize = function(_, size)
        return size
      end

      local items = {}
      for i = 1, 15 do
        table.insert(items, {
          text = "Book " .. i,
          path = "/tmp/book" .. i .. ".epub",
          is_file = true,
        })
      end

      local menu = createMockMenu({
        nb_cols_portrait = 3,
        nb_rows_portrait = 2, -- perpage = 6
        item_table = items,
        page = 2,
      })

      menu:_recalculateDimen()
      menu:_updateItemsBuildUI()

      assert.are.equal(2, #menu.layout)
      assert.are.equal(3, #menu.layout[1])
      assert.are.equal(3, #menu.layout[2])

      -- Page 2 items start from index 7 to 12
      assert.are.equal("Book 7", menu.layout[1][1].text)
      assert.are.equal("Book 12", menu.layout[2][3].text)
    end)

    it("should handle partial row on last page", function()
      Screen.getWidth = function()
        return 600
      end
      Screen.getHeight = function()
        return 800
      end
      Screen.scaleBySize = function(_, size)
        return size
      end

      local items = {}
      for i = 1, 7 do
        table.insert(items, {
          text = "Book " .. i,
          path = "/tmp/book" .. i .. ".epub",
          is_file = true,
        })
      end

      local menu = createMockMenu({
        nb_cols_portrait = 3,
        nb_rows_portrait = 2, -- perpage = 6, page 2 has only 1 item
        item_table = items,
        page = 2,
      })

      menu:_recalculateDimen()
      menu:_updateItemsBuildUI()

      assert.are.equal(1, #menu.layout)
      assert.are.equal(1, #menu.layout[1])
      assert.are.equal("Book 7", menu.layout[1][1].text)
    end)

    it("should calculate select_number for focused item", function()
      Screen.getWidth = function()
        return 600
      end
      Screen.getHeight = function()
        return 800
      end
      Screen.scaleBySize = function(_, size)
        return size
      end

      local items = {}
      for i = 1, 12 do
        table.insert(items, {
          text = "Book " .. i,
          path = "/tmp/book" .. i .. ".epub",
          is_file = true,
        })
      end

      local menu = createMockMenu({
        nb_cols_portrait = 3,
        nb_rows_portrait = 2, -- perpage = 6
        item_table = items,
        page = 2, -- items 7..12
        itemnumber = 8, -- item 8 is the 2nd item on page 2
      })

      menu:_recalculateDimen()
      local select_idx = menu:_updateItemsBuildUI()

      assert.are.equal(2, select_idx)
    end)

    it("should handle directory items in grid", function()
      Screen.getWidth = function()
        return 600
      end
      Screen.getHeight = function()
        return 800
      end
      Screen.scaleBySize = function(_, size)
        return size
      end

      local items = {
        { text = "Folder 1/", mandatory = "5 items", is_file = false },
        { text = "Book A", path = "/tmp/a.epub", is_file = true },
      }

      local menu = createMockMenu({
        nb_cols_portrait = 2,
        nb_rows_portrait = 1,
        item_table = items,
        page = 1,
      })

      menu:_recalculateDimen()
      menu:_updateItemsBuildUI()

      assert.are.equal(1, #menu.layout)
      assert.are.equal(2, #menu.layout[1])
      assert.True(menu.layout[1][1].is_directory)
      assert.False(menu.layout[1][2].is_directory)
    end)

    it(
      "should register items in items_to_update if book info is missing",
      function()
        Screen.getWidth = function()
          return 600
        end
        Screen.getHeight = function()
          return 800
        end
        Screen.scaleBySize = function(_, size)
          return size
        end

        local items = {
          {
            text = "Book Untracked",
            path = "/nonexistent/test_book.epub",
            is_file = true,
          },
        }

        local menu = createMockMenu({
          nb_cols_portrait = 2,
          nb_rows_portrait = 1,
          item_table = items,
          page = 1,
          do_covers = true,
        })

        menu:_recalculateDimen()
        menu:_updateItemsBuildUI()

        assert.are.equal(1, #menu.items_to_update)
        assert.are.equal("Book Untracked", menu.items_to_update[1].text)
      end
    )

    it("should handle item tap, hold, and focus handlers", function()
      local selected_entry = nil
      local held_entry = nil
      local menu = createMockMenu({
        nb_cols_portrait = 2,
        nb_rows_portrait = 1,
        item_table = {
          { text = "Folder A", path = "/tmp/dirA", is_directory = true },
          { text = "Book B", path = "/tmp/bookB.epub", is_file = true },
        },
        page = 1,
        do_covers = false,
        do_hint = true,
      })
      menu.onMenuSelect = function(self_m, entry) selected_entry = entry end
      menu.onMenuHold = function(self_m, entry) held_entry = entry end

      menu:_recalculateDimen()
      menu:_updateItemsBuildUI()

      assert.is_table(menu.layout)
      assert.is_true(#menu.layout >= 1)
      local row = menu.layout[1]
      for _, item in ipairs(row) do
        if item.onTapSelect then
          item:onTapSelect()
        end
        if item.onHoldSelect then
          item:onHoldSelect()
        end
        if item.onFocus then
          item:onFocus()
        end
        if item.onUnfocus then
          item:onUnfocus()
        end
        if item.getHoldMessage then
          local msg = item:getHoldMessage()
          assert.truthy(msg == nil or type(msg) == "string")
        end
      end
      assert.is_table(selected_entry)
      assert.is_table(held_entry)
    end)
  end)

  describe("MosaicMenuItem Painting & Sub-features", function()
    local BookInfoManager, DocSettings, ReadCollection, BD, Blitbuffer, Menu

    setup(function()
      BookInfoManager = require("plugins/coverbrowser.koplugin/bookinfomanager")
      DocSettings = require("docsettings")
      ReadCollection = require("readcollection")
      BD = require("ui/bidi")
      Blitbuffer = require("ffi/blitbuffer")
      Menu = require("ui/widget/menu")
    end)

    it("should build and paint fake covers with complex titles, authors, and series modes", function()
      local sample_cover = Blitbuffer.new(80, 120, Blitbuffer.TYPE_BB8)

      local mock_infos = {
        ["/tmp/book_multi_author.epub"] = {
          title = "A Great Novel - Vol 1 | Special Edition_With_Underscores.ext",
          authors = "Author One\nAuthor Two\nAuthor Three\nAuthor Four\nAuthor Five",
          series = "Epic Trilogy",
          series_index = 2,
          has_cover = nil,
          cover_fetched = "Y",
          description = "A long story.",
          pages = 350,
        },
        ["/tmp/book_with_cover.epub"] = {
          title = "Cover Book",
          authors = "Single Author",
          has_cover = "Y",
          cover_w = 80,
          cover_h = 120,
          cover_sizetag = "80x120",
          cover_bb = sample_cover,
          cover_fetched = "Y",
          pages = 200,
        },
        ["/tmp/book_wiki.epub"] = {
          title = "Wikipedia Entry",
          authors = "Wikipedia Contributors",
          has_cover = "Y",
          cover_fetched = "Y",
          pages = 50,
        },
      }

      local get_stub = stub(BookInfoManager, "getBookInfo", function(self_bim, path)
        return mock_infos[path]
      end)
      local sidecar_stub = stub(DocSettings, "hasSidecarFile", function() return true end)
      local setting_stub = stub(BookInfoManager, "getSetting", function(self_bim, key)
        if key == "series_mode" then return "append_series_to_title" end
        if key == "show_progress_in_mosaic" then return true end
        return nil
      end)

      local items = {
        { text = "Book Multi Author", path = "/tmp/book_multi_author.epub", is_file = true },
        { text = "Book With Cover", path = "/tmp/book_with_cover.epub", is_file = true },
        { text = "Book Wiki", path = "/tmp/book_wiki.epub", is_file = true },
        { text = "Deleted Book", path = "/tmp/deleted.epub", is_file = true, dim = true },
        { text = "Extremely/Long/Directory/Name/That/Will/Force/Font/Reduction/Below/Threshold/", is_file = false, mandatory = "12 items" },
      }

      local menu = createMockMenu({
        nb_cols_portrait = 2,
        nb_rows_portrait = 3,
        item_table = items,
        page = 1,
        do_covers = true,
        do_hint = true,
        updateCache = function(self_m, path, _, _, pages)
          self_m.cover_info_cache[path] = { pages or 100, 0.45, "reading" }
          self_m.cover_info_cache[path].n = 3
        end,
        cover_info_cache = {},
      })
      menu.updateCache = function(self_m, path, _, _, pages)
        self_m.cover_info_cache[path] = { pages or 100, 0.45, "reading" }
        self_m.cover_info_cache[path].n = 3
      end

      menu:_recalculateDimen()
      menu:_updateItemsBuildUI()

      local bb = Blitbuffer.new(600, 800)
      for _, row in ipairs(menu.layout) do
        for _, item in ipairs(row) do
          if item.paintTo then
            item:paintTo(bb, 0, 0)
          end
        end
      end

      -- Test RTL layout painting
      local bidi_stub = stub(BD, "mirroredUILayout", function() return true end)
      local coll_stub = stub(ReadCollection, "isFileInCollections", function(self_rc, path)
        return path ~= nil and type(path) == "string" and path:match("%.epub$") ~= nil
      end)

      for _, row in ipairs(menu.layout) do
        for _, item in ipairs(row) do
          if item.paintTo then
            if not item.is_directory then
              item.status = "abandoned"
              item.show_progress_bar = true
              item.percent_finished = 0.3
              item.has_description = true
            end
            item:paintTo(bb, 0, 0)

            if not item.is_directory then
              item.status = "complete"
              item:paintTo(bb, 0, 0)
            end
          end
        end
      end

      bidi_stub:revert()
      coll_stub:revert()
      get_stub:revert()
      sidecar_stub:revert()
      setting_stub:revert()
      sample_cover:free()
    end)

    it("should handle series_mode variants and xtext branches in FakeCover", function()
      local series_modes = { "append_series_to_authors", "series_in_separate_line" }
      for _, sm in ipairs(series_modes) do
        local mock_info = {
          title = "Very_Long_Title_Without_Spaces_To_Force_Breaking_Algorithm_And_Sizedec_Over_20_With_Dots.And.Underscores",
          authors = "Very_Long_Author_Name_Without_Spaces_To_Force_Breaking_Algorithm_And_Sizedec_Over_20_With_Dots.And.Underscores",
          series = "Test Series",
          series_index = 1,
          has_cover = nil,
          cover_fetched = "Y",
        }

        local get_stub = stub(BookInfoManager, "getBookInfo", function() return mock_info end)
        local setting_stub = stub(BookInfoManager, "getSetting", function(self_bim, key)
          if key == "series_mode" then return sm end
          return nil
        end)

        local menu = createMockMenu({
          nb_cols_portrait = 2,
          nb_rows_portrait = 1,
          item_table = {
            { text = "Test Book", path = "/tmp/test.epub", is_file = true },
          },
          page = 1,
          do_covers = false,
        })
        menu:_recalculateDimen()
        menu:_updateItemsBuildUI()

        assert.is_table(menu.layout)
        get_stub:revert()
        setting_stub:revert()
      end
    end)
  end)
end)

