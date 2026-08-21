describe("DictQuickLookup", function()
  local DictQuickLookup
  local UIManager
  local Event
  local Geom
  local util

  local orig_setDirty
  local orig_show
  local orig_close
  local orig_broadcastEvent
  local orig_scheduleIn
  local orig_scheduleRefresh

  local dummy_ui = {
    wikipedia = {
      getWikiLanguages = function()
        return { "en", "es" }, true
      end,
    },
  }

  setup(function()
    require("commonrequire")
    DictQuickLookup = require("ui/widget/dictquicklookup")
    UIManager = require("ui/uimanager")
    Event = require("ui/event")
    Geom = require("ui/geometry")
    util = require("util")

    orig_setDirty = UIManager.setDirty
    orig_show = UIManager.show
    orig_close = UIManager.close
    orig_broadcastEvent = UIManager.broadcastEvent
    orig_scheduleIn = UIManager.scheduleIn
    orig_scheduleRefresh = UIManager.scheduleRefresh
  end)

  before_each(function()
    DictQuickLookup.window_list = {}
    DictQuickLookup.rotated_update_wiki_languages_on_close = nil

    -- Safe default stubs for UI management during unit tests
    UIManager.setDirty = function() end
    UIManager.show = function() end
    UIManager.close = function(_, widget)
      if widget and type(widget) == "table" and widget.onClose then
        widget:onClose()
      end
    end
    UIManager.broadcastEvent = function() end
    UIManager.scheduleIn = function(_, fn)
      if fn then
        fn()
      end
    end
    UIManager.scheduleRefresh = function() end
  end)

  after_each(function()
    UIManager.setDirty = orig_setDirty
    UIManager.show = orig_show
    UIManager.close = orig_close
    UIManager.broadcastEvent = orig_broadcastEvent
    UIManager.scheduleIn = orig_scheduleIn
    UIManager.scheduleRefresh = orig_scheduleRefresh
  end)

  local function createDummyResults()
    return {
      {
        dict = "Dict 1",
        word = "word1",
        definition = "def 1",
        is_html = false,
        lang = "en",
        ifo_lang = { lang_in = "en", lang_out = "en" },
      },
      {
        dict = "Dict 2",
        word = "word2",
        definition = "def 2",
        is_html = true,
        lang = "en",
        ifo_lang = { lang_in = "en", lang_out = "en" },
      },
    }
  end

  describe("getWikiSaveEpubDefaultDir", function()
    it("should handle home_dir with and without trailing slash", function()
      local old_home = G_named_settings.home_dir
      G_named_settings.home_dir = function()
        return "/home/user/"
      end
      assert.are.equal(
        "/home/user/Wikipedia",
        DictQuickLookup.getWikiSaveEpubDefaultDir()
      )

      G_named_settings.home_dir = function()
        return "/home/user"
      end
      assert.are.equal(
        "/home/user/Wikipedia",
        DictQuickLookup.getWikiSaveEpubDefaultDir()
      )

      G_named_settings.home_dir = old_home
    end)
  end)

  describe("isDocless and canSearch", function()
    it("should check isDocless", function()
      local lookup = DictQuickLookup:new({
        word = "test",
        results = createDummyResults(),
      })
      assert.is_true(lookup:isDocless())

      lookup.ui = { highlight = {} }
      assert.is_false(lookup:isDocless())
    end)

    it("should check canSearch for non-wiki variant", function()
      local lookup = DictQuickLookup:new({
        word = "test",
        results = createDummyResults(),
        is_wiki = false,
      })
      -- docless -> false
      assert.is_false(lookup:canSearch())

      lookup.ui = { highlight = {} }
      lookup.highlight = nil
      assert.is_false(lookup:canSearch())

      lookup.highlight = {}
      assert.is_true(lookup:canSearch())
    end)

    it("should check canSearch for wiki variant", function()
      local single_lang_ui = {
        wikipedia = {
          getWikiLanguages = function()
            return { "en" }, false
          end,
        },
      }
      local lookup = DictQuickLookup:new({
        word = "test",
        results = createDummyResults(),
        is_wiki = true,
        ui = single_lang_ui,
      })
      assert.is_false(lookup:canSearch())

      lookup.wiki_languages = { "en", "es" }
      assert.is_true(lookup:canSearch())
    end)
  end)

  describe("Dictionary navigation", function()
    it("should accurately report prev and next dict availability", function()
      local lookup = DictQuickLookup:new({
        word = "test",
        results = createDummyResults(),
      })

      assert.are.equal(1, lookup.dict_index)
      assert.is_false(lookup:isPrevDictAvaiable())
      assert.is_true(lookup:isNextDictAvaiable())

      lookup:onChangeToNextDict()
      assert.are.equal(2, lookup.dict_index)
      assert.is_true(lookup:isPrevDictAvaiable())
      assert.is_false(lookup:isNextDictAvaiable())

      -- Wrap around next
      lookup:onChangeToNextDict()
      assert.are.equal(1, lookup.dict_index)

      -- Wrap around prev
      lookup:onChangeToPrevDict()
      assert.are.equal(2, lookup.dict_index)

      -- Jump to first / last
      lookup:changeToFirstDict()
      assert.are.equal(1, lookup.dict_index)

      lookup:changeToLastDict()
      assert.are.equal(2, lookup.dict_index)
    end)

    it("should handle single result navigation", function()
      local lookup = DictQuickLookup:new({
        word = "test",
        results = { createDummyResults()[1] },
      })
      assert.is_false(lookup:isPrevDictAvaiable())
      assert.is_false(lookup:isNextDictAvaiable())

      lookup:onChangeToNextDict()
      assert.are.equal(1, lookup.dict_index)

      lookup:onChangeToPrevDict()
      assert.are.equal(1, lookup.dict_index)
    end)
  end)

  describe("changeDictionary and display properties", function()
    it("should format displaydictname with preferred dictionaries", function()
      local results = createDummyResults()
      local lookup = DictQuickLookup:new({
        word = "test",
        results = results,
        preferred_dictionaries = { "Dict 2", "Dict 1" },
      })

      -- Index 1 (Dict 1) is preferred dict #2 -> ❷ symbol
      assert.truthy(lookup.displaydictname:find("Dict 1"))

      -- Change to Dict 2 (preferred dict #1 -> ❶ symbol)
      lookup:changeDictionary(2)
      assert.truthy(lookup.displaydictname:find("Dict 2"))
    end)

    it("should add query suffix for 1st result", function()
      local results = createDummyResults()
      local lookup = DictQuickLookup:new({
        word = "queried_word",
        results = results,
      })

      -- Text result 1 should contain query suffix
      assert.truthy(lookup.definition:find("queried_word"))

      -- Switch to HTML result 2
      lookup:changeDictionary(2)
      assert.are.equal("def 2", lookup.definition)
    end)
  end)

  describe("HTML CSS generation", function()
    it("should generate html dictionary css", function()
      local lookup = DictQuickLookup:new({
        word = "test",
        results = createDummyResults(),
        css = "p { color: red; }",
      })

      local css = lookup:getHtmlDictionaryCss()
      assert.is_string(css)
      assert.is_true(#css > 0)
    end)
  end)

  describe("ReadPrev / ReadNext / MenuKeyPress result handlers", function()
    it("should handle onReadNextResult and onReadPrevResult", function()
      local lookup = DictQuickLookup:new({
        word = "test",
        results = createDummyResults(),
      })

      assert.is_true(lookup:onReadNextResult())
      assert.are.equal(2, lookup.dict_index)

      assert.is_true(lookup:onReadPrevResult())
      assert.are.equal(1, lookup.dict_index)
    end)

    it("should handle onMenuKeyPress", function()
      local lookup = DictQuickLookup:new({
        word = "test",
        results = createDummyResults(),
      })
      local called = false
      lookup.dict_title.left_icon_tap_callback = function()
        called = true
        return true
      end

      assert.is_true(lookup:onMenuKeyPress())
      assert.is_true(called)
    end)
  end)

  describe("Lifecycle events (onShow, onClose, onExit, onHoldClose)", function()
    it("should set dirty on onShow and onClose", function()
      local dirty_called = false
      UIManager.setDirty = function()
        dirty_called = true
      end

      local lookup = DictQuickLookup:new({
        word = "test",
        results = createDummyResults(),
      })

      assert.is_true(lookup:onShow())
      assert.is_true(dirty_called)

      lookup:onClose()
      assert.are.equal(0, #DictQuickLookup.window_list)
    end)

    it("should cleanup image blitbuffers on onClose", function()
      local free_called = false
      local dummy_bb = setmetatable({
        free = function()
          free_called = true
        end,
        getType = function()
          return "bb"
        end,
        getWidth = function()
          return 10
        end,
        getHeight = function()
          return 10
        end,
        getInverse = function(s)
          return s
        end,
      }, {
        __index = function()
          return function() end
        end,
      })
      local results = createDummyResults()
      results[1].images = { { bb = dummy_bb, width = 10, height = 10 } }

      local lookup = DictQuickLookup:new({
        word = "test",
        results = results,
      })

      lookup:onClose()
      assert.is_true(free_called)
    end)

    it("should close window and broadcast wiki languages on onExit", function()
      local close_called = false
      local broadcast_called = false
      UIManager.close = function(_, widget)
        close_called = true
        if widget and widget.onClose then
          widget:onClose()
        end
      end
      UIManager.broadcastEvent = function()
        broadcast_called = true
      end

      local lookup = DictQuickLookup:new({
        word = "test",
        results = createDummyResults(),
        is_wiki = true,
        ui = dummy_ui,
        update_wiki_languages_on_close = true,
        wiki_languages = { "en", "fr" },
      })

      lookup:onExit()
      assert.is_true(close_called)
      assert.is_true(broadcast_called)
    end)

    it("should handle save_highlight and highlight clear on onExit", function()
      local save_called = false
      local clear_called = false
      local mock_highlight = {
        saveHighlight = function()
          save_called = true
        end,
        clear = function()
          clear_called = true
        end,
        getClearId = function()
          return 1
        end,
      }

      local lookup = DictQuickLookup:new({
        word = "test",
        results = createDummyResults(),
        highlight = mock_highlight,
        save_highlight = true,
      })

      lookup:onExit()
      assert.is_true(save_called)
      assert.is_true(clear_called)
    end)

    it("should close all windows on onHoldClose", function()
      local closed_count = 0
      UIManager.close = function(_, widget)
        closed_count = closed_count + 1
        if widget and widget.onClose then
          widget:onClose()
        end
      end

      local _lookup1 = DictQuickLookup:new({
        word = "test1",
        results = createDummyResults(),
      })
      local lookup2 = DictQuickLookup:new({
        word = "test2",
        results = createDummyResults(),
      })

      assert.are.equal(2, #DictQuickLookup.window_list)

      lookup2:onHoldClose()
      assert.are.equal(0, #DictQuickLookup.window_list)
      assert.are.equal(2, closed_count)
    end)
  end)

  describe("lookupWikipedia", function()
    it("should broadcast LookupWikipedia event with parameters", function()
      local broadcast_called = false
      UIManager.broadcastEvent = function(_, ev)
        if ev and ev.handler == "onLookupWikipedia" then
          broadcast_called = true
        end
      end

      local lookup = DictQuickLookup:new({
        word = "original_word",
        results = createDummyResults(),
        is_wiki = true,
        ui = dummy_ui,
        lang = "en",
      })

      lookup:lookupWikipedia(false)
      assert.is_true(broadcast_called)
    end)
  end)

  describe("onLookupInputWord", function()
    it("should create input dialog and invoke callbacks", function()
      local lookup = DictQuickLookup:new({
        word = "test",
        results = createDummyResults(),
      })

      lookup:onLookupInputWord("hint_word")
      assert.truthy(lookup.input_dialog)
    end)
  end)

  describe("Button actions", function()
    it("should handle highlight button toggle", function()
      local mock_highlight = {
        saveHighlight = function() end,
        clear = function() end,
        getClearId = function()
          return 1
        end,
      }

      local lookup = DictQuickLookup:new({
        word = "test",
        results = createDummyResults(),
        highlight = mock_highlight,
        ui = { highlight = mock_highlight },
      })

      local hl_btn = lookup.button_table:getButtonById("highlight")
      assert.truthy(hl_btn)
      assert.is_false(lookup.save_highlight or false)

      hl_btn:callback()
      assert.is_true(lookup.save_highlight)
    end)

    it(
      "should build wiki fullpage layout with Save and Close buttons",
      function()
        local results = createDummyResults()
        results[1].is_wiki_fullpage = true

        local lookup = DictQuickLookup:new({
          word = "test",
          results = results,
          is_wiki = true,
          ui = dummy_ui,
          is_wiki_fullpage = true,
        })

        local save_btn = lookup.button_table:getButtonById("save")
        assert.truthy(save_btn)

        local close_btn = lookup.button_table:getButtonById("close")
        assert.truthy(close_btn)
      end
    )

    it("should build link button when selected_link is present", function()
      local lookup = DictQuickLookup:new({
        word = "test",
        results = createDummyResults(),
        selected_link = { link = "http://example.com" },
      })

      local link_btn = lookup.button_table:getButtonById("link")
      assert.truthy(link_btn)
    end)
  end)

  describe("Menus", function()
    it("should open results menu on onShowResultsMenu", function()
      local lookup = DictQuickLookup:new({
        word = "test",
        results = createDummyResults(),
      })

      assert.is_true(lookup:onShowResultsMenu())
      assert.are.equal(1, util.tableSize(lookup.menu_opened))
    end)

    it("should open alternative results menu on showResultsAltMenu", function()
      local results = createDummyResults()
      table.insert(results, {
        dict = "Dict 1",
        word = "word1_alt",
        definition = "def 1 alt",
        is_html = false,
      })

      local lookup = DictQuickLookup:new({
        word = "test",
        results = results,
      })

      lookup:showResultsAltMenu()
      assert.are.equal(1, util.tableSize(lookup.menu_opened))
    end)

    it("should open wiki results menu on showWikiResultsMenu", function()
      local lookup = DictQuickLookup:new({
        word = "test",
        results = createDummyResults(),
        is_wiki = true,
        ui = dummy_ui,
      })

      lookup:showWikiResultsMenu()
      assert.are.equal(1, util.tableSize(lookup.menu_opened))
    end)
  end)

  describe("Gesture handlers", function()
    it("should handle onTap outside, title, and definition", function()
      local lookup = DictQuickLookup:new({
        word = "test",
        results = createDummyResults(),
      })

      -- Tap outside window frame
      local outside_ev = { pos = Geom:new({ x = -10, y = -10, w = 1, h = 1 }) }
      assert.is_true(lookup:onTap(nil, outside_ev))

      -- Tap inside title
      local title_ev = { pos = lookup.dict_title.dimen:copy() }
      assert.is_true(lookup:onTap(nil, title_ev))

      -- Tap inside definition widget
      local def_ev = { pos = lookup.definition_widget.dimen:copy() }
      assert.is_true(lookup:onTap(nil, def_ev))
    end)

    it("should handle onSwipe in definition widget", function()
      local lookup = DictQuickLookup:new({
        word = "test",
        results = createDummyResults(),
      })

      local def_dimen = lookup.definition_widget.dimen

      -- Swipe west -> next dict
      local swipe_west = { pos = def_dimen:copy(), direction = "west" }
      assert.is_true(lookup:onSwipe(nil, swipe_west))
      assert.are.equal(2, lookup.dict_index)

      -- Swipe east -> prev dict
      local swipe_east = { pos = def_dimen:copy(), direction = "east" }
      assert.is_true(lookup:onSwipe(nil, swipe_east))
      assert.are.equal(1, lookup.dict_index)

      -- Swipe north -> refresh callback
      local refreshed = false
      lookup.refresh_callback = function()
        refreshed = true
      end
      local swipe_north = { pos = def_dimen:copy(), direction = "north" }
      assert.is_false(lookup:onSwipe(nil, swipe_north))
      assert.is_true(refreshed)
    end)

    it(
      "should handle forwarding text hold, touch, and mousewheel events",
      function()
        local lookup = DictQuickLookup:new({
          word = "test",
          results = createDummyResults(),
        })

        local ev = { pos = Geom:new({ x = 0, y = 0, w = 1, h = 1 }) }
        lookup:onHoldStartText(nil, ev)
        lookup:onHoldPanText(nil, ev)
        lookup:onHoldReleaseText(nil, ev)
        lookup:onForwardingTouch(nil, ev)
        lookup:onForwardingPan(nil, ev)

        -- Mousewheel scrolling forward / backward
        local mw_down = { from_mousewheel = true, relative = { y = -1 } }
        assert.is_true(lookup:onForwardingPanRelease(nil, mw_down))

        local mw_up = { from_mousewheel = true, relative = { y = 1 } }
        assert.is_true(lookup:onForwardingPanRelease(nil, mw_up))
      end
    )

    it("should adjust window position based on word_boxes", function()
      local word_boxes = {
        Geom:new({ x = 10, y = 200, w = 100, h = 30 }),
      }

      local lookup = DictQuickLookup:new({
        word = "test",
        results = createDummyResults(),
        word_boxes = word_boxes,
      })

      assert.truthy(lookup.region)
    end)

    it("should be modal by default", function()
      local lookup = DictQuickLookup:new({
        word = "test",
        results = createDummyResults(),
      })
      assert.is_true(lookup.modal)
    end)

    it(
      "should be placed above modal widgets in the UIManager window stack",
      function()
        local Widget = require("ui/widget/widget")
        local mock_modal = Widget:new({
          modal = true,
          dimen = Geom:new({ w = 100, h = 100 }),
        })
        local lookup = DictQuickLookup:new({
          word = "test",
          results = createDummyResults(),
        })

        -- Restore orig_show and orig_close temporarily for stack test
        UIManager.show = orig_show
        UIManager.close = orig_close

        UIManager:show(mock_modal)
        UIManager:show(lookup)

        local modal_idx, lookup_idx
        for idx, win in ipairs(UIManager._window_stack) do
          if win.widget == mock_modal then
            modal_idx = idx
          elseif win.widget == lookup then
            lookup_idx = idx
          end
        end

        UIManager:close(lookup)
        UIManager:close(mock_modal)

        assert.is_not_nil(modal_idx, "mock_modal should be in the window stack")
        assert.is_not_nil(
          lookup_idx,
          "DictQuickLookup should be in the window stack"
        )
        assert.is_true(
          lookup_idx > modal_idx,
          "DictQuickLookup should be above mock_modal in the stack"
        )
      end
    )
  end)
end)
