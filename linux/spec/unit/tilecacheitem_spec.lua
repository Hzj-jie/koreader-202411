describe("TileCacheItem", function()
  local TileCacheItem, Blitbuffer, ffiUtil

  setup(function()
    require("commonrequire")
    require("document/canvascontext"):init(require("device"))
    TileCacheItem = require("document/tilecacheitem")
    Blitbuffer = require("ffi/blitbuffer")
    ffiUtil = require("ffi/util")
  end)

  it("should convert to table and restore from table preserving attributes and Blitbuffer", function()
    local bb = Blitbuffer.new(16, 16, Blitbuffer.TYPE_BB8)

    local item = TileCacheItem:new({
      size = 256,
      pageno = 42,
      excerpt = "Chapter Title",
      created_ts = 1700000000,
      persistent = true,
      doc_path = "/books/test.epub",
      bb = bb,
    })

    local t = item:totable()
    assert.is_table(t)
    assert.are.equal(256, t.size)
    assert.are.equal(42, t.pageno)
    assert.are.equal("Chapter Title", t.excerpt)
    assert.are.equal(1700000000, t.created_ts)
    assert.is_true(t.persistent)
    assert.are.equal("/books/test.epub", t.doc_path)
    assert.is_table(t.bb)
    assert.are.equal(16, t.bb.w)
    assert.are.equal(16, t.bb.h)
    assert.are.equal(Blitbuffer.TYPE_BB8, t.bb.fmt)
    assert.is_string(t.bb.data)

    -- Restore into a new item
    local restored = TileCacheItem:new()
    restored:fromtable(t)

    assert.are.equal(256, restored.size)
    assert.are.equal(42, restored.pageno)
    assert.are.equal("Chapter Title", restored.excerpt)
    assert.are.equal(1700000000, restored.created_ts)
    assert.is_true(restored.persistent)
    assert.are.equal("/books/test.epub", restored.doc_path)
    assert.is_truthy(restored.bb)
    assert.are.equal(16, restored.bb.w)
    assert.are.equal(16, restored.bb.h)
    assert.are.equal(Blitbuffer.TYPE_BB8, restored.bb:getType())

    item:onFree()
    restored:onFree()
  end)

  it("should round-trip dump and load via Persist to a temporary file", function()
    local temp_path = "/tmp/test_tilecache_" .. ffiUtil.getpid() .. ".zst"

    local bb = Blitbuffer.new(32, 32, Blitbuffer.TYPE_BB8)

    local item = TileCacheItem:new({
      size = 1024,
      pageno = 7,
      excerpt = "Page 7 excerpt",
      created_ts = 1700000500,
      persistent = false,
      doc_path = "/books/sample.pdf",
      bb = bb,
    })

    local size = item:dump(temp_path)
    assert.is_truthy(size)
    assert.is_true(tonumber(size) > 0)

    local loaded_item = TileCacheItem:new()
    loaded_item:load(temp_path)

    os.remove(temp_path)

    assert.are.equal(1024, loaded_item.size)
    assert.are.equal(7, loaded_item.pageno)
    assert.are.equal("Page 7 excerpt", loaded_item.excerpt)
    assert.are.equal(1700000500, loaded_item.created_ts)
    assert.is_false(loaded_item.persistent)
    assert.are.equal("/books/sample.pdf", loaded_item.doc_path)
    assert.is_truthy(loaded_item.bb)
    assert.are.equal(32, loaded_item.bb.w)
    assert.are.equal(32, loaded_item.bb.h)

    item:onFree()
    loaded_item:onFree()
  end)

  it("should return nil on dump failure and handle missing file in load gracefully", function()
    local bb = Blitbuffer.new(8, 8, Blitbuffer.TYPE_BB8)
    local item = TileCacheItem:new({
      bb = bb,
    })

    local dump_res = item:dump("/nonexistent/invalid/dir/cache.zst")
    assert.is_nil(dump_res)

    local empty_item = TileCacheItem:new()
    empty_item:load("/nonexistent/missing/file.zst")
    assert.is_nil(empty_item.bb)

    item:onFree()
  end)
end)
