--[[--
MuPDF API

This is a FFI wrapper for what was a Lua-based API in the past
Some kind of C wrapper is needed for muPDF since muPDF uses
a setjmp/longjmp based approach to error/exception handling.
That's one of the very few things we can't deal with using
LuaJIT's FFI.

@module ffi.mupdf
--]]

local ffi = require("ffi")
require("ffi/mupdf_h")
require("ffi/posix_h") -- for malloc

local BlitBuffer = require("ffi/blitbuffer")

local W = ffi.loadlib("wrap-mupdf")
local M = W

--- @fixme: Don't make cache_size too low, at least not until we bump MµPDF,
---         as there's a pernicious issue that corrupts its store cache on overcommit on old versions.
---         c.f., https://github.com/koreader/koreader/issues/7627
---         (FZ_STORE_DEFAULT is 256MB, we used to set it to 8MB).
---         And when we bump MµPDF, it'll likely have *more* stuff to store in there,
--          so, don't make that too low, period ;).
--          NOTE: Revisit when we bump MµPDF by doing a few tests with the tracing memory allocators,
--                as even 32MB is likely to be too conservative.
local mupdf = {
  debug_memory = false,
  cache_size = 32 * 1024 * 1024,
}
-- this cannot get adapted by the cdecl file because it is a
-- string constant. Must match the actual mupdf API:
local FZ_VERSION = "1.24.10"

local document_mt = { __index = {} }
local page_mt = { __index = {} }

mupdf.debug = function() --[[ no debugging by default ]]
end

local save_ctx = nil
-- provides an fz_context for mupdf
local function context()
  if save_ctx ~= nil then
    return save_ctx
  end

  local ctx = M.fz_new_context_imp(
    mupdf.debug_memory and W.mupdf_get_my_alloc_context() or nil,
    nil,
    mupdf.cache_size,
    FZ_VERSION
  )

  if ctx == nil then
    error("cannot create fz_context for MuPDF")
  end

  -- ctx is a cdata<fz_context *>, attach a finalizer to it to release ressources on garbage collection
  ctx = ffi.gc(ctx, mupdf.fz_context_gc)

  M.fz_install_external_font_funcs(ctx)
  M.fz_register_document_handlers(ctx)

  save_ctx = ctx
  return ctx
end

-- a wrapper for mupdf exception error messages
local function merror(message)
  if context() ~= nil then
    error(
      string.format(
        "%s: %s (%d)",
        message,
        ffi.string(W.mupdf_error_message(context())),
        W.mupdf_error_code(context())
      )
    )
  else
    error(message)
  end
end

--
function mupdf.fz_context_gc(ctx)
  if ctx ~= nil then
    M.fz_drop_context(ctx)
  end
end

--[[--
Opens a document.
--]]
function mupdf.openDocument(filename)
  local mupdf_doc = {
    doc = W.mupdf_open_document(context(), filename),
    filename = filename,
  }

  if mupdf_doc.doc == nil then
    merror("MuPDF cannot open file.")
  end

  -- doc is a cdata<fz_document *>, attach a finalizer to it to release ressources on garbage collection
  mupdf_doc.doc = ffi.gc(mupdf_doc.doc, mupdf.fz_document_gc)

  setmetatable(mupdf_doc, document_mt)

  if mupdf_doc:getPages() <= 0 then
    merror("MuPDF found no pages in file.")
  end

  return mupdf_doc
end

function mupdf.openDocumentFromText(text, magic)
  local stream = W.mupdf_open_memory(
    context(),
    ffi.cast("const unsigned char*", text),
    #text
  )
  local mupdf_doc = {
    doc = W.mupdf_open_document_with_stream(context(), magic, stream),
  }
  W.mupdf_drop_stream(context(), stream)

  if mupdf_doc.doc == nil then
    merror("MuPDF cannot open document from text")
  end

  -- doc is a cdata<fz_document *>, attach a finalizer to it to release ressources on garbage collection
  mupdf_doc.doc = ffi.gc(mupdf_doc.doc, mupdf.fz_document_gc)

  setmetatable(mupdf_doc, document_mt)

  return mupdf_doc
end

-- Document functions:

--[[
close the document

this is done automatically by the garbage collector but can be
triggered explicitly
--]]
function document_mt.__index:close()
  if self.doc ~= nil then
    M.fz_drop_document(context(), self.doc)
    -- Clear the cdata finalizer to avoid a double-free
    self.doc = ffi.gc(self.doc, nil)
    self.doc = nil

    -- Clear the context, too, in order to release memory *now*.
    --- @note: This is mostly for testing the store memory corruption issues investigated in #7627.
    ---        Otherwise, keeping the context around makes sense,
    ---        as we use MµPDF in more places than simply as a Document engine...
    --[[
        if save_ctx then
            print("MuPDF:close dropping context", save_ctx)
            M.fz_drop_context(save_ctx)
            -- Clear the cdata finalizer to avoid a double-free
            save_ctx = ffi.gc(save_ctx, nil)
            save_ctx = nil
        end
        --]]
  end
end

function mupdf.fz_document_gc(doc)
  if doc ~= nil then
    M.fz_drop_document(context(), doc)
  end
end

--[[
check if the document needs a password for access
--]]
function document_mt.__index:needsPassword()
  return M.fz_needs_password(context(), self.doc) ~= 0
end

--[[
try to authenticate with a password
--]]
function document_mt.__index:authenticatePassword(password)
  if M.fz_authenticate_password(context(), self.doc, password) == 0 then
    return false
  end
  return true
end

--[[
read number of pages in document
--]]
function document_mt.__index:getPages()
  -- cache number of pages
  if self.number_of_pages then
    return self.number_of_pages
  end

  local pages = W.mupdf_count_pages(context(), self.doc)
  if pages == -1 then
    merror("cannot access page tree")
  end

  self.number_of_pages = pages

  return pages
end

function document_mt.__index:isDocumentReflowable()
  if self.is_reflowable then
    return self.is_reflowable
  end
  self.is_reflowable = M.fz_is_document_reflowable(context(), self.doc) == 1
  return self.is_reflowable
end

function document_mt.__index:layoutDocument(width, height, em)
  -- Reset the cache.
  self.number_of_pages = nil

  W.mupdf_layout_document(context(), self.doc, width, height, em)
end

function document_mt.__index:setColorRendering(color)
  self.color = color
end

local function toc_walker(toc, outline, depth)
  while outline ~= nil do
    table.insert(toc, {
      page = outline.page.page + 1,
      title = ffi.string(outline.title),
      depth = depth,
    })
    if outline.down then
      toc_walker(toc, outline.down, depth + 1)
    end
    outline = outline.next
  end
end

--[[
read table of contents (ToC)

Returns a table like this:
{
    {page=12, depth=1, title="chapter1"},
    {page=54, depth=1, title="chapter2"},
}

Returns an empty table when there is no ToC
--]]
function document_mt.__index:getToc()
  local toc = {}
  local outline = W.mupdf_load_outline(context(), self.doc)
  if outline ~= nil then
    toc_walker(toc, outline, 1)
    M.fz_drop_outline(context(), outline)
  end
  return toc
end

--[[
open a page, return page object
--]]
function document_mt.__index:openPage(number)
  local mupdf_page = {
    page = W.mupdf_load_page(context(), self.doc, number - 1),
    number = number,
    doc = self,
  }

  if mupdf_page.page == nil then
    merror("cannot open page #" .. number)
  end

  -- page is a cdata<fz_page *>, attach a finalizer to it to release ressources on garbage collection
  mupdf_page.page = ffi.gc(mupdf_page.page, mupdf.fz_page_gc)

  setmetatable(mupdf_page, page_mt)

  return mupdf_page
end

local function getMetadataInfo(doc, info)
  local bufsize = 255
  local buf = ffi.new("char[?]", bufsize)
  -- `fz_lookup_metadata` return the number of bytes needed
  -- to store the string, **including** the null terminator.
  local res = M.fz_lookup_metadata(context(), doc, info, buf, bufsize)
  if res > bufsize then
    -- Buffer was too small.
    bufsize = res
    buf = ffi.new("char[?]", bufsize)
    res = M.fz_lookup_metadata(context(), doc, info, buf, bufsize)
  end
  if res > 1 then
    -- Note: strip the null terminator.
    return ffi.string(buf, res - 1)
  end
  -- Empty string or error (-1).
  return ""
end

--[[
Get metadata, return object
--]]
function document_mt.__index:getMetadata()
  local metadata = {
    title = getMetadataInfo(self.doc, "info:Title"),
    author = getMetadataInfo(self.doc, "info:Author"),
    subject = getMetadataInfo(self.doc, "info:Subject"),
    keywords = getMetadataInfo(self.doc, "info:Keywords"),
    creator = getMetadataInfo(self.doc, "info:Creator"),
    producer = getMetadataInfo(self.doc, "info:Producer"),
    creationDate = getMetadataInfo(self.doc, "info:CreationDate"),
    modDate = getMetadataInfo(self.doc, "info:ModDate"),
  }

  return metadata
end

--[[
return currently claimed memory by MuPDF

This will return sensible values only when the debug_memory flag is set
--]]
function document_mt.__index:getCacheSize()
  if mupdf.debug_memory then
    return W.mupdf_get_cache_size()
  else
    return 0
  end
end

function document_mt.__index:cleanCache()
  -- NOP, just for API compatibility
end

--[[
write the document to a new file
--]]
function document_mt.__index:writeDocument(filename)
  local opts = ffi.new("pdf_write_options[1]")
  opts[0].do_incremental = (filename == self.filename) and 1 or 0
  opts[0].do_ascii = 0
  opts[0].do_garbage = 0
  opts[0].do_linear = 0
  local ok = W.mupdf_pdf_save_document(
    context(),
    ffi.cast("pdf_document*", self.doc),
    filename,
    opts
  )
  if ok == nil then
    merror("could not write document")
  end
end

-- Page functions:

--[[
explicitly close the page object

this is done implicitly by garbage collection, too.
--]]
function page_mt.__index:close()
  if self.page ~= nil then
    M.fz_drop_page(context(), self.page)
    -- Clear the cdata finalizer to avoid a double-free
    self.page = ffi.gc(self.page, nil)
    self.page = nil
  end
end

function mupdf.fz_page_gc(page)
  if page ~= nil then
    M.fz_drop_page(context(), page)
  end
end

--[[
calculate page size after applying DrawContext
--]]
function page_mt.__index:getSize(draw_context)
  local bounds = ffi.new("fz_rect")
  local ctm = ffi.new("fz_matrix")

  W.mupdf_fz_scale(ctm, draw_context.zoom, draw_context.zoom)
  W.mupdf_fz_pre_rotate(ctm, draw_context.rotate)

  W.mupdf_fz_bound_page(context(), self.page, bounds)
  W.mupdf_fz_transform_rect(bounds, ctm)

  -- NOTE: fz_bound_page returns an internal representation computed @ 72dpi...
  --       It is often superbly mysterious, even for images,
  --       so we do *NOT* want to round it right now,
  --       as it would introduce rounding errors much too early in the pipeline...
  -- NOTE: ReaderZooming uses it to compute the scale factor, where accuracy matters!
  -- NOTE: This is also used in conjunction with getUsedBBox,
  --       which also returns precise, floating point rectangles!
  --[[
    M.fz_round_rect(bbox, bounds)
    return bbox[0].x1-bbox[0].x0, bbox[0].y1-bbox[0].y0
    --]]

  return bounds.x1 - bounds.x0, bounds.y1 - bounds.y0
end

--[[
check which part of the page actually contains content
--]]
function page_mt.__index:getUsedBBox()
  local result = ffi.new("fz_rect")

  local dev = W.mupdf_new_bbox_device(context(), result)
  if dev == nil then
    merror("cannot allocate bbox_device")
  end
  local ok = W.mupdf_run_page(context(), self.page, dev, M.fz_identity, nil)
  M.fz_close_device(context(), dev)
  M.fz_drop_device(context(), dev)
  if ok == nil then
    merror("cannot calculate bbox for page")
  end

  return result.x0, result.y0, result.x1, result.y1
end

local B = string.byte
local function is_unicode_wspace(c)
  return c == 9 --  TAB
    or c == 0x0a --  HT
    or c == 0x0b --  LF
    or c == 0x0c --  VT
    or c == 0x0d --  FF
    or c == 0x20 --  CR
    or c == 0x85 --  NEL
    or c == 0xA0 --  No break space
    or c == 0x1680 --  Ogham space mark
    or c == 0x180E --  Mongolian Vowel Separator
    or c == 0x2000 --  En quad
    or c == 0x2001 --  Em quad
    or c == 0x2002 --  En space
    or c == 0x2003 --  Em space
    or c == 0x2004 --  Three-per-Em space
    or c == 0x2005 --  Four-per-Em space
    or c == 0x2006 --  Five-per-Em space
    or c == 0x2007 --  Figure space
    or c == 0x2008 --  Punctuation space
    or c == 0x2009 --  Thin space
    or c == 0x200A --  Hair space
    or c == 0x2028 --  Line separator
    or c == 0x2029 --  Paragraph separator
    or c == 0x202F --  Narrow no-break space
    or c == 0x205F --  Medium mathematical space
    or c == 0x3000 --  Ideographic space
end
local function is_unicode_bullet(c)
  -- Not all of them are strictly bullets, but will do for our usage here
  return c == 0x2022 --  Bullet
    or c == 0x2023 --  Triangular bullet
    or c == 0x25a0 --  Black square
    or c == 0x25cb --  White circle
    or c == 0x25cf --  Black circle
    or c == 0x25e6 --  White bullet
    or c == 0x2043 --  Hyphen bullet
    or c == 0x2219 --  Bullet operator
    or c == 149 --  Ascii bullet
    or c == B("*")
end

local function skip_starting_bullet(line)
  local ch = line.first_char
  local found_bullet = false

  while ch ~= nil do
    if is_unicode_bullet(ch.c) then
      found_bullet = true
    elseif not is_unicode_wspace(ch.c) then
      break
    end

    ch = ch.next
  end

  if found_bullet then
    return ch
  else
    return line.first_char
  end
end

--[[
get the text of the given page

will return text in a Lua table that is modeled after
djvu.c creates this table.

note that the definition of "line" is somewhat arbitrary
here (for now)

MuPDFs API provides text as single char information
that is collected in "spans". we use a span as a "line"
in Lua output and segment spans into words by looking
for space characters.

will return an empty table if we have no text
--]]
function page_mt.__index:getPageText()
  -- first, we run the page through a special device, the text_device
  local text_page = W.mupdf_new_stext_page_from_page(context(), self.page, nil)
  if text_page == nil then
    merror("cannot alloc text_page")
  end

  -- now we analyze the data returned by the device and bring it
  -- into the format we want to return
  local lines = {}
  local size = 0

  local block = text_page.first_block
  while block ~= nil do
    if block.type == M.FZ_STEXT_BLOCK_TEXT then
      -- a block contains lines, which is our primary return datum
      local mupdf_line = block.u.t.first_line
      while mupdf_line ~= nil do
        local line = {}
        local line_bbox = ffi.new("fz_rect", M.fz_empty_rect)

        local first_char = skip_starting_bullet(mupdf_line)
        local ch = first_char
        local ch_len = 0
        while ch ~= nil do
          ch = ch.next
          ch_len = ch_len + 1
        end

        if ch_len > 0 then
          -- here we will collect UTF-8 chars before making them
          -- a Lua string:
          local textbuf = ffi.new("char[?]", ch_len * 4)

          ch = first_char
          while ch ~= nil do
            local textlen = 0
            local word_bbox = ffi.new("fz_rect", M.fz_empty_rect)
            while ch ~= nil do
              if is_unicode_wspace(ch.c) then
                -- ignore and end word
                break
              end
              textlen = textlen + M.fz_runetochar(textbuf + textlen, ch.c)
              local char_bbox = ffi.new("fz_rect")
              W.mupdf_fz_rect_from_quad(char_bbox, ch.quad)
              W.mupdf_fz_union_rect(word_bbox, char_bbox)
              W.mupdf_fz_union_rect(line_bbox, char_bbox)
              if
                ch.c >= 0x4e00 and ch.c <= 0x9FFF -- CJK Unified Ideographs
                or ch.c >= 0x2000 and ch.c <= 0x206F -- General Punctuation
                or ch.c >= 0x3000 and ch.c <= 0x303F -- CJK Symbols and Punctuation
                or ch.c >= 0x3400 and ch.c <= 0x4DBF -- CJK Unified Ideographs Extension A
                or ch.c >= 0xF900 and ch.c <= 0xFAFF -- CJK Compatibility Ideographs
                or ch.c >= 0xFF01 and ch.c <= 0xFFEE -- Halfwidth and Fullwidth Forms
                or ch.c >= 0x20000 and ch.c <= 0x2A6DF -- CJK Unified Ideographs Extension B
              then
                -- end word
                break
              end
              ch = ch.next
            end
            -- add word to line
            table.insert(line, {
              word = ffi.string(textbuf, textlen),
              x0 = word_bbox.x0,
              y0 = word_bbox.y0,
              x1 = word_bbox.x1,
              y1 = word_bbox.y1,
            })
            size = size + 5 * 8 + textlen

            if ch == nil then
              break
            end

            ch = ch.next
          end

          line.x0, line.y0 = line_bbox.x0, line_bbox.y0
          line.x1, line.y1 = line_bbox.x1, line_bbox.y1
          size = size + 5 * 8

          table.insert(lines, line)
        end

        mupdf_line = mupdf_line.next
      end
    end

    block = block.next
  end

  -- Rough approximation of size for caching
  lines.size = size

  M.fz_drop_stext_page(context(), text_page)

  return lines
end

--[[
Get a list of the Hyperlinks on a page
--]]
function page_mt.__index:getPageLinks()
  local page_links = W.mupdf_load_links(context(), self.page)
  -- do not error out when page_links == NULL, since there might
  -- simply be no links present.

  local links = {}

  local link = page_links
  while link ~= nil do
    local data = {
      x0 = link.rect.x0,
      y0 = link.rect.y0,
      x1 = link.rect.x1,
      y1 = link.rect.y1,
    }
    local pos = ffi.new("float[2]")
    local location = ffi.new("fz_location")
    W.mupdf_fz_resolve_link(
      context(),
      self.doc.doc,
      link.uri,
      pos,
      pos + 1,
      location
    )
    -- `fz_resolve_link` return a location of (-1, -1) for external links.
    if location.chapter == -1 and location.page == -1 then
      data.uri = ffi.string(link.uri)
    else
      data.page =
        W.mupdf_fz_page_number_from_location(context(), self.doc.doc, location)
    end
    data.pos = {
      x = pos[0],
      y = pos[1],
    }
    table.insert(links, data)
    link = link.next
  end

  M.fz_drop_link(context(), page_links)

  return links
end

local function run_page(page, pixmap, ctm)
  M.fz_clear_pixmap_with_value(context(), pixmap, 0xff)

  local dev = W.mupdf_new_draw_device(context(), nil, pixmap)
  if dev == nil then
    merror("cannot create draw device")
  end

  local ok = W.mupdf_run_page(context(), page.page, dev, ctm, nil)
  M.fz_close_device(context(), dev)
  M.fz_drop_device(context(), dev)
  if ok == nil then
    merror("could not run page")
  end
end
--[[
render page to blitbuffer

old interface: expects a blitbuffer to render to
--]]
function page_mt.__index:draw(draw_context, blitbuffer, offset_x, offset_y)
  local buffer = self:draw_new(
    draw_context,
    blitbuffer:getWidth(),
    blitbuffer:getHeight(),
    offset_x,
    offset_y
  )
  blitbuffer:blitFrom(buffer)
  buffer:free()
end
--[[
render page to blitbuffer

new interface: creates the blitbuffer with the rendered data and returns that
TODO: make this the used interface
--]]
function page_mt.__index:draw_new(
  draw_context,
  width,
  height,
  offset_x,
  offset_y
)
  local ctm = ffi.new("fz_matrix")

  W.mupdf_fz_scale(ctm, draw_context.zoom, draw_context.zoom)
  W.mupdf_fz_pre_rotate(ctm, draw_context.rotate)
  W.mupdf_fz_pre_translate(ctm, draw_context.offset_x, draw_context.offset_y)

  local bbox =
    ffi.new("fz_irect", offset_x, offset_y, offset_x + width, offset_y + height)

  local bb = BlitBuffer.new(
    width,
    height,
    self.doc.color and BlitBuffer.TYPE_BBRGB32 or BlitBuffer.TYPE_BB8
  )

  local colorspace = self.doc.color and M.fz_device_rgb(context())
    or M.fz_device_gray(context())
  if mupdf.bgr and self.doc.color then
    colorspace = M.fz_device_bgr(context())
  end
  local pix = W.mupdf_new_pixmap_with_bbox_and_data(
    context(),
    colorspace,
    bbox,
    nil,
    self.doc.color and 1 or 0,
    ffi.cast("unsigned char*", bb.data)
  )
  if pix == nil then
    merror("cannot allocate pixmap")
  end

  run_page(self, pix, ctm)

  if draw_context.gamma >= 0.0 then
    M.fz_gamma_pixmap(context(), pix, draw_context.gamma)
  end

  M.fz_drop_pixmap(context(), pix)

  return bb
end

mupdf.STRIKE_HEIGHT = 0.375
mupdf.UNDERLINE_HEIGHT = 0
mupdf.LINE_THICKNESS = 0.05
mupdf.HIGHLIGHT_COLOR = { 1.0, 1.0, 0.0 }
mupdf.UNDERLINE_COLOR = { 0.0, 0.0, 1.0 }
mupdf.STRIKE_OUT_COLOR = { 1.0, 0.0, 0.0 }

function page_mt.__index:addMarkupAnnotation(points, n, type, bb_color)
  local color = ffi.new("float[3]")
  local alpha = 1.0
  if type == M.PDF_ANNOT_HIGHLIGHT then
    if bb_color then
      color[0] = bb_color.r / 255
      color[1] = bb_color.g / 255
      color[2] = bb_color.b / 255
    else
      color[0] = mupdf.HIGHLIGHT_COLOR[1]
      color[1] = mupdf.HIGHLIGHT_COLOR[2]
      color[2] = mupdf.HIGHLIGHT_COLOR[3]
    end
    alpha = 0.5
  elseif type == M.PDF_ANNOT_UNDERLINE then
    if bb_color then
      color[0] = bb_color.r / 255
      color[1] = bb_color.g / 255
      color[2] = bb_color.b / 255
    else
      color[0] = mupdf.UNDERLINE_COLOR[1]
      color[1] = mupdf.UNDERLINE_COLOR[2]
      color[2] = mupdf.UNDERLINE_COLOR[3]
    end
  elseif type == M.PDF_ANNOT_STRIKE_OUT then
    if bb_color then
      color[0] = bb_color.r / 255
      color[1] = bb_color.g / 255
      color[2] = bb_color.b / 255
    else
      color[0] = mupdf.STRIKE_OUT_COLOR[1]
      color[1] = mupdf.STRIKE_OUT_COLOR[2]
      color[2] = mupdf.STRIKE_OUT_COLOR[3]
    end
  else
    return
  end

  local annot =
    W.mupdf_pdf_create_annot(context(), ffi.cast("pdf_page*", self.page), type)
  if annot == nil then
    merror("could not create annotation")
  end

  local ok = W.mupdf_pdf_set_annot_quad_points(context(), annot, n, points)
  if ok == nil then
    merror("could not set annotation quadpoints")
  end

  ok = W.mupdf_pdf_set_annot_color(context(), annot, 3, color)
  if ok == nil then
    merror("could not set annotation color")
  end

  ok = W.mupdf_pdf_set_annot_opacity(context(), annot, alpha)
  if ok == nil then
    merror("could not set annotation opacity")
  end

  -- Fetch back MuPDF's stored coordinates of all quadpoints, as they may have been modified/rounded
  -- (we need the exact ones that were saved if we want to be able to find them for deletion/update)
  for i = 0, n - 1 do
    W.mupdf_pdf_annot_quad_point(context(), annot, i, points + i)
  end
end

function page_mt.__index:deleteMarkupAnnotation(annot)
  local ok =
    W.mupdf_pdf_delete_annot(context(), ffi.cast("pdf_page*", self.page), annot)
  if ok == nil then
    merror("could not delete markup annotation")
  end
end

function page_mt.__index:getMarkupAnnotation(points, n)
  local annot =
    W.mupdf_pdf_first_annot(context(), ffi.cast("pdf_page*", self.page))
  while annot ~= nil do
    local n2 = W.mupdf_pdf_annot_quad_point_count(context(), annot)
    if n == n2 then
      local quadpoint = ffi.new("fz_quad[1]")
      local match = true
      for i = 0, n - 1 do
        W.mupdf_pdf_annot_quad_point(context(), annot, i, quadpoint)
        if
          points[i].ul.x ~= quadpoint[0].ul.x
          or points[i].ul.y ~= quadpoint[0].ul.y
          or points[i].ur.x ~= quadpoint[0].ur.x
          or points[i].ur.y ~= quadpoint[0].ur.y
          or points[i].ll.x ~= quadpoint[0].ll.x
          or points[i].ll.y ~= quadpoint[0].ll.y
          or points[i].lr.x ~= quadpoint[0].lr.x
          or points[i].lr.y ~= quadpoint[0].lr.y
        then
          match = false
          break
        end
      end
      if match then
        return annot
      end
    end
    annot = W.mupdf_pdf_next_annot(context(), annot)
  end
  return nil
end

function page_mt.__index:updateMarkupAnnotation(annot, contents)
  local ok = W.mupdf_pdf_set_annot_contents(context(), annot, contents)
  if ok == nil then
    merror("could not update markup annot contents")
  end
end

-- image loading via MuPDF:

--[[--
Renders image data.
--]]
function mupdf.renderImage(data, size, width, height)
  local buffer = W.mupdf_new_buffer_from_shared_data(
    context(),
    ffi.cast("unsigned char*", data),
    size
  )
  local image = W.mupdf_new_image_from_buffer(context(), buffer)
  W.mupdf_drop_buffer(context(), buffer)
  if image == nil then
    merror("could not load image data")
  end
  local pixmap =
    W.mupdf_get_pixmap_from_image(context(), image, nil, nil, nil, nil)
  M.fz_drop_image(context(), image)
  if pixmap == nil then
    merror("could not create pixmap from image")
  end

  local p_width = M.fz_pixmap_width(context(), pixmap)
  local p_height = M.fz_pixmap_height(context(), pixmap)
  -- mupdf_get_pixmap_from_image() may not scale image to the
  -- width and height provided, so check and scale it if needed
  if width and height then
    -- Ensure we pass integer values for width & height to fz_scale_pixmap(),
    -- because it enforces an alpha channel otherwise...
    width = math.floor(width)
    height = math.floor(height)
    if p_width ~= width or p_height ~= height then
      local scaled_pixmap =
        M.fz_scale_pixmap(context(), pixmap, 0, 0, width, height, nil)
      M.fz_drop_pixmap(context(), pixmap)
      if scaled_pixmap == nil then
        merror("could not create scaled pixmap from pixmap")
      end
      pixmap = scaled_pixmap
      p_width = M.fz_pixmap_width(context(), pixmap)
      p_height = M.fz_pixmap_height(context(), pixmap)
    end
  end
  local bbtype
  local ncomp = M.fz_pixmap_components(context(), pixmap)
  if ncomp == 1 then
    bbtype = BlitBuffer.TYPE_BB8
  elseif ncomp == 2 then
    bbtype = BlitBuffer.TYPE_BB8A
  elseif ncomp == 3 then
    bbtype = BlitBuffer.TYPE_BBRGB24
  elseif ncomp == 4 then
    bbtype = BlitBuffer.TYPE_BBRGB32
  else
    error("unsupported number of color components")
  end
  -- Handle RGB->BGR conversion for Kobos when needed
  local bb
  if mupdf.bgr and ncomp >= 3 then
    local bgr_pixmap = W.mupdf_convert_pixmap(
      context(),
      pixmap,
      M.fz_device_bgr(context()),
      nil,
      nil,
      M.fz_default_color_params,
      (ncomp == 4 and 1 or 0)
    )
    if pixmap == nil then
      merror("could not convert pixmap to BGR")
    end
    M.fz_drop_pixmap(context(), pixmap)

    local p = M.fz_pixmap_samples(context(), bgr_pixmap)
    bb = BlitBuffer.new(p_width, p_height, bbtype, p):copy()
    M.fz_drop_pixmap(context(), bgr_pixmap)
  else
    local p = M.fz_pixmap_samples(context(), pixmap)
    bb = BlitBuffer.new(p_width, p_height, bbtype, p):copy()
    M.fz_drop_pixmap(context(), pixmap)
  end
  return bb
end

--- Renders image file.
function mupdf.renderImageFile(filename, width, height)
  local file = io.open(filename, "rb")
  if not file then
    error("could not open image file")
  end
  local data = file:read("*a")
  file:close()
  return mupdf.renderImage(data, #data, width, height)
end

--[[--
Scales a blitbuffer.

MµPDF's scaling is of much better quality than the very naive implementation in blitbuffer.lua.
(see fz_scale_pixmap_cached() in mupdf/source/fitz/draw-scale-simple.c).
Same arguments as BlitBuffer:scale() for easy replacement.

Unlike BlitBuffer:scale(), this *ignores* the blitbuffer's rotation
(i.e., where possible, we simply wrap the BlitBuffer's data in a fitz pixmap,
with no data copy, so the buffer's *native* memory layout is followed).
If you actually want to preserve the rotation, you'll have to fudge
with the width & height arguments and tweak the returned buffer's rotation flag,
or go through a temporary copy to ensure that the buffer's memory is laid out accordingly.
--]]
function mupdf.scaleBlitBuffer(bb, width, height)
  -- We need first to convert our BlitBuffer to a pixmap
  local bbtype = bb:getType()
  local colorspace
  local converted_bb
  local alpha
  local stride = bb.stride
  -- MuPDF should know how to handle *most* of our BB types,
  -- special snowflakes excluded (4bpp & RGB565),
  -- in which case we feed it a temporary copy in the closest format it'll understand.
  if bbtype == BlitBuffer.TYPE_BB8 then
    colorspace = M.fz_device_gray(context())
    alpha = 0
  elseif bbtype == BlitBuffer.TYPE_BB8A then
    colorspace = M.fz_device_gray(context())
    alpha = 1
  elseif bbtype == BlitBuffer.TYPE_BBRGB24 then
    if mupdf.bgr then
      colorspace = M.fz_device_bgr(context())
    else
      colorspace = M.fz_device_rgb(context())
    end
    alpha = 0
  elseif bbtype == BlitBuffer.TYPE_BBRGB32 then
    if mupdf.bgr then
      colorspace = M.fz_device_bgr(context())
    else
      colorspace = M.fz_device_rgb(context())
    end
    alpha = 1
  elseif bbtype == BlitBuffer.TYPE_BB4 then
    converted_bb = BlitBuffer.new(bb.w, bb.h, BlitBuffer.TYPE_BB8)
    converted_bb:blitFrom(bb, 0, 0, 0, 0, bb.w, bb.h)
    bb = converted_bb -- we don't free() the provided bb, but we'll have to free our converted_bb
    colorspace = M.fz_device_gray(context())
    alpha = 0
    stride = bb.w
  else
    converted_bb = BlitBuffer.new(bb.w, bb.h, BlitBuffer.TYPE_BBRGB32)
    converted_bb:blitFrom(bb, 0, 0, 0, 0, bb.w, bb.h)
    bb = converted_bb -- we don't free() the provided bb, but we'll have to free our converted_bb
    if mupdf.bgr then
      colorspace = M.fz_device_bgr(context())
    else
      colorspace = M.fz_device_rgb(context())
    end
    alpha = 1
  end
  -- We can now create a pixmap from this bb of correct type
  local pixmap = W.mupdf_new_pixmap_with_data(
    context(),
    colorspace,
    bb.w,
    bb.h,
    nil,
    alpha,
    stride,
    ffi.cast("unsigned char*", bb.data)
  )
  if pixmap == nil then
    if converted_bb then
      converted_bb:free()
    end -- free our home made bb
    merror("could not create pixmap from blitbuffer")
  end
  -- We can now scale the pixmap
  -- Better to ensure we give integer width and height, to avoid a black 1-pixel line at right and bottom of image.
  -- Also, fz_scale_pixmap enforces an alpha channel if w or h are floats...
  local scaled_pixmap = M.fz_scale_pixmap(
    context(),
    pixmap,
    0,
    0,
    math.floor(width),
    math.floor(height),
    nil
  )
  M.fz_drop_pixmap(context(), pixmap) -- free our original pixmap
  if scaled_pixmap == nil then
    if converted_bb then
      converted_bb:free()
    end -- free our home made bb
    merror("could not create scaled pixmap from pixmap")
  end
  local p_width = M.fz_pixmap_width(context(), scaled_pixmap)
  local p_height = M.fz_pixmap_height(context(), scaled_pixmap)
  -- And convert the pixmap back to a BlitBuffer
  bbtype = nil
  local ncomp = M.fz_pixmap_components(context(), scaled_pixmap)
  if ncomp == 1 then
    bbtype = BlitBuffer.TYPE_BB8
  elseif ncomp == 2 then
    bbtype = BlitBuffer.TYPE_BB8A
  elseif ncomp == 3 then
    bbtype = BlitBuffer.TYPE_BBRGB24
  elseif ncomp == 4 then
    bbtype = BlitBuffer.TYPE_BBRGB32
  else
    if converted_bb then
      converted_bb:free()
    end -- free our home made bb
    error("unsupported number of color components")
  end
  local p = M.fz_pixmap_samples(context(), scaled_pixmap)
  bb = BlitBuffer.new(p_width, p_height, bbtype, p):copy()
  M.fz_drop_pixmap(context(), scaled_pixmap) -- free our scaled pixmap
  if converted_bb then
    converted_bb:free()
  end -- free our home made bb
  return bb
end

-- k2pdfopt interfacing

-- will lazily load ffi/koptcontext.lua in order to interface k2pdfopt
local cached_k2pdfopt
local function get_k2pdfopt()
  if cached_k2pdfopt then
    return cached_k2pdfopt
  end

  local koptcontext = require("ffi/koptcontext")
  cached_k2pdfopt = koptcontext.k2pdfopt
  return cached_k2pdfopt
end

-- lazily load libpthread
local cached_pthread
local function get_pthread()
  if cached_pthread then
    return cached_pthread
  end

  local util = require("ffi/util")

  require("ffi/pthread_h")

  local ok
  if ffi.os == "Windows" then
    return ffi.load("libwinpthread-1.dll")
  elseif util.isAndroid() then
    -- pthread directives are in Bionic library on Android
    ok, cached_pthread = pcall(ffi.load, "libc.so")
    if ok then
      return cached_pthread
    end
  else
    -- Kobo devices strangely have no libpthread.so in LD_LIBRARY_PATH
    -- so we hardcode the libpthread.so.0 here just for Kobo.
    for _, libname in ipairs({ "pthread", "libpthread.so.0" }) do
      ok, cached_pthread = pcall(ffi.load, libname)
      if ok then
        return cached_pthread
      end
    end
  end
end

--[[
the following function is a reimplementation of what can be found
in libk2pdfopt/willuslib/bmpmupdf.c
k2pdfopt supports only 8bit and 24bit "bitmaps" - and mupdf will give
only 8bit+8bit alpha or 24bit+8bit alpha pixmaps. So we need to convert
what we get from mupdf.
--]]
local function bmpmupdf_pixmap_to_bmp(bmp, pixmap)
  local k2pdfopt = get_k2pdfopt()

  bmp.width = M.fz_pixmap_width(context(), pixmap)
  bmp.height = M.fz_pixmap_height(context(), pixmap)
  local ncomp = M.fz_pixmap_components(context(), pixmap)
  local p = M.fz_pixmap_samples(context(), pixmap)
  if ncomp == 2 or ncomp == 4 then
    k2pdfopt.pixmap_to_bmp(bmp, p, ncomp)
  else
    error("unsupported pixmap format for conversion to bmp")
  end
end

local function render_for_kopt(bmp, page, scale, bounds)
  local k2pdfopt = get_k2pdfopt()

  local bbox = ffi.new("fz_irect")
  local ctm = ffi.new("fz_matrix")
  W.mupdf_fz_scale(ctm, scale, scale)
  W.mupdf_fz_transform_rect(bounds, ctm)
  W.mupdf_fz_round_rect(bbox, bounds)

  local colorspace = page.doc.color and M.fz_device_rgb(context())
    or M.fz_device_gray(context())
  if mupdf.bgr and page.doc.color then
    colorspace = M.fz_device_bgr(context())
  end
  local pix = W.mupdf_new_pixmap_with_bbox(context(), colorspace, bbox, nil, 1)
  if pix == nil then
    merror("could not allocate pixmap")
  end

  run_page(page, pix, ctm)

  k2pdfopt.bmp_init(bmp)

  bmpmupdf_pixmap_to_bmp(bmp, pix)

  M.fz_drop_pixmap(context(), pix)
end

function page_mt.__index:reflow(kopt_context)
  local k2pdfopt = get_k2pdfopt()

  local bounds = ffi.new(
    "fz_rect",
    kopt_context.bbox.x0,
    kopt_context.bbox.y0,
    kopt_context.bbox.x1,
    kopt_context.bbox.y1
  )
  -- probe scale
  local zoom = kopt_context.zoom * kopt_context.quality
  local scale = (1.5 * zoom * kopt_context.dev_width) / bounds.x1
  -- store zoom
  kopt_context.zoom = scale
  -- do real scale
  mupdf.debug(
    string.format(
      "reading page:%d,%d,%d,%d scale:%.2f",
      bounds.x0,
      bounds.y0,
      bounds.x1,
      bounds.y1,
      scale
    )
  )
  render_for_kopt(kopt_context.src, self, scale, bounds)

  if kopt_context.precache ~= 0 then
    local pthread = get_pthread()
    local rf_thread = ffi.new("pthread_t[1]")
    local attr = ffi.new("pthread_attr_t[1]")
    pthread.pthread_attr_init(attr)
    pthread.pthread_attr_setdetachstate(attr, pthread.PTHREAD_CREATE_DETACHED)
    pthread.pthread_create(
      rf_thread,
      attr,
      k2pdfopt.k2pdfopt_reflow_bmp,
      ffi.cast("void*", kopt_context)
    )
    pthread.pthread_attr_destroy(attr)
  else
    k2pdfopt.k2pdfopt_reflow_bmp(kopt_context)
  end
end

function page_mt.__index:getPagePix(kopt_context)
  local bounds = ffi.new(
    "fz_rect",
    kopt_context.bbox.x0,
    kopt_context.bbox.y0,
    kopt_context.bbox.x1,
    kopt_context.bbox.y1
  )

  render_for_kopt(kopt_context.src, self, kopt_context.zoom, bounds)

  kopt_context.page_width = kopt_context.src.width
  kopt_context.page_height = kopt_context.src.height
end

function page_mt.__index:toBmp(bmp, dpi)
  local bounds = ffi.new("fz_rect")
  W.mupdf_fz_bound_page(context(), self.page, bounds)
  render_for_kopt(bmp, self, dpi / 72, bounds)
end

return mupdf
