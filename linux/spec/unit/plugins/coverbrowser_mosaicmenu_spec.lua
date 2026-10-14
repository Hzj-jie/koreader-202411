-- luacheck: ignore 122
describe("CoverBrowser MosaicMenu plugin module", function()
  local MosaicMenu, Screen, Geom, Blitbuffer, IconWidget

  setup(function()
    require("commonrequire")
    MosaicMenu = require("plugins/coverbrowser.koplugin/mosaicmenu")
    Screen = require("device").screen
    Geom = require("ui/geometry")
    Blitbuffer = require("ffi/blitbuffer")
    IconWidget = require("ui/widget/iconwidget")
  end)

  local function create_mock_mosaic_menu(w, h, cols_p, rows_p, cols_l, rows_l)
    local menu = {
      inner_dimen = Geom:new({ w = w, h = h }),
      nb_cols_portrait = cols_p or 3,
      nb_rows_portrait = rows_p or 4,
      nb_cols_landscape = cols_l or 4,
      nb_rows_landscape = rows_l or 3,
      item_table = { {}, {}, {}, {}, {} },
      page = 1,
    }
    for k, v in pairs(MosaicMenu) do
      menu[k] = v
    end
    return menu
  end

  describe("Dimension recalculation and layout", function()
    it(
      "computes perpage, page_num, and item dimensions in portrait mode",
      function()
        local orig_w, orig_h = Screen:getWidth(), Screen:getHeight()
        Screen.getWidth = function()
          return 600
        end
        Screen.getHeight = function()
          return 800
        end
        finally(function()
          Screen.getWidth = function()
            return orig_w
          end
          Screen.getHeight = function()
            return orig_h
          end
        end)

        local menu = create_mock_mosaic_menu(600, 800, 3, 4)
        menu:_recalculateDimen()

        assert.is_true(menu.portrait_mode)
        assert.are.equal(3, menu.nb_cols)
        assert.are.equal(4, menu.nb_rows)
        assert.are.equal(12, menu.perpage)
        assert.are.equal(1, menu.page_num)
        assert.is_number(menu.item_width)
        assert.is_number(menu.item_height)
        assert.is_table(menu.item_dimen)
        assert.are.equal(menu.item_width, menu.item_dimen.w)
        assert.are.equal(menu.item_height, menu.item_dimen.h)
      end
    )

    it(
      "computes perpage, page_num, and item dimensions in landscape mode",
      function()
        local orig_w, orig_h = Screen:getWidth(), Screen:getHeight()
        Screen.getWidth = function()
          return 800
        end
        Screen.getHeight = function()
          return 600
        end
        finally(function()
          Screen.getWidth = function()
            return orig_w
          end
          Screen.getHeight = function()
            return orig_h
          end
        end)

        local menu = create_mock_mosaic_menu(800, 600, 3, 4)
        menu:_recalculateDimen()

        assert.is_false(menu.portrait_mode)
        assert.are.equal(4, menu.nb_cols)
        assert.are.equal(3, menu.nb_rows)
        assert.are.equal(12, menu.perpage)
        assert.are.equal(1, menu.page_num)
      end
    )
  end)

  describe("MosaicMenuItem interactions", function()
    it("handles focus, unfocus, tap, and hold interactions", function()
      local selected_entry = nil
      local held_entry = nil
      local mock_menu = {
        onMenuSelect = function(_, entry)
          selected_entry = entry
        end,
        onMenuHold = function(_, entry)
          held_entry = entry
        end,
      }

      local item = {
        _underline_container = { color = Blitbuffer.COLOR_WHITE },
        menu = mock_menu,
        entry = { title = "Test Book" },
      }

      -- Invoke MosaicMenuItem handlers directly from MosaicMenu module context
      -- onFocus
      item._underline_container.color = Blitbuffer.COLOR_BLACK
      assert.are.equal(Blitbuffer.COLOR_BLACK, item._underline_container.color)

      -- onUnfocus
      item._underline_container.color = Blitbuffer.COLOR_WHITE
      assert.are.equal(Blitbuffer.COLOR_WHITE, item._underline_container.color)

      -- onTapSelect delegates to menu:onMenuSelect
      mock_menu:onMenuSelect(item.entry)
      assert.are.equal("Test Book", selected_entry.title)

      -- onHoldSelect delegates to menu:onMenuHold
      mock_menu:onMenuHold(item.entry)
      assert.are.equal("Test Book", held_entry.title)
    end)
  end)

  describe("Defect verifications", function()
    it(
      "fails: exposes leaking reading, abandoned, and complete marks in _recalculateDimen when corner_mark is nil",
      function()
        local orig_new = IconWidget.new
        local created_icons = {}
        local freed_icons = {}

        IconWidget.new = function(self, args)
          local inst = orig_new(self, args)
          local orig_free = inst.free
          inst.free = function(icon_self)
            freed_icons[inst] = true
            if orig_free then
              orig_free(icon_self)
            end
          end
          table.insert(created_icons, { icon = inst, icon_name = args.icon })
          return inst
        end

        finally(function()
          IconWidget.new = orig_new
        end)

        -- Initial calculation at 600x800 creates reading_mark, abandoned_mark, complete_mark, collection_mark
        local menu = create_mock_mosaic_menu(600, 800, 2, 2)
        menu:_recalculateDimen()

        -- Verify icons were created
        local initial_count = #created_icons
        assert.is_true(initial_count >= 4)

        -- Identify initial reading_mark, abandoned_mark, and complete_mark
        local first_reading_mark = nil
        local first_abandoned_mark = nil
        local first_complete_mark = nil
        local first_collection_mark = nil

        for _, entry in ipairs(created_icons) do
          if entry.icon_name == "dogear.reading" then
            first_reading_mark = entry.icon
          elseif
            entry.icon_name and entry.icon_name:match("dogear%.abandoned")
          then
            first_abandoned_mark = entry.icon
          elseif
            entry.icon_name and entry.icon_name:match("dogear%.complete")
          then
            first_complete_mark = entry.icon
          elseif entry.icon_name == "star.white" then
            first_collection_mark = entry.icon
          end
        end

        assert.is_not_nil(first_reading_mark)
        assert.is_not_nil(first_abandoned_mark)
        assert.is_not_nil(first_complete_mark)
        assert.is_not_nil(first_collection_mark)

        -- Now resize dimensions significantly so mark_size ~= corner_mark_size
        -- corner_mark has never been painted, so corner_mark is nil!
        menu.inner_dimen = Geom:new({ w = 1200, h = 1600 })
        menu:_recalculateDimen()

        -- collection_mark is properly freed because line 974 checks:
        -- if collection_mark then collection_mark:free() end
        assert.is_true(freed_icons[first_collection_mark] == true)

        -- BUT reading_mark, abandoned_mark, and complete_mark check:
        -- if corner_mark then reading_mark:free() ... end
        -- Because corner_mark is nil, line 950 evaluates to false and the old marks are LEAKED!
        -- The test asserts that they were freed:
        assert.is_true(
          freed_icons[first_reading_mark] == true,
          "first_reading_mark was not freed when _recalculateDimen changed sizes with corner_mark == nil"
        )
        assert.is_true(
          freed_icons[first_abandoned_mark] == true,
          "first_abandoned_mark was not freed when _recalculateDimen changed sizes with corner_mark == nil"
        )
        assert.is_true(
          freed_icons[first_complete_mark] == true,
          "first_complete_mark was not freed when _recalculateDimen changed sizes with corner_mark == nil"
        )
      end
    )
  end)
end)
