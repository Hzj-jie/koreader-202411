local ffi
local KOPTContext

describe("ffi/koptcontext module", function()
  local orig_ffi_string

  setup(function()
    require("commonrequire")
    ffi = require("ffi")
    orig_ffi_string = ffi.string
    ffi.string = function(ptr, len)
      if ptr == nil or ptr == ffi.null then
        error(
          "bad argument #1 to 'string' (cannot convert 'NULL' to 'const char *')\n"
            .. debug.traceback()
        )
      end
      return orig_ffi_string(ptr, len)
    end
    KOPTContext = require("ffi/koptcontext")
  end)

  teardown(function()
    ffi.string = orig_ffi_string
  end)

  it("initializes with default settings", function()
    local kc = KOPTContext.new()
    assert.are.equal(1, kc.trim)
    assert.are.equal(1, kc.wrap)
    assert.are.equal(2, kc.columns)
    assert.are.equal(1.2, kc.line_spacing)
    assert.are.equal(0.06, kc.margin)
  end)

  it("serializes and restores rectmaps matching allocated size", function()
    local kc = KOPTContext.new()
    kc:setLanguage("eng")
    kc.rectmaps.n = 2
    kc.rectmaps.na = 10
    kc.rectmaps.wrectmap = ffi.C.malloc(ffi.sizeof("WRECTMAP") * 2)

    local tbl = KOPTContext.totable(kc)
    ffi.C.free(kc.rectmaps.wrectmap)
    kc.rectmaps.wrectmap = nil
    kc.rectmaps.n = 0
    kc.rectmaps.na = 0

    assert.are.equal(2, tbl.rectmaps.n)
    assert.are.equal(2, tbl.rectmaps.na)

    local restored = KOPTContext.fromtable(tbl)
    assert.are.equal(2, restored.rectmaps.n)
    assert.are.equal(2, restored.rectmaps.na)
    if restored.rectmaps.wrectmap ~= nil then
      ffi.C.free(restored.rectmaps.wrectmap)
      restored.rectmaps.wrectmap = nil
    end
  end)

  it("handles version mismatch gracefully by returning nil", function()
    local kc = KOPTContext.new()
    kc:setLanguage("eng")
    kc.rectmaps.n = 1
    kc.rectmaps.na = 1
    kc.rectmaps.wrectmap = ffi.C.malloc(ffi.sizeof("WRECTMAP"))

    local tbl = KOPTContext.totable(kc)
    ffi.C.free(kc.rectmaps.wrectmap)
    kc.rectmaps.wrectmap = nil

    assert.is_not_nil(tbl)
    local restored = KOPTContext.fromtable(tbl)
    assert.is_not_nil(restored)
    if restored.rectmaps.wrectmap ~= nil then
      ffi.C.free(restored.rectmaps.wrectmap)
      restored.rectmaps.wrectmap = nil
    end

    tbl.__version__ = "mismatched_version_0.0.0"
    local mismatch_restored = KOPTContext.fromtable(tbl)
    assert.is_nil(mismatch_restored)
  end)
end)
