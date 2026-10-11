describe("PDF document module", function()
  local DocumentRegistry

  setup(function()
    require("commonrequire")
    DocumentRegistry = require("document/documentregistry")
  end)

  local doc
  it("should open document", function()
    local sample_pdf = "spec/front/unit/data/tall.pdf"
    doc = DocumentRegistry:openDocument(sample_pdf)
    assert.truthy(doc)
  end)
  it("should get page dimensions", function()
    local dimen = doc:getPageDimensions(1, 1, 0)
    assert.are.same(dimen.w, 567)
    assert.are.same(dimen.h, 1418)
  end)
  it("should get cover image", function()
    local image = doc:getCoverPageImage()
    assert.truthy(image)
    assert.are.same(320, image:getWidth())
    assert.are.same(800, image:getHeight())
  end)
  local pos0 = { page = 1, x = 0, y = 20 }
  local pos1 = { page = 1, x = 300, y = 120 }
  local pboxes = {
    { x = 26, y = 42, w = 240, h = 22 },
    { x = 48, y = 82, w = 185, h = 22 },
  }
  it("should clip page rect to PNG file", function()
    doc:clipPagePNGFile(pos0, pos1, nil, nil, "/tmp/clip0.png")
    doc:clipPagePNGFile(pos0, pos1, pboxes, "lighten", "/tmp/clip1.png")
  end)
  it("should clip page rect to PNG string", function()
    local clip0 = doc:clipPagePNGString(pos0, pos1, nil, nil)
    assert.truthy(clip0)
    local clip1 = doc:clipPagePNGString(pos0, pos1, pboxes, "lighten")
    assert.truthy(clip1)
  end)
  it(
    "should get used bbox dimensions without mutating cached bbox and respecting rotation",
    function()
      doc.configurable.trim_page = 0
      -- Set cached bbox with negative x0/y0
      doc.bbox[1] = { x0 = -10, y0 = -20, x1 = 100, y1 = 200 }
      local dimen_rot0 = doc:getUsedBBoxDimensions(1, 1, 0)
      assert.are.same(100, dimen_rot0.w)
      assert.are.same(200, dimen_rot0.h)
      -- Ensure doc.bbox[1] was not mutated in-place
      assert.are.same(-10, doc.bbox[1].x0)
      assert.are.same(-20, doc.bbox[1].y0)

      -- Test rotation 90
      local dimen_rot90 = doc:getUsedBBoxDimensions(1, 1, 90)
      assert.are.same(200, dimen_rot90.w)
      assert.are.same(100, dimen_rot90.h)

      -- Test corrupted bbox fallback
      doc.bbox[1] = { x0 = 100, y0 = 200, x1 = 50, y1 = 100 }
      local dimen_fallback = doc:getUsedBBoxDimensions(1, 1, 90)
      -- For page 1, native dimen was 567 x 1418, so rotation 90 should be 1418 x 567
      assert.are.same(1418, dimen_fallback.w)
      assert.are.same(567, dimen_fallback.h)
    end
  )
  it("should close document", function()
    doc:close()
  end)
end)

describe("EPUB document module", function()
  local DocumentRegistry, cre

  setup(function()
    require("commonrequire")
    cre = require("libs/libkoreader-cre")
    DocumentRegistry = require("document/documentregistry")
  end)

  local doc
  it("should open document", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    doc = DocumentRegistry:openDocument(sample_epub)
    assert.truthy(doc)
  end)
  it("should get cover image", function()
    local image = doc:getCoverPageImage()
    assert.truthy(image)
    assert.are.same(image:getWidth(), 442)
    assert.are.same(image:getHeight(), 616)
  end)
  it("should register droid sans fallback", function()
    local face_list = cre.getFontFaces()
    local has_droid_sans = false
    for i, v in ipairs(face_list) do
      if v == "Droid Sans Mono" then
        has_droid_sans = true
        break
      end
    end
    assert.is_true(has_droid_sans)
    assert.is_true(#face_list >= 10)
  end)
  it("should close document", function()
    doc:close()
  end)
end)
