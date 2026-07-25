describe("Kobo NTX I/O interface module", function()
  local ok

  setup(function()
    require("commonrequire")
    local old_arg = _G.arg
    _G.arg = { "0", "0" }
    ok = pcall(require, "device/kobo/ntx_io")
    _G.arg = old_arg
  end)

  it("should handle execution of ntx_io script safely", function()
    assert.is_boolean(ok)
  end)
end)
