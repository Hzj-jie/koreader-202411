-- luacheck: ignore 122
describe("trace_require tool", function()
  local orig_require

  setup(function()
    require("commonrequire")
    orig_require = _G.require
  end)

  after_each(function()
    _G.require = orig_require
  end)

  it("should trace module requiring and return loaded module", function()
    dofile("tools/trace_require.lua")
    local mod = require("math")
    assert.is_table(mod)
    assert.are.equal(math.sin, mod.sin)
  end)
end)
