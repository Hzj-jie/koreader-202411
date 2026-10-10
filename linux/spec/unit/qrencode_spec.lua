local qrencode

describe("ffi/qrencode module", function()
  setup(function()
    require("commonrequire")
    qrencode = require("ffi/qrencode")
  end)

  it("generates a QR code grid for short text", function()
    local ok, grid = qrencode.qrcode("hello world")
    assert.is_true(ok)
    assert.is_table(grid)
    assert.is_true(#grid >= 21)
  end)

  it(
    "generates a QR code grid with specified error correction level",
    function()
      local ok, grid = qrencode.qrcode("https://koreader.rocks", 2)
      assert.is_true(ok)
      assert.is_table(grid)
      assert.is_true(#grid >= 21)
    end
  )

  it(
    "returns an error or nil when payload length exceeds Version 40 capacity",
    function()
      local _, fn = debug.getupvalue(qrencode.qrcode, 1)
      local _, get_version_eclevel = debug.getupvalue(fn, 2)
      -- 3000 bytes in binary mode exceeds maximum Version 40 capacity (2953 bytes).
      local version, ec = get_version_eclevel(3000, 3, 1)
      assert.is_nil(version)
    end
  )
end)
