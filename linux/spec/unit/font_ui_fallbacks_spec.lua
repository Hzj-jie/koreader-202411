local FontUIFallbacks
local FontList
local UIManager
local Font
local InfoMessage
local util

local function contains(tbl, val)
  for _, v in ipairs(tbl) do
    if v == val then
      return true
    end
  end
  return false
end

describe("FontUIFallbacks element", function()
  local orig_getFontList
  local orig_fontinfo
  local orig_show
  local orig_askForRestart

  setup(function()
    require("commonrequire")
    FontList = require("fontlist")
    UIManager = require("ui/uimanager")
    Font = require("ui/font")
    InfoMessage = require("ui/widget/infomessage")
    util = require("util")
  end)

  before_each(function()
    orig_getFontList = FontList.getFontList
    orig_fontinfo = FontList.fontinfo
    orig_show = UIManager.show
    orig_askForRestart = UIManager.askForRestart

    if G_reader_settings:has("font_ui_fallbacks") then
      G_reader_settings:delete("font_ui_fallbacks")
    end

    package.loaded["ui/elements/font_ui_fallbacks"] = nil
    FontUIFallbacks = require("ui/elements/font_ui_fallbacks")
  end)

  after_each(function()
    FontList.getFontList = orig_getFontList
    FontList.fontinfo = orig_fontinfo
    UIManager.show = orig_show
    UIManager.askForRestart = orig_askForRestart

    if G_reader_settings:has("font_ui_fallbacks") then
      G_reader_settings:delete("font_ui_fallbacks")
    end
  end)

  it("should export correct element structure", function()
    assert.is_table(FontUIFallbacks)
    assert.is_string(FontUIFallbacks.text)
    assert.is_function(FontUIFallbacks.sub_item_table_func)
  end)

  it(
    "should return default menu items with hardcoded fallback fonts",
    function()
      local menu_items = FontUIFallbacks.sub_item_table_func()
      assert.is_table(menu_items)

      -- Item 1: About info item
      local about_item = menu_items[1]
      assert.is_string(about_item.text)
      assert.is_true(about_item.separator)
      assert.is_true(about_item.keep_menu_open)
      assert.is_function(about_item.callback)

      -- Hardcoded fallbacks should follow
      local expected_hardcoded = {
        "Noto Sans CJK SC (TC, JA, KO)",
        "Noto Sans Arabic UI",
        "Noto Sans Devanagari UI",
        "Noto Sans Bengali UI",
      }

      assert.are.equal(#expected_hardcoded + 1, #menu_items)

      for i, expected_name in ipairs(expected_hardcoded) do
        local item = menu_items[i + 1]
        assert.are.equal(expected_name, item.text)
        assert.is_true(item.checked_func())
        assert.is_false(item.enabled_func())
      end

      -- The last hardcoded item should have separator = true
      assert.is_true(menu_items[#menu_items].separator)
    end
  )

  it("should identify valid fallback candidates from FontList", function()
    local mock_paths = {
      "/fonts/NotoSansHebrew-Regular.ttf",
      "/fonts/NotoEmoji.ttf",
      "/fonts/NotoSansMono-Regular.ttf",
      "/fonts/NotoSansBold.ttf",
      "/fonts/NotoSerif.ttf",
      "/fonts/MultiFace.ttf",
      "/fonts/Roboto.ttf",
    }

    FontList.getFontList = function(self)
      local list = util.tableDeepCopy(orig_getFontList(self))
      for _, p in ipairs(mock_paths) do
        table.insert(list, p)
      end
      return list
    end

    FontList.fontinfo = util.tableDeepCopy(orig_fontinfo)
    FontList.fontinfo["/fonts/NotoSansHebrew-Regular.ttf"] = {
      {
        name = "Noto Sans Hebrew",
        path = "/fonts/NotoSansHebrew-Regular.ttf",
        bold = false,
        italic = false,
        serif = false,
        mono = false,
      },
    }
    FontList.fontinfo["/fonts/NotoEmoji.ttf"] = {
      {
        name = "Noto Emoji",
        path = "/fonts/NotoEmoji.ttf",
        bold = false,
        italic = false,
        serif = false,
        mono = false,
      },
    }
    FontList.fontinfo["/fonts/NotoSansMono-Regular.ttf"] = {
      { name = "Noto Sans Mono", mono = true },
    }
    FontList.fontinfo["/fonts/NotoSansBold.ttf"] = {
      { name = "Noto Sans Bold", bold = true },
    }
    FontList.fontinfo["/fonts/NotoSerif.ttf"] = {
      { name = "Noto Serif", serif = true },
    }
    FontList.fontinfo["/fonts/MultiFace.ttf"] = {
      { name = "Face 1" },
      { name = "Face 2" },
    }
    FontList.fontinfo["/fonts/Roboto.ttf"] = {
      { name = "Roboto" },
    }

    package.loaded["ui/elements/font_ui_fallbacks"] = nil
    FontUIFallbacks = require("ui/elements/font_ui_fallbacks")

    local menu_items = FontUIFallbacks.sub_item_table_func()

    local names = {}
    for _, item in ipairs(menu_items) do
      table.insert(names, item.text)
    end

    assert.is_true(contains(names, "Noto Sans Hebrew"))
    assert.is_true(contains(names, "Noto Emoji"))
    assert.is_false(contains(names, "Noto Sans Mono"))
    assert.is_false(contains(names, "Noto Sans Bold"))
    assert.is_false(contains(names, "Noto Serif"))
    assert.is_false(contains(names, "Roboto"))

    -- Find item for candidate
    local candidate_item
    for _, item in ipairs(menu_items) do
      if item.text == "Noto Sans Hebrew" then
        candidate_item = item
        break
      end
    end

    assert.is_not_nil(candidate_item)
    assert.is_false(candidate_item.checked_func())
    assert.is_true(candidate_item.enabled_func())
  end)

  it(
    "should load stored font_ui_fallbacks settings and position them correctly",
    function()
      G_reader_settings:save("font_ui_fallbacks", {
        "/fonts/NotoSansHebrew-Regular.ttf",
      })

      FontList.getFontList = function(self)
        local list = util.tableDeepCopy(orig_getFontList(self))
        table.insert(list, "/fonts/NotoSansHebrew-Regular.ttf")
        return list
      end

      FontList.fontinfo = util.tableDeepCopy(orig_fontinfo)
      FontList.fontinfo["/fonts/NotoSansHebrew-Regular.ttf"] = {
        {
          name = "Noto Sans Hebrew",
          path = "/fonts/NotoSansHebrew-Regular.ttf",
        },
      }

      package.loaded["ui/elements/font_ui_fallbacks"] = nil
      FontUIFallbacks = require("ui/elements/font_ui_fallbacks")

      local menu_items = FontUIFallbacks.sub_item_table_func()

      -- Stored additional fallback should be inserted at index 3 (after About item + Noto Sans CJK SC)
      local item = menu_items[3]
      assert.are.equal("Noto Sans Hebrew", item.text)
      assert.is_true(item.checked_func())
      assert.is_true(item.enabled_func())
    end
  )

  it(
    "should prune non-existent font paths from font_ui_fallbacks setting",
    function()
      G_reader_settings:save("font_ui_fallbacks", {
        "/fonts/MissingFont.ttf",
      })

      package.loaded["ui/elements/font_ui_fallbacks"] = nil
      FontUIFallbacks = require("ui/elements/font_ui_fallbacks")

      FontUIFallbacks.sub_item_table_func()

      assert.is_false(G_reader_settings:has("font_ui_fallbacks"))
    end
  )

  it("should allow toggling on an unchecked candidate font", function()
    FontList.getFontList = function(self)
      local list = util.tableDeepCopy(orig_getFontList(self))
      table.insert(list, "/fonts/NotoSansHebrew-Regular.ttf")
      return list
    end

    FontList.fontinfo = util.tableDeepCopy(orig_fontinfo)
    FontList.fontinfo["/fonts/NotoSansHebrew-Regular.ttf"] = {
      {
        name = "Noto Sans Hebrew",
        path = "/fonts/NotoSansHebrew-Regular.ttf",
      },
    }

    local restart_called = false
    UIManager.askForRestart = function()
      restart_called = true
    end

    package.loaded["ui/elements/font_ui_fallbacks"] = nil
    FontUIFallbacks = require("ui/elements/font_ui_fallbacks")

    local menu_items = FontUIFallbacks.sub_item_table_func()

    local candidate_item
    for _, item in ipairs(menu_items) do
      if item.text == "Noto Sans Hebrew" then
        candidate_item = item
        break
      end
    end

    assert.is_not_nil(candidate_item)
    assert.is_false(candidate_item.checked_func())

    -- Toggle candidate ON
    candidate_item.callback()

    assert.is_true(restart_called)
    assert.is_true(candidate_item.checked_func())

    local saved = G_reader_settings:read("font_ui_fallbacks")
    assert.is_table(saved)
    assert.are.equal("/fonts/NotoSansHebrew-Regular.ttf", saved[1])
  end)

  it("should allow toggling off a checked fallback font", function()
    G_reader_settings:save("font_ui_fallbacks", {
      "/fonts/NotoSansHebrew-Regular.ttf",
    })

    FontList.getFontList = function(self)
      local list = util.tableDeepCopy(orig_getFontList(self))
      table.insert(list, "/fonts/NotoSansHebrew-Regular.ttf")
      return list
    end

    FontList.fontinfo = util.tableDeepCopy(orig_fontinfo)
    FontList.fontinfo["/fonts/NotoSansHebrew-Regular.ttf"] = {
      {
        name = "Noto Sans Hebrew",
        path = "/fonts/NotoSansHebrew-Regular.ttf",
      },
    }

    local restart_called = false
    UIManager.askForRestart = function()
      restart_called = true
    end

    package.loaded["ui/elements/font_ui_fallbacks"] = nil
    FontUIFallbacks = require("ui/elements/font_ui_fallbacks")

    local menu_items = FontUIFallbacks.sub_item_table_func()

    local checked_item
    for _, item in ipairs(menu_items) do
      if item.text == "Noto Sans Hebrew" then
        checked_item = item
        break
      end
    end

    assert.is_not_nil(checked_item)
    assert.is_true(checked_item.checked_func())

    -- Toggle candidate OFF
    checked_item.callback()

    assert.is_true(restart_called)
    assert.is_false(checked_item.checked_func())
    assert.is_false(G_reader_settings:has("font_ui_fallbacks"))
  end)

  it("should show warning when max fallback font limit is reached", function()
    local paths = {}
    local fontinfo_mock = util.tableDeepCopy(orig_fontinfo)
    for i = 1, Font.additional_fallback_max_nb do
      local p = "/fonts/NotoSansFont" .. i .. ".ttf"
      table.insert(paths, p)
      fontinfo_mock[p] = {
        { name = "Noto Sans Font" .. i, path = p },
      }
    end

    -- Add one extra candidate path
    local extra_p = "/fonts/NotoSansExtra.ttf"
    table.insert(paths, extra_p)
    fontinfo_mock[extra_p] = {
      { name = "Noto Sans Extra", path = extra_p },
    }

    -- Set max fallbacks already selected
    local initial_fallbacks = {}
    for i = 1, Font.additional_fallback_max_nb do
      table.insert(initial_fallbacks, "/fonts/NotoSansFont" .. i .. ".ttf")
    end
    G_reader_settings:save("font_ui_fallbacks", initial_fallbacks)

    FontList.getFontList = function(self)
      local list = util.tableDeepCopy(orig_getFontList(self))
      for _, p in ipairs(paths) do
        table.insert(list, p)
      end
      return list
    end
    FontList.fontinfo = fontinfo_mock

    local shown_widget
    UIManager.show = function(self_ui, widget)
      shown_widget = widget
    end

    local restart_called = false
    UIManager.askForRestart = function()
      restart_called = true
    end

    package.loaded["ui/elements/font_ui_fallbacks"] = nil
    FontUIFallbacks = require("ui/elements/font_ui_fallbacks")

    local menu_items = FontUIFallbacks.sub_item_table_func()

    local extra_item
    for _, item in ipairs(menu_items) do
      if item.text == "Noto Sans Extra" then
        extra_item = item
        break
      end
    end

    assert.is_not_nil(extra_item)
    assert.is_false(extra_item.checked_func())

    -- Attempt to toggle extra item ON when limit is reached
    extra_item.callback()

    assert.is_false(restart_called)
    assert.is_not_nil(shown_widget)
    assert.is_not_nil(shown_widget.text)
  end)

  it("should trigger InfoMessage dialog from About item callback", function()
    local shown_widget
    UIManager.show = function(self_ui, widget)
      shown_widget = widget
    end

    local menu_items = FontUIFallbacks.sub_item_table_func()
    local about_item = menu_items[1]

    about_item.callback()

    assert.is_not_nil(shown_widget)
    assert.is_not_nil(shown_widget.text)
  end)
end)
