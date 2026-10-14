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
end)
