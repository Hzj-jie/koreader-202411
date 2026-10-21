local ZipWriter
local bit

describe("ZipWriter", function()
  setup(function()
    require("commonrequire")
    ZipWriter = require("ffi/zipwriter")
    bit = require("bit")
  end)

  it("should instantiate a new ZipWriter", function()
    local zw = ZipWriter:new()
    assert.is_table(zw)
  end)

  it("should create and close a zip file with content", function()
    local test_zip = "test_output.zip"
    os.remove(test_zip)

    local zw = ZipWriter:new()
    local ok = zw:open(test_zip)
    assert.is_true(ok)

    zw:add("hello.txt", "Hello World!", true)
    zw:add(
      "compressed.txt",
      "This is compressed content repeat repeat repeat",
      false
    )
    assert.is_true(zw:close())

    local f = io.open(test_zip, "rb")
    assert.is_not_nil(f)
    local data = f:read("*a")
    f:close()
    os.remove(test_zip)

    assert.is_true(#data > 0)
    -- Check local file header signature PK\3\4
    assert.are.equal("PK\3\4", data:sub(1, 4))
  end)

  it(
    "encodes FAT timestamp seconds using standard dos time conversion",
    function()
      local orig_date = os.date
      os.date = function()
        return {
          year = 2026,
          month = 10,
          day = 10,
          hour = 12,
          min = 0,
          sec = 58,
        }
      end

      local test_zip = "test_fat_sec.zip"
      os.remove(test_zip)
      local zw = ZipWriter:new()
      zw:open(test_zip)
      zw:close()
      os.remove(test_zip)
      os.date = orig_date

      local fat_seconds = bit.band(zw.started_time, 0x1F)
      assert.are.equal(30, fat_seconds)
    end
  )
end)
