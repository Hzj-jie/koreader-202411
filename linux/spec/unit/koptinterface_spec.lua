describe("Koptinterface module", function()
  local DocCache, DocumentRegistry, Koptinterface
  local tall_pdf = "spec/front/unit/data/tall.pdf"
  local complex_pdf = "spec/front/unit/data/sample.pdf"
  local paper_pdf = "spec/front/unit/data/paper.pdf"
  local doc, complex_doc, paper_doc

  setup(function()
    require("commonrequire")
    DocCache = require("document/doccache")
    DocumentRegistry = require("document/documentregistry")
    Koptinterface = require("document/koptinterface")

    doc = DocumentRegistry:openDocument(tall_pdf)
    complex_doc = DocumentRegistry:openDocument(complex_pdf)
    paper_doc = DocumentRegistry:openDocument(paper_pdf)
  end)

  teardown(function()
    doc:close()
    complex_doc:close()
    paper_doc:close()
  end)

  before_each(function()
    doc.configurable.text_wrap = 0
    complex_doc.configurable.text_wrap = 0
    paper_doc.configurable.text_wrap = 0
    doc.bbox = {}
    complex_doc.bbox = {}
    paper_doc.bbox = {}
    DocCache:clear()
  end)

  it("should get auto bbox", function()
    local auto_bbox = Koptinterface:getAutoBBox(doc, 1)
    assert.is.near(22, auto_bbox.x0, 0.5)
    assert.is.near(38, auto_bbox.y0, 0.5)
    assert.is.near(548, auto_bbox.x1, 0.5)
    assert.is.near(1387, auto_bbox.y1, 0.5)
  end)

  it("should get semi auto bbox", function()
    local semiauto_bbox = Koptinterface:getSemiAutoBBox(doc, 1)
    local page_bbox = doc:getPageBBox(1)
    doc.bbox[1] = {
      x0 = page_bbox.x0 + 10,
      y0 = page_bbox.y0 + 10,
      x1 = page_bbox.x1 - 10,
      y1 = page_bbox.y1 - 10,
    }

    local bbox = Koptinterface:getSemiAutoBBox(doc, 1)
    assert.is_not.near(semiauto_bbox.x0, bbox.x0, 0.5)
    assert.is_not.near(semiauto_bbox.y0, bbox.y0, 0.5)
    assert.is_not.near(semiauto_bbox.x1, bbox.x1, 0.5)
    assert.is_not.near(semiauto_bbox.y1, bbox.y1, 0.5)
  end)

  it("should render optimized page to de-watermark", function()
    local page_dimen = doc:getPageDimensions(1, 1.0, 0)
    local tile = Koptinterface:renderOptimizedPage(doc, 1, nil, 1.0, 0, 0)
    assert.truthy(tile)
    assert.are.same(page_dimen, tile.excerpt)
  end)

  it("should reflow page in foreground", function()
    doc.configurable.text_wrap = 1
    local kc = Koptinterface:getCachedContext(doc, 1)
    assert.truthy(kc)
  end)

  it("should hint reflowed page in background", function()
    doc.configurable.text_wrap = 1
    Koptinterface:hintReflowedPage(doc, 1, 1.0, 0, 1.0, 0)
    -- and wait for reflowing to complete
    local kc = Koptinterface:getCachedContext(doc, 1)
    assert.truthy(kc)
  end)

  it("should get native text boxes", function()
    Koptinterface:getCachedContext(doc, 1)
    local boxes = Koptinterface:getNativeTextBoxes(doc, 1)
    local lines_in_native_page = #boxes
    assert.truthy(lines_in_native_page == 60)
  end)

  it("should get native text boxes from scratch", function()
    Koptinterface:getCachedContext(doc, 1)
    local boxes = Koptinterface:getNativeTextBoxesFromScratch(doc, 1)
    local lines_in_native_page = #boxes
    assert.truthy(lines_in_native_page == 60)
  end)

  it("should get reflow text boxes", function()
    doc.configurable.text_wrap = 1
    Koptinterface:getCachedContext(doc, 1)
    local boxes = Koptinterface:getReflowedTextBoxes(doc, 1)
    local lines_in_reflowed_page = #boxes
    assert.truthy(lines_in_reflowed_page > 60)
  end)

  it("should get reflow text boxes from scratch", function()
    doc.configurable.text_wrap = 1
    Koptinterface:getCachedContext(doc, 1)
    local boxes = Koptinterface:getReflowedTextBoxesFromScratch(doc, 1)
    local lines_in_reflowed_page = #boxes
    assert.truthy(lines_in_reflowed_page > 60)
  end)

  it("should get page block of a two-column page", function()
    for i = 0.3, 0.6, 0.3 do
      for j = 0.3, 0.6, 0.3 do
        local block = Koptinterface:getPageBlock(complex_doc, 34, i, j)
        assert.truthy(block.x1 - block.x0 < 0.5)
      end
    end
  end)

  it("should get word from native position", function()
    local word_boxes = Koptinterface:getWordFromPosition(complex_doc, {
      page = 19,
      x = 400,
      y = 530,
    })
    assert.is.same("previous", word_boxes.word)
  end)

  it("should get word from reflow position", function()
    complex_doc.configurable.text_wrap = 1
    Koptinterface:getCachedContext(complex_doc, 19)
    local word_boxes = Koptinterface:getWordFromPosition(complex_doc, {
      page = 19,
      x = 320,
      y = 730,
    })
    assert.is.same("time,", word_boxes.word)
  end)

  it("should get link from native position", function()
    local link = Koptinterface:getLinkFromPosition(paper_doc, 1, {
      x = 140,
      y = 560,
    })
    assert.truthy(link)
    assert.is.same(20, link.page)
    require("dbg"):v("link", link)
  end)

  it("should get link from reflow position", function()
    paper_doc.configurable.text_wrap = 1
    local link = Koptinterface:getLinkFromPosition(paper_doc, 1, {
      x = 455,
      y = 1105,
    })
    assert.truthy(link)
    assert.is.same(20, link.page)
  end)

  it("should set default configurable options", function()
    local conf = {}
    Koptinterface:setDefaultConfigurable(conf)
    assert.is_not_nil(conf.trim_page)
    assert.is_not_nil(conf.text_wrap)
    assert.is_not_nil(conf.font_size)
  end)

  it("should get manual page bbox when trim_page is 0", function()
    doc.configurable.text_wrap = 0
    doc.configurable.trim_page = 0
    local bbox = Koptinterface:getPageBBox(doc, 1)
    assert.is_not_nil(bbox)
    assert.is_not_nil(bbox.x0)
    assert.is_not_nil(bbox.y0)
  end)

  it("should get page dimensions in native and reflow mode", function()
    doc.configurable.text_wrap = 0
    local dim1 = Koptinterface:getPageDimensions(doc, 1, 1.0, 0)
    assert.is_not_nil(dim1.w)
    assert.is_not_nil(dim1.h)

    doc.configurable.text_wrap = 1
    local dim2 = Koptinterface:getPageDimensions(doc, 1, 1.0, 0)
    assert.is_not_nil(dim2.w)
    assert.is_not_nil(dim2.h)
  end)

  it("should get cover page image", function()
    local img = Koptinterface:getCoverPageImage(doc)
    assert.is_not_nil(img)
  end)

  it("should hint page in various modes", function()
    doc.configurable.text_wrap = 0
    doc.configurable.page_opt = 0
    doc.configurable.auto_straighten = 0
    Koptinterface:hintPage(doc, 1, 1.0, 0, 1.0)

    doc.configurable.page_opt = 1
    Koptinterface:hintPage(doc, 1, 1.0, 0, 1.0)

    doc.configurable.text_wrap = 1
    Koptinterface:hintPage(doc, 1, 1.0, 0, 1.0)
  end)

  it("should render page in fallback, optimized, and reflow modes", function()
    doc.configurable.text_wrap = 0
    doc.configurable.page_opt = 0
    doc.configurable.auto_straighten = 0
    local tile1 = Koptinterface:renderPage(doc, 1, nil, 1.0, 0, 1.0)
    assert.is_not_nil(tile1)

    doc.configurable.page_opt = 1
    local tile2 = Koptinterface:renderPage(doc, 1, nil, 1.0, 0, 1.0)
    assert.is_not_nil(tile2)

    doc.configurable.text_wrap = 1
    local tile3 = Koptinterface:renderPage(doc, 1, nil, 1.0, 0, 1.0)
    assert.is_not_nil(tile3)
  end)

  it("should draw page to blitbuffer", function()
    local Blitbuffer = require("ffi/blitbuffer")
    local Geom = require("ui/geometry")
    local canvas_size = require("document/canvascontext"):getSize()
    local target = Blitbuffer.new(canvas_size.w, canvas_size.h)
    local rect = Geom:new({ x = 0, y = 0, w = canvas_size.w, h = canvas_size.h })

    doc.configurable.text_wrap = 0
    doc.configurable.page_opt = 0
    doc.configurable.auto_straighten = 0
    Koptinterface:drawPage(doc, target, 0, 0, rect, 1, 1.0, 0, 1.0)

    doc.configurable.text_wrap = 1
    Koptinterface:drawPage(doc, target, 0, 0, rect, 1, 1.0, 0, 1.0)
  end)

  it("should get text boxes with or without forced OCR", function()
    paper_doc.configurable.text_wrap = 0
    paper_doc.configurable.forced_ocr = 0
    local boxes1 = Koptinterface:getTextBoxes(paper_doc, 1)
    assert.is_not_nil(boxes1)

    paper_doc.configurable.forced_ocr = 1
    local boxes2 = Koptinterface:getTextBoxes(paper_doc, 1)
    assert.is_not_nil(boxes2)
  end)

  it("should get panel from page gesture", function()
    local ges = {
      pos = { x = 100, y = 100 },
      distance = { x = 50, y = 50 },
    }
    local panel = Koptinterface:getPanelFromPage(doc, 1, ges)
    -- panel can be nil or box table depending on k2pdfopt panel detection
    assert.is_true(panel == nil or type(panel) == "table")
  end)

  it("should clip page PNG string", function()
    local pos0 = { page = 1, x = 10, y = 10, zoom = 1.0 }
    local pos1 = { page = 1, x = 100, y = 100, zoom = 1.0 }
    local png = Koptinterface:clipPagePNGString(doc, pos0, pos1, nil, nil)
    assert.is_not_nil(png)
    assert.is_true(#png > 0)
  end)

  it("should compare positions correctly", function()
    local pos_page1 = { page = 1, x = 100, y = 100 }
    local pos_page2 = { page = 2, x = 100, y = 100 }
    assert.are.equal(1, Koptinterface:comparePositions(complex_doc, pos_page1, pos_page2))
    assert.are.equal(-1, Koptinterface:comparePositions(complex_doc, pos_page2, pos_page1))

    local pos_top = { page = 19, x = 400, y = 400 }
    local pos_bottom = { page = 19, x = 400, y = 530 }
    assert.are.equal(1, Koptinterface:comparePositions(complex_doc, pos_top, pos_bottom))

    assert.are.equal(0, Koptinterface:comparePositions(complex_doc, pos_bottom, pos_bottom))
  end)

  it("should get text from native and reflow positions", function()
    complex_doc.configurable.text_wrap = 0
    local pos0 = { page = 19, x = 400, y = 530 }
    local pos1 = { page = 19, x = 450, y = 530 }
    local res = Koptinterface:getTextFromPositions(complex_doc, pos0, pos1)
    assert.is_not_nil(res)
    assert.is_not_nil(res.text)

    complex_doc.configurable.text_wrap = 1
    Koptinterface:getCachedContext(complex_doc, 19)
    local rpos0 = { page = 19, x = 320, y = 730 }
    local rpos1 = { page = 19, x = 360, y = 730 }
    local rres = Koptinterface:getTextFromPositions(complex_doc, rpos0, rpos1)
    assert.is_not_nil(rres)
  end)

  it("should get page boxes from positions", function()
    complex_doc.configurable.text_wrap = 0
    local ppos0 = { page = 19, x = 400, y = 530 }
    local ppos1 = { page = 19, x = 450, y = 530 }
    local boxes = Koptinterface:getPageBoxesFromPositions(complex_doc, 19, ppos0, ppos1)
    assert.is_not_nil(boxes)

    complex_doc.configurable.text_wrap = 1
    local rboxes = Koptinterface:getPageBoxesFromPositions(complex_doc, 19, ppos0, ppos1)
    assert.is_not_nil(rboxes)
  end)

  it("should transform native rect to page rect", function()
    local rect = { x = 10, y = 10, w = 100, h = 50 }
    complex_doc.configurable.text_wrap = 0
    local r1 = Koptinterface:nativeToPageRectTransform(complex_doc, 1, rect)
    assert.are.same(rect, r1)

    complex_doc.configurable.text_wrap = 1
    Koptinterface:getCachedContext(complex_doc, 19)
    local rect19 = { x = 400, y = 530, w = 50, h = 20 }
    local r2 = Koptinterface:nativeToPageRectTransform(complex_doc, 19, rect19)
    assert.is_not_nil(r2)
  end)

  it("should find text in document", function()
    local matches = Koptinterface:findText(paper_doc, "sample", 0, 0, true, 1)
    assert.is_not_nil(matches)
    assert.is_true(#matches > 0)
    assert.is_not_nil(matches.page)

    local bmatches = Koptinterface:findText(paper_doc, "sample", -1, 1, true, 1)
    assert.is_not_nil(bmatches)
    assert.is_true(#bmatches > 0)
  end)

  it("should find all text with context", function()
    local res = Koptinterface:findAllText(paper_doc, "sample", true, 2, 5)
    assert.is_not_nil(res)
    assert.is_true(#res > 0)
    assert.is_not_nil(res[1].matched_text)
  end)

  it("should get selected word context", function()
    complex_doc.configurable.text_wrap = 0
    local pos = { page = 19, x = 400, y = 530 }
    local word_info = Koptinterface:getWordFromPosition(complex_doc, pos)
    assert.is_not_nil(word_info)
    assert.is_not_nil(word_info.word)

    local prev_text, next_text = Koptinterface:getSelectedWordContext(word_info.word, 2, pos)
    assert.is_not_nil(prev_text)
    assert.is_not_nil(next_text)
  end)

  it("should handle edge cases in getWordFromBoxes and getTextFromBoxes", function()
    assert.are.same({}, Koptinterface:getWordFromBoxes(nil, { x = 0, y = 0 }))
    assert.are.same({}, Koptinterface:getWordFromBoxes({}, { x = 0, y = 0 }))

    assert.are.same({}, Koptinterface:getTextFromBoxes(nil, { x = 0, y = 0 }, { x = 1, y = 1 }))
    assert.are.same({}, Koptinterface:getTextFromBoxes({}, { x = 0, y = 0 }, { x = 1, y = 1 }))

    local sample_boxes = {
      {
        y0 = 10, y1 = 20, x0 = 10, x1 = 100,
        { word = "hello-", x0 = 10, y0 = 10, x1 = 50, y1 = 20 },
      },
      {
        y0 = 25, y1 = 35, x0 = 10, x1 = 100,
        { word = "world", x0 = 10, y0 = 25, x1 = 50, y1 = 35 },
      },
    }
    local res = Koptinterface:getTextFromBoxes(sample_boxes, { x = 15, y = 15 }, { x = 15, y = 30 })
    assert.are.equal("helloworld", res.text)
  end)

  it("should handle OCR word extraction", function()
    paper_doc.configurable.text_wrap = 0
    local wbox = { sbox = { x = 10, y = 10, w = 50, h = 20 } }
    Koptinterface:getOCRWord(paper_doc, 1, wbox)

    paper_doc.configurable.text_wrap = 1
    Koptinterface:getOCRWord(paper_doc, 1, wbox)

    Koptinterface:getOCRText(paper_doc, 1, nil)
  end)
end)
