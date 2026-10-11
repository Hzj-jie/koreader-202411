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

  it("handles missing debug info without crashing on short_src", function()
    dofile("tools/trace_require.lua")
    local orig_getinfo = debug.getinfo
    debug.getinfo = function(level)
      if level == 2 then
        return { short_src = "[C]" }
      elseif level == 3 then
        return nil
      end
      return orig_getinfo(level)
    end
    finally(function()
      debug.getinfo = orig_getinfo
    end)

    assert.has_no.errors(function()
      require("table")
    end)
  end)

  it("guards against log10 of zero when module load elapse is zero", function()
    dofile("tools/trace_require.lua")
    local log10_arg = nil
    local orig_log10 = math.log10
    math.log10 = function(val)
      log10_arg = val
      return orig_log10(val)
    end
    local orig_clock = os.clock
    os.clock = function()
      return 100.0
    end
    finally(function()
      math.log10 = orig_log10
      os.clock = orig_clock
    end)

    require("string")

    -- Exposes defect: when elapse == 0, trace_require computes math.log10(0) (-inf)
    assert.is_not_nil(log10_arg)
    assert.is_true(log10_arg > 0)
  end)
end)
