local IME = require("ui/data/keyboardlayouts/generic_ime")

describe("GenericIME module", function()
  local dummy_code_map = {
    ["ni"] = { "你", "拟" },
    ["hao"] = { "好", "号" },
    ["nihank"] = "你好",
  }

  local ime

  setup(function()
    ime = IME:new({
      code_map = dummy_code_map,
    })
  end)

  it("should initialize sorted codes and key maps", function()
    assert.is_not_nil(ime.sorted_codes)
    assert.is_true(#ime.sorted_codes >= 3)
  end)

  it("should retrieve candidate list for exact code", function()
    local candi = ime:getCandi("ni")
    assert.is_same(candi, { "你", "拟" })
  end)

  it("should retrieve single candidate wrapped in array", function()
    local candi = ime:getCandi("nihank")
    assert.is_same(candi, { "你好" })
  end)

  it("should check if code map entry is unique", function()
    local unique = ime:uniqueMap("nihank")
    assert.is_true(unique)
  end)

  it("should clear stack and reset status", function()
    ime:clear_stack()
    assert.is_equal(ime.last_key, "")
    assert.is_equal(ime.last_index, 0)

    ime:reset_status()
    assert.is_equal(ime.last_key, "")
  end)

  it("should handle unknown code lookup gracefully", function()
    local candi = ime:getCandi("nonexistentcode")
    assert.is_same(candi, {})
  end)

  describe("InputBox composition and deletion", function()
    local function createMockInputBox()
      local box = {
        deleted = 0,
        added = {},
      }
      box.delChar = {
        raw_method_call = function(_self)
          box.deleted = box.deleted + 1
        end,
      }
      box.addChars = {
        raw_method_call = function(_self, str)
          table.insert(box.added, str)
        end,
      }
      return box
    end

    it("composes strokes, switches candidates, and separates on space", function()
      local ime_comp = IME:new({
        code_map = dummy_code_map,
        show_candi_callback = function()
          return true
        end,
        switch_char = "SWITCH",
        switch_char_prev = "SWITCH_PREV",
      })
      local box = createMockInputBox()

      -- Add first stroke 'n'
      ime_comp:wrappedAddChars(box, "n")
      assert.is_true(ime_comp:hasCandidates())

      -- Add second stroke 'i' -> candidate '你'
      ime_comp:wrappedAddChars(box, "i")
      local hint = ime_comp:getHintChars()
      assert.is_truthy(hint:find("你"))

      -- Switch candidate forward
      ime_comp:wrappedAddChars(box, "SWITCH")
      assert.is_truthy(ime_comp:getHintChars():find("拟"))

      -- Switch candidate backward
      ime_comp:wrappedAddChars(box, "SWITCH_PREV")
      assert.is_truthy(ime_comp:getHintChars():find("你"))

      -- Separate via space
      ime_comp:wrappedAddChars(box, " ")
      assert.is_false(ime_comp:hasCandidates())
    end)

    it("handles stepped deletion and local deletion", function()
      local ime_del = IME:new({
        code_map = dummy_code_map,
      })
      local box = createMockInputBox()

      -- Add 'n' then 'i'
      ime_del:wrappedAddChars(box, "n")
      ime_del:wrappedAddChars(box, "i")
      assert.is_true(ime_del:hasCandidates())

      -- Stepped deletion of 'i'
      ime_del:wrappedDelChar(box)
      assert.is_true(ime_del:hasCandidates())

      -- Deletion of 'n'
      ime_del:wrappedDelChar(box)
      assert.is_false(ime_del:hasCandidates())

      -- Deletion with empty stack delegates to inputbox
      local prev_deleted = box.deleted
      ime_del:wrappedDelChar(box)
      assert.is_equal(prev_deleted + 1, box.deleted)

      -- Local del clears stack
      ime_del:wrappedAddChars(box, "h")
      ime_del:wrappedAddChars(box, ime_del.local_del)
      assert.is_false(ime_del:hasCandidates())
    end)

    it("passes non-code characters directly to inputbox", function()
      local ime_passthrough = IME:new({
        code_map = dummy_code_map,
      })
      local box = createMockInputBox()

      ime_passthrough:wrappedAddChars(box, "1", "1")
      assert.is_equal("1", box.added[#box.added])
    end)

    it("handles uppercase input with has_case", function()
      local ime_case = IME:new({
        code_map = {
          ["abc"] = { "abc" },
        },
        has_case = true,
      })
      local box = createMockInputBox()

      ime_case:wrappedAddChars(box, "a", "A")
      ime_case:wrappedAddChars(box, "b", "b")
      ime_case:wrappedAddChars(box, "c", "c")
      local hint = ime_case:getHintChars()
      assert.is_truthy(hint:find("Abc"))
    end)

    it("handles auto_separate_callback for unique code mappings", function()
      local ime_autosep = IME:new({
        code_map = {
          ["z"] = "Z_CHAR",
        },
        auto_separate_callback = function()
          return true
        end,
      })
      local box = createMockInputBox()

      ime_autosep:wrappedAddChars(box, "z")
      assert.is_false(ime_autosep:hasCandidates())
    end)

    it("handles wildcard matching and candidate limits", function()
      local ime_wildcard = IME:new({
        code_map = {
          ["ab"] = "AB",
          ["ac"] = "AC",
        },
        W = "?",
        keys_string = "abc",
      })
      local box = createMockInputBox()

      ime_wildcard:wrappedAddChars(box, "a")
      ime_wildcard:wrappedAddChars(box, "?")
      assert.is_true(ime_wildcard:hasCandidates())

      -- Exceeding max wildcards returns nil
      assert.is_nil(ime_wildcard:getCandidates("??????"))
    end)
  end)
end)
