local Utf8Proc

describe("ffi/utf8proc module", function()
  setup(function()
    require("commonrequire")
    Utf8Proc = require("ffi/utf8proc")
  end)

  it("counts unicode codepoints accurately", function()
    local count = Utf8Proc.count("hello")
    assert.are.equal(5, count)

    local cjk_count = Utf8Proc.count("你好世界")
    assert.are.equal(4, cjk_count)
  end)

  it("normalizes strings to NFC form", function()
    local normalized = Utf8Proc.normalize_NFC("café")
    assert.is_string(normalized)
    assert.are.equal("café", normalized)
  end)

  it("converts strings with lowercase_dumb and uppercase_dumb", function()
    assert.are.equal("hello world", Utf8Proc.lowercase_dumb("HELLO WORLD"))
    assert.are.equal("HELLO WORLD", Utf8Proc.uppercase_dumb("hello world"))
  end)

  it(
    "does not mutate LuaJIT global interned string memory in cased_dumb",
    function()
      local baseline = (" "):rep(10)
      assert.are.equal("          ", baseline)

      Utf8Proc.lowercase_dumb("A")

      -- In expected behavior, Lua strings are immutable and ten spaces must remain ten spaces
      -- In production, Utf8Proc.cased_dumb casts (" "):rep(10) to a mutable C pointer and mutates it
      local after = (" "):rep(10)
      assert.are.equal("          ", after)
    end
  )
end)
