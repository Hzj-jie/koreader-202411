local serpent

describe("serpent module", function()
  setup(function()
    require("commonrequire")
    serpent = require("ffi/serpent")
  end)

  it("should serialize and deserialize basic tables", function()
    local tbl = { a = 1, b = "hello", c = { true, false } }
    local res = serpent.line(tbl, { comment = false, sortkeys = true })
    local loaded = loadstring("return " .. res)()
    assert.are.same(tbl, loaded)
  end)

  it("should format numbers and preserve floating point values", function()
    local tbl = { pi = 3.141592653589793 }
    local res = serpent.line(tbl, { comment = false })
    local loaded = loadstring("return " .. res)()
    assert.are.equal(tbl.pi, loaded.pi)
  end)

  it("should serialize math.huge as 1/0 without fixradix", function()
    local tbl = { inf = math.huge, neg_inf = -math.huge }
    local res = serpent.line(tbl, { comment = false, sortkeys = true })
    local loaded = loadstring("return " .. res)()
    assert.are.equal(math.huge, loaded.inf)
    assert.are.equal(-math.huge, loaded.neg_inf)
  end)

  it(
    "should serialize math.huge accurately when fixradix is enabled",
    function()
      local tbl = { inf = math.huge }
      local res = serpent.line(tbl, { fixradix = true, comment = false })
      local loaded = loadstring("return " .. res)()
      assert.are.equal(math.huge, loaded.inf)
    end
  )

  it(
    "should serialize -math.huge accurately when fixradix is enabled",
    function()
      local tbl = { neg_inf = -math.huge }
      local res = serpent.line(tbl, { fixradix = true, comment = false })
      local chunk, err = loadstring("return " .. res)
      assert.is_nil(err)
      local ok, loaded = pcall(chunk)
      assert.is_true(ok)
      assert.are.equal(-math.huge, loaded.neg_inf)
    end
  )

  it(
    "should validate radix formatting using percent format specifier",
    function()
      local formatted = (".1f"):format(1.2)
      assert.are.equal("1.2", formatted)
    end
  )
end)
