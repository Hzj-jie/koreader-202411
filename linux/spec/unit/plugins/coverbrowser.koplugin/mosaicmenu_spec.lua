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

    it("should handle empty item table gracefully", function()
      local menu = createMockMenu({
        nb_cols_portrait = 2,
        nb_rows_portrait = 2,
        item_table = {},
      })
      menu:_recalculateDimen()
      assert.are.equal(0, menu.page_num)
    end)

    it("should handle item tap helper safely", function()
      local menu = createMockMenu({
        item_table = { { text = "Book 1" } },
      })
      if type(menu._onItemTap) == "function" then
        menu:_onItemTap({ text = "Book 1" })
      end
    end)
  end)
end)
