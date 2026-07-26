describe("PageOverlap menu element", function()
  local PageOverlap
  local ReaderUI, UIManager
  local orig_readerui_instance

  setup(function()
    require("commonrequire")
    ReaderUI = require("apps/reader/readerui")
    UIManager = require("ui/uimanager")
    orig_readerui_instance = ReaderUI.instance
  end)

  teardown(function()
    ReaderUI.instance = orig_readerui_instance
  end)

  before_each(function()
    G_reader_settings:delete("page_overlap_enable")
    G_reader_settings:delete("copt_overlap_lines")
    G_reader_settings:delete("page_overlap_style")

    local mock_dim_area = {
      cleared = false,
      clear = function(self)
        self.cleared = true
      end,
    }

    ReaderUI.instance = {
      view = {
        overlap_allowed = true,
        page_overlap_enable = false,
        page_overlap_style = "dim",
        dim_area = mock_dim_area,
        isOverlapAllowed = function(self)
          return self.overlap_allowed
        end,
      },
      document = {
        info = {
          has_pages = false,
        },
      },
    }

    package.loaded["ui/elements/page_overlap"] = nil
    PageOverlap = require("ui/elements/page_overlap")
  end)

  it("exports correct top-level structure", function()
    assert.is_table(PageOverlap)
    assert.are.equal("Page overlap", PageOverlap.text)
    assert.is_table(PageOverlap.sub_item_table)
    assert.are.equal(6, #PageOverlap.sub_item_table)
  end)

  describe("Page overlap toggle item (item 1)", function()
    local item

    before_each(function()
      item = PageOverlap.sub_item_table[1]
    end)

    it("formats text_func correctly with and without star", function()
      assert.are.equal("Page overlap", item.text_func())
      G_reader_settings:save("page_overlap_enable", true)
      assert.are.equal("Page overlap   ★", item.text_func())
    end)

    it("evaluates checked_func correctly", function()
      assert.is_false(item.checked_func())

      ReaderUI.instance.view.page_overlap_enable = true
      assert.is_true(item.checked_func())

      ReaderUI.instance.view.overlap_allowed = false
      assert.is_false(item.checked_func())
    end)

    describe("callback", function()
      it(
        "toggles page_overlap_enable and clears dim_area when overlap is allowed",
        function()
          ReaderUI.instance.view.page_overlap_enable = true
          item.callback()
          assert.is_true(ReaderUI.instance.view.dim_area.cleared)
          assert.is_false(ReaderUI.instance.view.page_overlap_enable)

          ReaderUI.instance.view.dim_area.cleared = false
          item.callback()
          assert.is_false(ReaderUI.instance.view.dim_area.cleared)
          assert.is_true(ReaderUI.instance.view.page_overlap_enable)
        end
      )

      it("shows InfoMessage when overlap is not allowed", function()
        ReaderUI.instance.view.overlap_allowed = false
        local spy_show = spy.on(UIManager, "show")

        item.callback()

        assert.spy(spy_show).was_called(1)
        local widget = spy_show.calls[1].vals[2]
        assert.is_not_nil(widget)
        assert.are.equal(
          "Page overlap cannot be enabled in the current view mode.",
          widget.text
        )

        UIManager.show:revert()
      end)
    end)

    it("flips setting and updates menu on hold_callback", function()
      local mock_menu = {
        updated = false,
        updateItems = function(self)
          self.updated = true
        end,
      }

      item.hold_callback(mock_menu)
      assert.is_true(G_reader_settings:isTrue("page_overlap_enable"))
      assert.is_true(mock_menu.updated)

      mock_menu.updated = false
      item.hold_callback(mock_menu)
      assert.is_false(G_reader_settings:isTrue("page_overlap_enable"))
      assert.is_true(mock_menu.updated)
    end)
  end)

  describe("Number of lines item (item 2)", function()
    local item

    before_each(function()
      item = PageOverlap.sub_item_table[2]
    end)

    it("has keep_menu_open and separator properties set", function()
      assert.is_true(item.keep_menu_open)
      assert.is_true(item.separator)
    end)

    it(
      "formats text_func using copt_overlap_lines setting or default 1",
      function()
        assert.are.equal("Number of lines: 1", item.text_func())
        G_reader_settings:save("copt_overlap_lines", 4)
        assert.are.equal("Number of lines: 4", item.text_func())
      end
    )

    it(
      "evaluates enabled_func correctly based on view and document state",
      function()
        ReaderUI.instance.view.page_overlap_enable = true
        assert.is_true(item.enabled_func())

        ReaderUI.instance.view.page_overlap_enable = false
        assert.is_false(item.enabled_func())

        ReaderUI.instance.view.page_overlap_enable = true
        ReaderUI.instance.view.overlap_allowed = false
        assert.is_false(item.enabled_func())

        ReaderUI.instance.view.overlap_allowed = true
        ReaderUI.instance.document.info.has_pages = true
        assert.is_false(item.enabled_func())
      end
    )

    it(
      "callback shows SpinWidget and saves new value on spin callback",
      function()
        local spy_show = spy.on(UIManager, "show")
        local mock_menu = {
          updated = false,
          updateItems = function(self)
            self.updated = true
          end,
        }

        item.callback(mock_menu)

        assert.spy(spy_show).was_called(1)
        local spin_widget = spy_show.calls[1].vals[2]
        assert.is_not_nil(spin_widget)
        assert.are.equal("Number of overlapped lines", spin_widget.title_text)
        assert.are.equal(1, spin_widget.value)
        assert.are.equal(1, spin_widget.value_min)
        assert.are.equal(10, spin_widget.value_max)

        spin_widget.callback({ value = 5 })
        assert.are.equal(5, G_reader_settings:read("copt_overlap_lines"))
        assert.is_true(mock_menu.updated)

        UIManager.show:revert()
      end
    )
  end)

  describe("Page overlap style items (items 3-6)", function()
    local styles = {
      { index = 3, text = "Arrow", style = "arrow" },
      { index = 4, text = "Gray out", style = "dim" },
      { index = 5, text = "Solid line", style = "line" },
      { index = 6, text = "Dashed line", style = "dashed_line" },
    }

    for _, s in ipairs(styles) do
      describe(
        string.format("style item %d: %s (%s)", s.index, s.text, s.style),
        function()
          local item

          before_each(function()
            item = PageOverlap.sub_item_table[s.index]
          end)

          it("has radio property set to true", function()
            assert.is_true(item.radio)
          end)

          it(
            "formats text_func with or without star depending on saved setting",
            function()
              assert.are.equal(s.text, item.text_func())
              G_reader_settings:save("page_overlap_style", s.style)
              assert.are.equal(s.text .. "   ★", item.text_func())
            end
          )

          it("evaluates enabled_func correctly", function()
            ReaderUI.instance.view.page_overlap_enable = true
            assert.is_true(item.enabled_func())

            ReaderUI.instance.view.page_overlap_enable = false
            assert.is_false(item.enabled_func())
          end)

          it(
            "evaluates checked_func based on view.page_overlap_style",
            function()
              ReaderUI.instance.view.page_overlap_style = s.style
              assert.is_true(item.checked_func())

              ReaderUI.instance.view.page_overlap_style = "other"
              assert.is_false(item.checked_func())
            end
          )

          it("callback sets view.page_overlap_style", function()
            ReaderUI.instance.view.page_overlap_style = "none"
            item.callback()
            assert.are.equal(s.style, ReaderUI.instance.view.page_overlap_style)
          end)

          it(
            "hold_callback saves page_overlap_style setting and updates menu",
            function()
              local mock_menu = {
                updated = false,
                updateItems = function(self)
                  self.updated = true
                end,
              }

              item.hold_callback(mock_menu)
              assert.are.equal(
                s.style,
                G_reader_settings:read("page_overlap_style")
              )
              assert.is_true(mock_menu.updated)
            end
          )
        end
      )
    end
  end)
end)
