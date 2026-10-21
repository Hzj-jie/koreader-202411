local ffi
local zstd

describe("ffi/zstd module", function()
  setup(function()
    require("commonrequire")
    ffi = require("ffi")
    zstd = require("ffi/zstd")
  end)

  it("compresses and decompresses data round-trip", function()
    local original = "Hello Zstandard compression world! 1234567890"
    local cbuff, clen = zstd.zstd_compress(original, #original)
    assert.is_not_nil(cbuff)
    assert.is_true(clen > 0)

    local dbuff, dlen = zstd.zstd_uncompress(cbuff, clen)
    assert.is_not_nil(dbuff)
    assert.are.equal(#original, tonumber(dlen))
    assert.are.equal(original, ffi.string(dbuff, dlen))

    ffi.C.free(cbuff)
    ffi.C.free(dbuff)
  end)

  it("decompresses data using reusable decompression context", function()
    local original = "Testing reusable decompression context in ZSTD"
    local cbuff, clen = zstd.zstd_compress(original, #original)
    local dbuff, dlen = zstd.zstd_uncompress_ctx(cbuff, clen)

    assert.is_not_nil(dbuff)
    assert.are.equal(#original, tonumber(dlen))
    assert.are.equal(original, ffi.string(dbuff, dlen))

    ffi.C.free(cbuff)
    ffi.C.free(dbuff)
  end)

  it(
    "validates frame content size before attempting allocation on invalid data",
    function()
      local bad_data = "not a valid zstd stream at all"
      local ok, err = pcall(function()
        zstd.zstd_uncompress(bad_data, #bad_data)
      end)
      assert.is_false(ok)

      -- When passed invalid bytes, ZSTD_getFrameContentSize returns ZSTD_CONTENTSIZE_ERROR ((uint64_t)-2).
      -- This sentinel should be caught before attempting allocation.
      assert.is_nil(
        string.match(
          tostring(err),
          "Failed to allocate ZSTD decompression buffer"
        )
      )
    end
  )
end)
