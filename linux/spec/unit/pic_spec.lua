local ffi
local Pic

describe("ffi/pic module", function()
  setup(function()
    require("commonrequire")
    ffi = require("ffi")
    Pic = require("ffi/pic")
  end)

  it("opens GIF document and opens page successfully", function()
    local doc = Pic.openGIFDocument("../koreader/tools/eink_cmap.gif")
    assert.is_not_nil(doc)
    assert.is_true(doc:getPages() > 0)
    local page = doc:openPage(1)
    assert.is_not_nil(page)
    assert.is_not_nil(page.image_bb)
    assert.is_true(page.width > 0)
    assert.is_true(page.height > 0)
    page:close()
    doc:close()
  end)

  it("fails cleanly when opening page on GIF with 0 images", function()
    local doc = Pic.openGIFDocument("../koreader/tools/eink_cmap.gif")
    local saved_count = doc.giffile.ImageCount
    doc.giffile.ImageCount = 0

    local ok, err = pcall(function()
      doc:openPage(1)
    end)

    doc.giffile.ImageCount = saved_count
    doc:close()

    assert.is_false(ok)
    assert.is_not_nil(string.match(tostring(err), "GIF has no images"))
  end)
end)
