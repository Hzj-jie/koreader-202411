local ffi
local Pic

describe("ffi/pic module", function()
  setup(function()
    require("commonrequire")
    ffi = require("ffi")
    Pic = require("ffi/pic")
  end)

  it("opens GIF document and opens page successfully", function()
    local doc = Pic.openGIFDocument("tools/eink_cmap.gif")
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

  it(
    "fails cleanly when opening page on GIF with no valid color map",
    function()
      local doc = Pic.openGIFDocument("tools/eink_cmap.gif")
      local saved_s_colormap = doc.giffile.SColorMap
      local saved_desc_colormap = doc.giffile.SavedImages[0].ImageDesc.ColorMap
      doc.giffile.SColorMap = nil
      doc.giffile.SavedImages[0].ImageDesc.ColorMap = nil

      local ok, err = pcall(function()
        doc:openPage(1)
      end)

      doc.giffile.SColorMap = saved_s_colormap
      doc.giffile.SavedImages[0].ImageDesc.ColorMap = saved_desc_colormap
      doc:close()

      assert.is_false(ok)
      assert.is_not_nil(
        string.match(tostring(err), "GIF has no valid color map")
      )
    end
  )
end)
