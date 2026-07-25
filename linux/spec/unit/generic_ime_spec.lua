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
end)
