-- luacheck: ignore 122
describe("CoverBrowser ListMenu plugin module", function()
  local ListMenu, Screen, Geom, Blitbuffer, DocSettings, IconWidget

  setup(function()
    require("commonrequire")
    ListMenu = require("plugins/coverbrowser.koplugin/listmenu")
    Screen = require("device").screen
    Geom = require("ui/geometry")
    Blitbuffer = require("ffi/blitbuffer")
    DocSettings = require("docsettings")
    IconWidget = require("ui/widget/iconwidget")
  end)

  local function create_mock_list_menu(w, h, perpage_p)
    local menu = {
      inner_dimen = Geom:new({ w = w, h = h }),
      title_bar = {
        getSize = function()
          return Geom:new({ w = w, h = 40 })
        end,
      },
      page_info = {
        getSize = function()
          return Geom:new({ w = w, h = 20 })
        end,
      },
      path_items = {},
      path = "/tmp",
      files_per_page = perpage_p or 10,
      item_table = { {}, {}, {}, {}, {} },
      item_group = {},
      layout = {},
      items_to_update = {},
      page = 1,
    }
    for k, v in pairs(ListMenu) do
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

        local menu = create_mock_list_menu(600, 800, 10, 6)
        menu:_recalculateDimen()

        assert.is_true(menu.portrait_mode)
        assert.are.equal(10, menu.perpage)
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

        local menu = create_mock_list_menu(800, 600, 10, 6)
        menu:_recalculateDimen()

        assert.is_false(menu.portrait_mode)
        assert.is_true(menu.perpage > 0)
        assert.are.equal(1, menu.page_num)
      end
    )
  end)

  describe("ListMenuItem interactions", function()
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

      item._underline_container.color = Blitbuffer.COLOR_BLACK
      assert.are.equal(Blitbuffer.COLOR_BLACK, item._underline_container.color)

      item._underline_container.color = Blitbuffer.COLOR_WHITE
      assert.are.equal(Blitbuffer.COLOR_WHITE, item._underline_container.color)

      mock_menu:onMenuSelect(item.entry)
      assert.are.equal("Test Book", selected_entry.title)

      mock_menu:onMenuHold(item.entry)
      assert.are.equal("Test Book", held_entry.title)
    end)
  end)

  describe("Defect verifications", function()
    it("paints dogear for opened unindexed book", function()
      local orig_has_sidecar = DocSettings.hasSidecarFile
      DocSettings.hasSidecarFile = function()
        return true
      end

      local dogear_painted = false
      local orig_new = IconWidget.new
      IconWidget.new = function(self, args)
        local inst = orig_new(self, args)
        if args and args.icon == "dogear.opaque" then
          local orig_paintTo = inst.paintTo
          inst.paintTo = function(icon_self, ...)
            dogear_painted = true
            if orig_paintTo then
              orig_paintTo(icon_self, ...)
            end
          end
        end
        return inst
      end

      finally(function()
        DocSettings.hasSidecarFile = orig_has_sidecar
        IconWidget.new = orig_new
      end)

      local menu = create_mock_list_menu(600, 800, 10)
      menu._do_hint_opened = true
      menu.item_table = {
        {
          file = "/tmp/unindexed_opened_book.epub",
          path = "/tmp/unindexed_opened_book.epub",
          is_file = true,
          text = "Unindexed Book",
        },
      }
      menu:_recalculateDimen()
      menu:_updateItemsBuildUI()

      assert.is_table(menu.item_group)
      local item = menu.item_group[2]
      assert.is_not_nil(item)
      assert.is_true(item.been_opened)

      local bb = Blitbuffer.new(600, 800, Blitbuffer.TYPE_BPP_8)
      item:paintTo(bb, 0, 0)

      assert.is_true(
        dogear_painted,
        "Dogear was not painted for opened unindexed book"
      )
    end)
  end)
end)
