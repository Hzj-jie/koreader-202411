describe("Japanese plugin & Deinflector", function()
  local Deinflector
  local Japanese
  local G_reader_settings_orig

  setup(function()
    require("commonrequire")
    Deinflector = require("plugins/japanese.koplugin/deinflector")
    Japanese = require("plugins/japanese.koplugin/main")
    G_reader_settings_orig = _G.G_reader_settings
  end)

  describe("Deinflector initialization and inflection rules", function()
    it("should initialize Deinflector with rules loaded from JSON", function()
      local deinflector = Deinflector:new()
      assert.is_table(deinflector)
      assert.is_table(deinflector.rules)
      assert.is_table(deinflector.enabled_text_conversions)
      assert.is_truthy(next(deinflector.rules))
    end)

    it("should deinflect ichidan and godan past/negative forms verbatim", function()
      local deinflector = Deinflector:new()

      -- 食べた (tabeta) -> 食べる (taberu) [ichidan past]
      local results_eat = deinflector:deinflectVerbatim("食べた")
      local found_eat = false
      for _, res in ipairs(results_eat) do
        if res.term == "食べる" then
          found_eat = true
          break
        end
      end
      assert.is_true(found_eat)

      -- 読まない (yomanai) -> 読む (yomu) [godan negative]
      local results_read = deinflector:deinflectVerbatim("読まない")
      local found_read = false
      for _, res in ipairs(results_read) do
        if res.term == "読む" then
          found_read = true
          break
        end
      end
      assert.is_true(found_read)
    end)

    it("should support deinflect with text conversions (hiragana, katakana, half-width)", function()
      local deinflector = Deinflector:new()

      -- Half-width to full-width or katakana to hiragana conversions
      local results = deinflector:deinflect("たべた")
      assert.is_table(results)
      assert.is_true(#results > 0)
      local terms = {}
      for _, r in ipairs(results) do
        terms[r.term] = true
      end
      assert.is_true(terms["たべる"] or terms["たべた"])
    end)

    it("should respect disabled text conversions in deinflect", function()
      local deinflector = Deinflector:new()
      deinflector.enabled_text_conversions = {}
      local results = deinflector:deinflect("食べた")
      assert.is_table(results)
      assert.is_true(#results > 0)
      assert.are.equal("食べた", results[1].term)
    end)

    it("should generate menu items for deinflector settings", function()
      local deinflector = Deinflector:new()
      local menu_items = deinflector:genMenuItems()
      assert.is_table(menu_items)
      assert.are.equal(2, #menu_items)

      -- Item 1: text conversions submenu
      local sub_item = menu_items[1]
      assert.is_function(sub_item.text_func)
      assert.is_string(sub_item.text_func())
      assert.is_table(sub_item.sub_item_table)
      assert.is_true(#sub_item.sub_item_table > 0)

      -- Item 2: deinflector information
      local info_item = menu_items[2]
      assert.is_string(info_item.text)
      assert.is_true(info_item.keep_menu_open)
      assert.is_function(info_item.callback)
    end)

    it("should toggle text conversion options in menu callbacks", function()
      local saved_key, saved_val
      _G.G_reader_settings = {
        read = function() end,
        save = function(_self, key, val)
          saved_key = key
          saved_val = val
        end,
      }

      local deinflector = Deinflector:new()
      local menu_items = deinflector:genMenuItems()
      local conv_items = menu_items[1].sub_item_table

      local first_conv = conv_items[1]
      local initial_checked = first_conv.checked_func()
      first_conv.callback(nil)
      assert.are.equal(not initial_checked, first_conv.checked_func())
      assert.are.equal("language_japanese_text_conversions", saved_key)
      assert.is_table(saved_val)

      _G.G_reader_settings = G_reader_settings_orig
    end)
  end)

  describe("Japanese language plugin", function()
    it("should identify supported language codes", function()
      local jp = Japanese:new()
      assert.is_true(jp:supportsLanguage("ja"))
      assert.is_true(jp:supportsLanguage("jpn"))
      assert.is_false(jp:supportsLanguage("en"))
      assert.is_false(jp:supportsLanguage("zh"))
      assert.is_false(jp:supportsLanguage("de"))
    end)

    it("should handle onWordLookup with Japanese and non-CJK text", function()
      local jp = Japanese:new()
      -- Non-CJK returns nil
      assert.is_nil(jp:onWordLookup({ text = "EnglishText" }))
      assert.is_nil(jp:onWordLookup({ text = "12345!?" }))

      -- Japanese inflected word returns candidates
      local candidates = jp:onWordLookup({ text = "食べた" })
      assert.is_table(candidates)
      assert.is_true(#candidates >= 2)
      local has_taberu = false
      for _, c in ipairs(candidates) do
        if c == "食べる" then
          has_taberu = true
          break
        end
      end
      assert.is_true(has_taberu)
    end)

    it("should handle onWordSelection expansion using dictionary lookup", function()
      local jp = Japanese:new()
      jp.dictionary = {
        rawSdcv = function(_self, words)
          local results = {}
          for i, w in ipairs(words) do
            if w == "食べる" then
              results[i] = { { definition = "to eat" } }
            else
              results[i] = {}
            end
          end
          return false, results
        end,
      }

      local text_sequence = {
        [0] = "食",
        [1] = "べ",
        [2] = "た",
        [3] = "。",
      }

      local args = {
        pos0 = 0,
        text = "食",
        callbacks = {
          get_next_char_pos = function(p)
            if p >= 3 then
              return nil
            end
            return p + 1
          end,
          get_text_in_range = function(_p0, p1)
            local s = ""
            for i = 0, p1 do
              s = s .. (text_sequence[i] or "")
            end
            return s
          end,
        },
      }

      local sel = jp:onWordSelection(args)
      assert.is_table(sel)
      assert.are.equal(0, sel[1])
      assert.are.equal(2, sel[2])

      -- Non-CJK skips expansion
      local no_cjk_args = {
        text = "abc",
      }
      assert.is_nil(jp:onWordSelection(no_cjk_args))
    end)

    it("should generate plugin menu item with scan length options", function()
      local jp = Japanese:new()
      local menu = jp:genMenuItem()
      assert.is_table(menu)
      assert.is_string(menu.text)
      assert.is_table(menu.sub_item_table)
      assert.is_true(#menu.sub_item_table >= 1)

      local scan_item = menu.sub_item_table[1]
      assert.is_function(scan_item.text_func)
      assert.is_truthy(scan_item.text_func():find("Text scan length"))
    end)
  end)
end)
