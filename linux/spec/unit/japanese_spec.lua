-- luacheck: ignore 122
describe("Japanese plugin unit tests", function()
  local Japanese

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
    Japanese = require("plugins/japanese.koplugin/main")
  end)

  teardown(function()
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
  end)

  it("should check supportsLanguage correctly", function()
    local plugin = Japanese:new({})
    assert.is_true(plugin:supportsLanguage("ja"))
    assert.is_true(plugin:supportsLanguage("jpn"))
    assert.is_false(plugin:supportsLanguage("en"))
    assert.is_false(plugin:supportsLanguage("zh"))
  end)

  it("should return deinflected words in onWordLookup", function()
    local plugin = Japanese:new({})
    plugin:init()

    local res = plugin:onWordLookup({ text = "食べた" })
    assert.is_table(res)
    local found_taberu = false
    for _, word in ipairs(res) do
      if word == "食べる" then
        found_taberu = true
        break
      end
    end
    assert.is_true(found_taberu)
  end)

  it("should return nil in onWordLookup for non-CJK text", function()
    local plugin = Japanese:new({})
    plugin:init()
    assert.is_nil(plugin:onWordLookup({ text = "hello" }))
  end)

  it("should return nil in onWordSelection for non-CJK text", function()
    local plugin = Japanese:new({})
    plugin:init()
    local args = {
      text = "English",
      pos0 = 0,
      callbacks = {},
    }
    assert.is_nil(plugin:onWordSelection(args))
  end)

  it(
    "should select 1-character Japanese word before punctuation in onWordSelection",
    function()
      local plugin = Japanese:new({})
      plugin:init()

      -- Simulate text "猫。" where pos0=0, pos1=1 ("猫"), pos2=2 ("。")
      local text_chars = { "猫", "。" }
      local callbacks = {
        get_next_char_pos = function(pos)
          if pos == 0 then
            return 1
          elseif pos == 1 then
            return 2
          end
          return nil
        end,
        get_text_in_range = function(p0, p1)
          if p0 == 0 and p1 == 1 then
            return "猫"
          elseif p0 == 0 and p1 == 2 then
            return "猫。"
          end
          return ""
        end,
      }

      local queried_words = nil
      plugin.dictionary = {
        rawSdcv = function(_, words)
          queried_words = words
          -- If "猫" is in words, return a mock definition for it
          local results = {}
          for _, w in ipairs(words) do
            if w == "猫" then
              table.insert(results, { { definition = "cat" } })
            else
              table.insert(results, {})
            end
          end
          return false, results
        end,
      }

      local res = plugin:onWordSelection({
        pos0 = 0,
        text = "猫",
        callbacks = callbacks,
      })

      -- The 1-char word "猫" should be checked and selected: range { 0, 1 }.
      assert.is_not_nil(queried_words)
      local queried_neko = false
      for _, w in ipairs(queried_words) do
        if w == "猫" then
          queried_neko = true
          break
        end
      end
      assert.is_true(queried_neko)
      assert.is_table(res)
      assert.are.same({ 0, 1 }, res)
    end
  )

  it(
    "should handle 1-character Japanese word at end of text without crashing on nil current_end",
    function()
      local plugin = Japanese:new({})
      plugin:init()

      -- Simulate single character "本" at end of text
      local callbacks = {
        get_next_char_pos = function(pos)
          if pos == 0 then
            return 1
          end
          return nil
        end,
        get_text_in_range = function(_p0, _p1)
          return "本"
        end,
      }

      plugin.dictionary = {
        rawSdcv = function(_, words)
          local results = {}
          for _, w in ipairs(words) do
            if w == "本" then
              table.insert(results, { { definition = "book" } })
            else
              table.insert(results, {})
            end
          end
          return false, results
        end,
      }

      assert.has_no.errors(function()
        local res = plugin:onWordSelection({
          pos0 = 0,
          text = "本",
          callbacks = callbacks,
        })
        assert.are.same({ 0, 1 }, res)
      end)
    end
  )

  it("should perform zero expansions when max_scan_length is 0", function()
    local plugin = Japanese:new({})
    plugin:init()
    plugin.max_scan_length = 0

    local next_char_called = 0
    local callbacks = {
      get_next_char_pos = function(pos)
        next_char_called = next_char_called + 1
        if pos == 0 then
          return 1
        elseif pos == 1 then
          return 2
        end
        return nil
      end,
      get_text_in_range = function(p0, p1)
        if p0 == 0 and p1 == 1 then
          return "本"
        end
        return "本を"
      end,
    }

    plugin.dictionary = {
      rawSdcv = function(_, words)
        local results = {}
        for _, w in ipairs(words) do
          if w == "本" then
            table.insert(results, { { definition = "book" } })
          else
            table.insert(results, {})
          end
        end
        return false, results
      end,
    }

    local res = plugin:onWordSelection({
      pos0 = 0,
      text = "本",
      callbacks = callbacks,
    })
    assert.are.same({ 0, 1 }, res)
    -- pos1 calculation called get_next_char_pos(0) once, but the expansion loop should not advance current_end past pos1
    assert.are.equal(1, next_char_called)
  end)

  it(
    "should preserve unmapped voiced and semi-voiced marks in deinflector",
    function()
      local Deinflector = require("plugins/japanese.koplugin/deinflector")
      local d = Deinflector:new({
        enabled_text_conversions = {
          ["halfwidth_to_fullwidth"] = false,
          ["katakana_to_hiragana"] = true,
          ["hiragana_to_katakana"] = true,
        },
      })
      local res1 = d:deinflect("ﾀﾞﾒ")
      local found1 = false
      for _, item in ipairs(res1) do
        assert.are_not.equal("ﾀﾒ", item.term)
        if item.term == "ﾀﾞﾒ" then
          found1 = true
        end
      end
      assert.is_true(found1)

      local res2 = d:deinflect("あﾞ")
      local found2 = false
      for _, item in ipairs(res2) do
        if item.term == "アﾞ" then
          found2 = true
          break
        end
      end
      assert.is_true(found2)
    end
  )
end)
