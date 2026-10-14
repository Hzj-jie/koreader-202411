describe("DjvuDocument", function()
  local CanvasContext
  local DjvuDocument
  local ffiUtil
  local lfs
  local sample_djvu = "spec/front/unit/data/djvu.djvu"

  setup(function()
    require("commonrequire")
    CanvasContext = require("document/canvascontext")
    DjvuDocument = require("document/djvudocument")
    ffiUtil = require("ffi/util")
    lfs = require("libs/libkoreader-lfs")

    CanvasContext:init(require("device"))

    if not lfs.attributes(sample_djvu) then
      sample_djvu = "spec/front/unit/data/djvu3spec.djvu"
    end
  end)

  describe("File Validation", function()
    it("should reject nonexistent or non-DjVu files without AT&TFORM magic", function()
      local ok1, err1 = pcall(function()
        return DjvuDocument:new({ file = "/tmp/nonexistent_" .. ffiUtil.getpid() .. ".djvu" })
      end)
      assert.is_false(ok1)
      assert.is_truthy(string.find(tostring(err1), "Not a valid DjVu file"))

      local invalid_file = "/tmp/test_invalid_magic_" .. ffiUtil.getpid() .. ".djvu"
      local f = assert(io.open(invalid_file, "w"))
      f:write("INVALID_MAGIC_HEADER")
      f:close()

      local ok2, err2 = pcall(function()
        return DjvuDocument:new({ file = invalid_file })
      end)
      assert.is_false(ok2)
      assert.is_truthy(string.find(tostring(err2), "Not a valid DjVu file"))

      os.remove(invalid_file)
    end)
  end)

  describe("Initialization & Document Operations", function()
    it("should initialize document, update color rendering, and query boxes/dimensions", function()
      local doc = DjvuDocument:new({ file = sample_djvu })

      assert.is_true(doc.is_open)
      assert.is_true(doc.info.has_pages)
      assert.is_true(doc.info.configurable)
      assert.are.equal(0, doc.render_mode)

      -- updateColorRendering
      doc:updateColorRendering()

      -- getPageTextBoxes
      local text = doc:getPageTextBoxes(1)
      assert.is_not_nil(text)

      -- getUsedBBox
      local ubbox = doc:getUsedBBox(1)
      assert.is_table(ubbox)
      assert.are.equal(0, ubbox.x0)
      assert.are.equal(0, ubbox.y0)
      assert.is_number(ubbox.x1)
      assert.is_number(ubbox.y1)
      assert.is_true(ubbox.x1 > 0)
      assert.is_true(ubbox.y1 > 0)

      -- getPageBBox
      local pbbox = doc:getPageBBox(1)
      assert.is_table(pbbox)

      -- getPageDimensions
      local dim = doc:getPageDimensions(1, 1, 0)
      assert.is_table(dim)
      assert.is_number(dim.w)
      assert.is_number(dim.h)

      -- hintPage
      assert.has_no_errors(function()
        doc:hintPage(1, 1, 0, 1.0)
      end)

      -- renderPage
      local bb = doc:renderPage(1, { x = 0, y = 0, w = 100, h = 100 }, 1, 0, 1.0)
      assert.is_not_nil(bb)

      -- comparePositions
      local cmp = doc:comparePositions({ page = 1, x = 0, y = 0 }, { page = 2, x = 0, y = 0 })
      assert.are.equal(1, cmp)

      doc._document:close()
      doc.is_open = false
    end)
  end)

  describe("Provider Registration", function()
    it("should register djvu and djv extensions in registry", function()
      local registered = {}
      local mock_registry = {
        addProvider = function(_self, ext, mime, provider, weight)
          table.insert(registered, {
            ext = ext,
            mime = mime,
            provider = provider,
            weight = weight,
          })
        end,
      }

      DjvuDocument:register(mock_registry)
      assert.are.equal(4, #registered)
      assert.are.equal("djvu", registered[1].ext)
      assert.are.equal("image/vnd.djvu", registered[1].mime)
      assert.are.equal("djvu", registered[2].ext)
      assert.are.equal("application/djvu", registered[2].mime)
      assert.are.equal("djvu", registered[3].ext)
      assert.are.equal("image/x-djvu", registered[3].mime)
      assert.are.equal("djv", registered[4].ext)
      assert.are.equal("image/vnd.djvu", registered[4].mime)
    end)
  end)
end)
