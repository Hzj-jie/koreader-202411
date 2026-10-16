local ffi
local mupdf

describe("ffi/mupdf module", function()
  setup(function()
    require("commonrequire")
    ffi = require("ffi")
    mupdf = require("ffi/mupdf")
  end)

  it("opens document and queries page count and dimensions", function()
    local doc = mupdf.openDocument("spec/front/unit/data/2col.pdf")
    assert.is_not_nil(doc)
    local pages = doc:getPages()
    assert.is_number(pages)
    assert.is_true(pages > 0)

    local page = doc:openPage(1)
    assert.is_not_nil(page)
    local dc = { zoom = 1, rotate = 0 }
    local w, h = page:getSize(dc)
    assert.is_number(w)
    assert.is_number(h)
    assert.is_true(w > 0)
    assert.is_true(h > 0)
    page:close()
    doc:close()
  end)

  it("renders image files to blitbuffer", function()
    local bb = mupdf.renderImageFile("resources/koreader.png")
    assert.is_not_nil(bb)
    assert.is_true(bb:getWidth() > 0)
    assert.is_true(bb:getHeight() > 0)
  end)

  it(
    "validates bgr_pixmap rather than pixmap when BGR conversion fails",
    function()
      local orig_bgr = mupdf.bgr
      mupdf.bgr = true

      local _, orig_W = debug.getupvalue(mupdf.renderImage, 1)
      local _, orig_M = debug.getupvalue(mupdf.renderImage, 5)

      local mock_W = setmetatable({
        mupdf_convert_pixmap = function(...)
          return nil
        end,
      }, { __index = orig_W })

      local mock_M = setmetatable({
        fz_default_color_params = ffi.new("int[1]"),
        fz_pixmap_samples = function(ctx, pix)
          if pix == nil or pix == ffi.null then
            error("NULL pixmap passed to fz_pixmap_samples")
          end
          return orig_M.fz_pixmap_samples(ctx, pix)
        end,
        fz_drop_pixmap = function(ctx, pix)
          if pix ~= nil and pix ~= ffi.null then
            return orig_M.fz_drop_pixmap(ctx, pix)
          end
        end,
      }, { __index = orig_M })

      debug.setupvalue(mupdf.renderImage, 1, mock_W)
      debug.setupvalue(mupdf.renderImage, 5, mock_M)

      local ok, err = pcall(function()
        mupdf.renderImageFile("resources/koreader.png")
      end)

      debug.setupvalue(mupdf.renderImage, 1, orig_W)
      debug.setupvalue(mupdf.renderImage, 5, orig_M)
      mupdf.bgr = orig_bgr

      assert.is_false(ok)
      assert.is_not_nil(
        string.match(tostring(err), "could not convert pixmap to BGR")
      )
    end
  )

  it(
    "cleans up pixmap and blitbuffer when page rendering fails in draw_new",
    function()
      local doc = mupdf.openDocument("spec/front/unit/data/2col.pdf")
      local page = doc:openPage(1)
      local dc =
        { zoom = 1, rotate = 0, offset_x = 0, offset_y = 0, gamma = -1 }

      local _, orig_W = debug.getupvalue(mupdf.renderImage, 1)
      local mock_W = setmetatable({
        mupdf_run_page = function(...)
          return nil
        end,
      }, { __index = orig_W })

      local BlitBuffer = require("ffi/blitbuffer")
      local orig_bb_new = BlitBuffer.new
      local bb_freed = false
      BlitBuffer.new = function(...)
        local real_bb = orig_bb_new(...)
        return setmetatable({
          free = function(self)
            bb_freed = true
            return real_bb:free()
          end,
        }, {
          __index = real_bb,
          __newindex = real_bb,
        })
      end

      debug.setupvalue(mupdf.renderImage, 1, mock_W)

      local ok, err = pcall(function()
        page:draw_new(dc, 100, 100, 0, 0)
      end)

      debug.setupvalue(mupdf.renderImage, 1, orig_W)
      BlitBuffer.new = orig_bb_new
      page:close()
      doc:close()

      assert.is_false(ok)
      assert.is_not_nil(string.match(tostring(err), "could not run page"))
      assert.is_true(bb_freed)
    end
  )
end)
