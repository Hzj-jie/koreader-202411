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
      local orig_format = getmetatable("").format
      getmetatable("").format = function(fmt, ...)
        if fmt == "%.1f" and select(1, ...) == 1.2 then
          return "1,2"
        end
        return orig_format(fmt, ...)
      end
      finally(function()
        getmetatable("").format = orig_format
      end)

      local tbl = { inf = math.huge }
      local res = serpent.line(tbl, { fixradix = true, comment = false })
      local loaded = loadstring("return " .. res)()
      assert.are.equal(math.huge, loaded.inf)
    end
  )

  it(
    "should serialize -math.huge accurately when fixradix is enabled",
    function()
      local orig_format = getmetatable("").format
      getmetatable("").format = function(fmt, ...)
        if fmt == "%.1f" and select(1, ...) == 1.2 then
          return "1,2"
        end
        return orig_format(fmt, ...)
      end
      finally(function()
        getmetatable("").format = orig_format
      end)

      local tbl = { neg_inf = -math.huge }
      local res = serpent.line(tbl, { fixradix = true, comment = false })
      local chunk, err = loadstring("return " .. res)
      assert.is_nil(err)
      local ok, loaded = pcall(chunk)
      assert.is_true(ok)
      assert.are.equal(-math.huge, loaded.neg_inf)
    end
  )
end)
