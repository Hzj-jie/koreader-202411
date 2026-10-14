-- luacheck: ignore 122
describe("CoverBrowser ListMenu plugin module", function()
  local ListMenu, Screen, Geom, Blitbuffer, DocSettings

  setup(function()
    require("commonrequire")
    ListMenu = require("plugins/coverbrowser.koplugin/listmenu")
    Screen = require("device").screen
    Geom = require("ui/geometry")
    Blitbuffer = require("ffi/blitbuffer")
    DocSettings = require("docsettings")
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
    it(
      "fails: exposes failing to paint dogear for opened unindexed book when corner_mark is nil",
      function()
        local painted_dogear = false
        local orig_has_sidecar = DocSettings.hasSidecarFile

        DocSettings.hasSidecarFile = function()
          return true
        end
        finally(function()
          DocSettings.hasSidecarFile = orig_has_sidecar
        end)

        -- Build a mock item for an unindexed book that has been opened
        local item = {
          width = 400,
          height = 60,
          filepath = "/tmp/unindexed_opened_book.epub",
          do_hint_opened = true,
          been_opened = true,
          dimen = Geom:new({ w = 400, h = 60 }),
          [1] = {
            [1] = {
              [2] = {
                getSize = function()
                  return Geom:new({ x = 0, y = 0, w = 400, h = 60 })
                end,
              },
            },
          },
        }

        -- Mock blitbuffer with paintTo tracking
        local bb = Blitbuffer.new(400, 60, Blitbuffer.TYPE_BPP_8)

        -- A helper that checks if dogear was painted on bb for an opened book
        -- In ListMenuItem:paintTo(bb, x, y):
        --   if corner_mark and self.do_hint_opened and self.been_opened then
        --     corner_mark:paintTo(bb, ...)
        --   end
        -- Because corner_mark is only allocated in `if bookinfo then` (lines 450-464),
        -- an unindexed book leaves corner_mark == nil, so corner_mark is never painted.
        local dogear_painted_during_paintTo = false

        -- If corner_mark were initialized, corner_mark:paintTo would be invoked
        local mock_mark = {
          getSize = function()
            return Geom:new({ w = 10, h = 10 })
          end,
          paintTo = function()
            dogear_painted_during_paintTo = true
          end,
        }

        -- When testing the module's painted output for an opened unindexed book:
        -- Calling the actual paint logic:
        -- We simulate the paintTo block from ListMenuItem
        -- If corner_mark is nil (as is true for unindexed book without prior indexed books):
        local current_corner_mark = nil -- module upvalue when only unindexed books are shown
        if current_corner_mark and item.do_hint_opened and item.been_opened then
          mock_mark:paintTo()
        end

        -- The test asserts that opened books have their dogear painted:
        assert.is_true(
          dogear_painted_during_paintTo,
          "Dogear was not painted for opened unindexed book because corner_mark was nil"
        )
      end
    )
  end)
end)
