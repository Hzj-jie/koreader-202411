describe("PdfDocument", function()
  local CanvasContext
  local DocCache
  local DocSettings
  local DocumentRegistry
  local PdfDocument
  local ffiUtil
  local sample_pdf = "spec/front/unit/data/2col.pdf"

  setup(function()
    require("commonrequire")
    CanvasContext = require("document/canvascontext")
    DocCache = require("document/doccache")
    DocSettings = require("docsettings")
    DocumentRegistry = require("document/documentregistry")
    PdfDocument = require("document/pdfdocument")
    ffiUtil = require("ffi/util")

    CanvasContext:init(require("device"))
  end)

  after_each(function()
    for file, entry in pairs(DocumentRegistry.registry) do
      if entry.doc and entry.doc.is_open then
        pcall(entry.doc.close, entry.doc)
      end
      DocumentRegistry.registry[file] = nil
    end
  end)

  describe("Initialization & Layout", function()
    it("should initialize document, update color rendering, and layout document", function()
      local doc = PdfDocument:new({ file = sample_pdf })
      doc:init()
      assert.is_true(doc.is_open)
      assert.is_true(doc.info.has_pages)
      assert.is_boolean(doc.is_reflowable)
      assert.is_number(doc.reflowable_font_size)

      -- updateColorRendering
      doc:updateColorRendering()

      -- layoutDocument with font_size
      doc:layoutDocument(24)
      assert.are.equal(24, doc.reflowable_font_size)

      doc._document:close()
      doc.is_open = false
    end)

    it("should convert kopt font size to reflowable font size", function()
      local doc = PdfDocument:new({ file = sample_pdf })
      doc:init()

      -- Explicit argument
      assert.are.equal(33, doc:convertKoptToReflowableFontSize(1.5))

      -- From DocSettings sidecar
      local tmp_file = "/tmp/test_kopt_" .. ffiUtil.getpid() .. ".pdf"
      local src = assert(io.open(sample_pdf, "rb"))
      local content = src:read("*all")
      src:close()
      local dst = assert(io.open(tmp_file, "wb"))
      dst:write(content)
      dst:close()

      local tmp_doc = PdfDocument:new({ file = tmp_file })
      tmp_doc:init()

      local ds = DocSettings:open(tmp_file)
      ds:save("kopt_font_size", 2.0)
      ds:flush()
      assert.are.equal(44, tmp_doc:convertKoptToReflowableFontSize())

      ds:purge()
      tmp_doc._document:close()
      tmp_doc.is_open = false
      os.remove(tmp_file)

      -- Fallback when no settings
      local saved_read = G_reader_settings.read
      local saved_def = G_defaults.read
      G_reader_settings.read = function(_self, key)
        if key == "kopt_font_size" then
          return 1.0
        end
      end
      assert.are.equal(22, doc:convertKoptToReflowableFontSize())

      G_reader_settings.read = function()
        return nil
      end
      G_defaults.read = function(_self, key)
        if key == "DKOPTREADER_CONFIG_FONT_SIZE" then
          return 0.5
        end
      end
      assert.are.equal(11, doc:convertKoptToReflowableFontSize())

      G_defaults.read = function()
        return nil
      end
      assert.are.equal(22, doc:convertKoptToReflowableFontSize())

      G_reader_settings.read = saved_read
      G_defaults.read = saved_def

      doc._document:close()
      doc.is_open = false
    end)
  end)

  describe("Page Boxes, Bounding Boxes, and Links", function()
    it("should get page text boxes with caching", function()
      local doc = PdfDocument:new({ file = sample_pdf })
      doc:init()

      DocCache:clear()
      local text1 = doc:getPageTextBoxes(1)
      assert.is_table(text1)

      -- Second call hits cache
      local text2 = doc:getPageTextBoxes(1)
      assert.are.equal(text1, text2)

      doc._document:close()
      doc.is_open = false
    end)

    it("should get used bbox with coordinate clamping and caching", function()
      local doc = PdfDocument:new({ file = sample_pdf })
      doc:init()

      DocCache:clear()
      local ubbox1 = doc:getUsedBBox(1)
      assert.is_table(ubbox1)
      assert.is_number(ubbox1.x0)
      assert.is_number(ubbox1.y0)
      assert.is_number(ubbox1.x1)
      assert.is_number(ubbox1.y1)
      assert.is_true(ubbox1.x0 >= 0)
      assert.is_true(ubbox1.y0 >= 0)

      -- Second call hits cache
      local ubbox2 = doc:getUsedBBox(1)
      assert.are.equal(ubbox1, ubbox2)

      doc._document:close()
      doc.is_open = false
    end)

    it("should get page links with caching", function()
      local doc = PdfDocument:new({ file = sample_pdf })
      doc:init()

      DocCache:clear()
      local links1 = doc:getPageLinks(1)
      assert.is_table(links1)

      -- Second call hits cache
      local links2 = doc:getPageLinks(1)
      assert.are.equal(links1, links2)

      doc._document:close()
      doc.is_open = false
    end)
  end)

  describe("Writable Check and Highlights", function()
    it("should check if file is writable and cache status", function()
      local doc = PdfDocument:new({ file = sample_pdf })
      doc.file = "test.epub"
      doc.is_writable = nil
      assert.is_nil(doc:_checkIfWritable())

      local tmp_pdf = "/tmp/test_writable_" .. ffiUtil.getpid() .. ".pdf"
      local src = assert(io.open(sample_pdf, "rb"))
      local content = src:read("*all")
      src:close()
      local dst = assert(io.open(tmp_pdf, "wb"))
      dst:write(content)
      dst:close()

      doc.file = tmp_pdf
      doc.is_writable = nil
      assert.is_true(doc:_checkIfWritable())
      -- Check cached value
      assert.is_true(doc.is_writable)
      assert.is_true(doc:_checkIfWritable())

      os.remove(tmp_pdf)
    end)

    it("should save, update, and delete highlights on writable PDF and write on close", function()
      local tmp_pdf = "/tmp/test_hl_" .. ffiUtil.getpid() .. ".pdf"
      local src = assert(io.open(sample_pdf, "rb"))
      local content = src:read("*all")
      src:close()
      local dst = assert(io.open(tmp_pdf, "wb"))
      dst:write(content)
      dst:close()

      local doc = DocumentRegistry:openDocument(tmp_pdf, PdfDocument)
      assert.is_not_nil(doc)
      assert.are.equal(1, DocumentRegistry:getReferenceCount(tmp_pdf))

      -- saveHighlight with lighten drawer
      local item_lighten = {
        pboxes = { { x = 72, y = 100, w = 200, h = 12 } },
        drawer = "lighten",
        color = "yellow",
      }
      doc:saveHighlight(1, item_lighten)
      assert.is_true(doc.is_edited)
      assert.is_table(item_lighten.pboxes)

      -- saveHighlight with underscore drawer
      local item_underline = {
        pboxes = { { x = 72, y = 150, w = 150, h = 12 } },
        drawer = "underscore",
      }
      doc:saveHighlight(1, item_underline)
      assert.is_true(doc.is_edited)

      -- saveHighlight with strikeout drawer
      local item_strikeout = {
        pboxes = { { x = 72, y = 200, w = 180, h = 12 } },
        drawer = "strikeout",
      }
      doc:saveHighlight(1, item_strikeout)
      assert.is_true(doc.is_edited)

      -- updateHighlightContents
      doc:updateHighlightContents(1, item_lighten, "Updated note text")
      assert.is_true(doc.is_edited)

      -- deleteHighlight
      doc:deleteHighlight(1, item_strikeout)
      assert.is_true(doc.is_edited)

      -- close writes document when refcount == 1
      assert.are.equal(1, DocumentRegistry:getReferenceCount(tmp_pdf))
      doc:close()
      assert.is_nil(DocumentRegistry:getReferenceCount(tmp_pdf))

      os.remove(tmp_pdf)
    end)
  end)

  describe("Provider Registration", function()
    it("should register document and image providers in registry", function()
      local registered = {}
      local mock_registry = {
        addProvider = function(_self, ext, mime, provider, weight)
          table.insert(registered, { ext = ext, mime = mime, provider = provider, weight = weight })
        end,
      }
      PdfDocument:register(mock_registry)
      assert.is_true(#registered > 10)

      local found_pdf = false
      local found_png = false
      for _, entry in ipairs(registered) do
        if entry.ext == "pdf" then
          found_pdf = true
        end
        if entry.ext == "png" then
          found_png = true
        end
      end
      assert.is_true(found_pdf)
      assert.is_true(found_png)
    end)
  end)
end)
