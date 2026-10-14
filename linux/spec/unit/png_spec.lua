local ffi
local Png

describe("ffi/png module", function()
  setup(function()
    require("commonrequire")
    ffi = require("ffi")
    Png = require("ffi/png")
  end)

  it("decodes valid PNG file from disk", function()
    local ok, img = Png.decodeFromFile("../koreader/resources/koreader.png", 3)
    assert.is_true(ok)
    assert.is_table(img)
    assert.is_not_nil(img.data)
    assert.is_true(img.width > 0)
    assert.is_true(img.height > 0)
    assert.are.equal(3, img.ncomp)
    ffi.C.free(img.data)
  end)

  it("rejects invalid color components in encodeToFile", function()
    local ok, err = Png.encodeToFile("/tmp/dummy.png", nil, 10, 10, 99)
    assert.is_false(ok)
    assert.are.equal("passed an invalid number of color components", err)
  end)

  it(
    "returns Lua string rather than raw cdata for lodepng error text in encodeToFile",
    function()
      local dummy_data = ffi.new("unsigned char[100]")
      -- Attempt to encode to an invalid directory path that cannot be written
      local ok, err_msg = Png.encodeToFile(
        "/nonexistent_dir_cannot_create/test.png",
        dummy_data,
        5,
        5,
        3
      )
      assert.is_false(ok)
      assert.is_not_nil(err_msg)

      -- Error message must be a Lua string
      assert.are.equal("string", type(err_msg))
    end
  )

  it("cleans up state on early exit in decodeFromFile", function()
    local cleaned = false
    local up_idx = 1
    local name, orig_lodepng = debug.getupvalue(Png.decodeFromFile, up_idx)
    if name ~= "lodepng" then
      up_idx = 2
      orig_lodepng = select(2, debug.getupvalue(Png.decodeFromFile, up_idx))
    end

    local mock_lodepng = setmetatable({
      lodepng_state_cleanup = function(state)
        cleaned = true
        return orig_lodepng.lodepng_state_cleanup(state)
      end,
    }, { __index = orig_lodepng })

    debug.setupvalue(Png.decodeFromFile, up_idx, mock_lodepng)

    local ok, _ = Png.decodeFromFile("../koreader/resources/koreader.png", 99)
    debug.setupvalue(Png.decodeFromFile, up_idx, orig_lodepng)

    assert.is_false(ok)
    assert.is_true(cleaned)
  end)
end)
