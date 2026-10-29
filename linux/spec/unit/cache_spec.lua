describe("Cache module", function()
  local DocumentRegistry, DocCache
  local doc
  local max_page = 1
  setup(function()
    require("commonrequire")
    DocumentRegistry = require("document/documentregistry")
    DocCache = require("document/doccache")

    local sample_pdf = "spec/front/unit/data/sample.pdf"
    doc = DocumentRegistry:openDocument(sample_pdf)
  end)
  teardown(function()
    doc:close()
  end)

  it("should clear cache", function()
    DocCache:clear()
  end)

  it("should serialize blitbuffer", function()
    for pageno = 1, math.min(max_page, doc.info.number_of_pages) do
      doc:renderPage(pageno, nil, 1, 0, 1.0)
      DocCache:serialize()
    end
    DocCache:clear()
  end)

  it("should deserialize blitbuffer", function()
    for pageno = 1, math.min(max_page, doc.info.number_of_pages) do
      doc:hintPage(pageno, 1, 0, 1.0, 0)
    end
    DocCache:clear()
  end)

  it("should serialize koptcontext", function()
    doc.configurable.text_wrap = 1
    for pageno = 1, math.min(max_page, doc.info.number_of_pages) do
      doc:renderPage(pageno, nil, 1, 0, 1.0)
      doc:getPageDimensions(pageno)
      DocCache:serialize()
    end
    DocCache:clear()
    doc.configurable.text_wrap = 0
  end)

  it("should deserialize koptcontext", function()
    for pageno = 1, math.min(max_page, doc.info.number_of_pages) do
      doc:renderPage(pageno, nil, 1, 0, 1.0)
    end
    DocCache:clear()
  end)

  it("purges on-disk cache and returns nil when item:load fails (bug #528)", function()
    local Cache = require("cache")
    local TileCacheItem = require("document/tilecacheitem")
    local ffi = require("ffi")
    local lfs = require("libs/libkoreader-lfs")
    local md5 = require("ffi/sha2").md5
    local zstd = require("ffi/zstd")

    local tmp_dir = (os.getenv("TMPDIR") or "/tmp") .. "/cache_test_" .. tostring(ffi.C.getpid())
    lfs.mkdir(tmp_dir)

    local c = Cache:new({
      size = 1000,
      avg_itemsize = 100,
      enable_eviction_cb = true,
      disk_cache = true,
      cache_path = tmp_dir .. "/",
    })
    c:init()

    local test_key = "corrupt_key"
    local cached_filename = tmp_dir .. "/" .. md5(test_key)
    local payload = "not a valid serialized table payload"
    local cbuff, clen = zstd.zstd_compress(payload, #payload)
    local str = ffi.string(cbuff, clen)
    ffi.C.free(cbuff)

    local f = assert(io.open(cached_filename, "wb"))
    f:write(str)
    f:close()

    finally(function()
      os.remove(cached_filename)
      lfs.rmdir(tmp_dir)
    end)

    c:refreshSnapshot()
    assert.is_not_nil(c.cached[md5(test_key)])

    local res = c:check(test_key, TileCacheItem)
    assert.is_nil(res)
    assert.is_nil(lfs.attributes(cached_filename))
  end)

  it("loads valid dumped TileCacheItem through Cache:check", function()
    local Blitbuffer = require("ffi/blitbuffer")
    local Cache = require("cache")
    local TileCacheItem = require("document/tilecacheitem")
    local ffi = require("ffi")
    local lfs = require("libs/libkoreader-lfs")
    local md5 = require("ffi/sha2").md5

    local tmp_dir = (os.getenv("TMPDIR") or "/tmp") .. "/cache_rt_test_" .. tostring(ffi.C.getpid())
    lfs.mkdir(tmp_dir)

    local c = Cache:new({
      size = 1000000,
      avg_itemsize = 10000,
      enable_eviction_cb = true,
      disk_cache = true,
      cache_path = tmp_dir .. "/",
    })
    c:init()

    local bb = Blitbuffer.new(10, 10, Blitbuffer.TYPE_BWRGB32)
    local item = TileCacheItem:new({
      size = 1000,
      pageno = 1,
      excerpt = { x = 0, y = 0, w = 10, h = 10 },
      created_ts = os.time(),
      persistent = true,
      doc_path = "/dummy/path.pdf",
      bb = bb,
    })

    local test_key = "valid_key"
    local cached_filename = tmp_dir .. "/" .. md5(test_key)
    assert.is_not_nil(item:dump(cached_filename))

    finally(function()
      bb:free()
      os.remove(cached_filename)
      lfs.rmdir(tmp_dir)
    end)

    c:refreshSnapshot()
    local loaded = c:check(test_key, TileCacheItem)
    assert.is_not_nil(loaded)
    assert.are.equal(1, loaded.pageno)
    assert.are.same({ x = 0, y = 0, w = 10, h = 10 }, loaded.excerpt)
    assert.is_not_nil(loaded.bb)
    loaded.bb:free()
  end)

  it("purges truncated zstd on-disk cache file and returns nil", function()
    local Cache = require("cache")
    local TileCacheItem = require("document/tilecacheitem")
    local ffi = require("ffi")
    local lfs = require("libs/libkoreader-lfs")
    local md5 = require("ffi/sha2").md5

    local tmp_dir = (os.getenv("TMPDIR") or "/tmp") .. "/cache_trunc_test_" .. tostring(ffi.C.getpid())
    lfs.mkdir(tmp_dir)

    local c = Cache:new({
      size = 1000,
      avg_itemsize = 100,
      enable_eviction_cb = true,
      disk_cache = true,
      cache_path = tmp_dir .. "/",
    })
    c:init()

    local test_key = "trunc_key"
    local cached_filename = tmp_dir .. "/" .. md5(test_key)
    local f = assert(io.open(cached_filename, "wb"))
    f:write("truncated zstd header")
    f:close()

    finally(function()
      os.remove(cached_filename)
      lfs.rmdir(tmp_dir)
    end)

    c:refreshSnapshot()
    assert.is_not_nil(c.cached[md5(test_key)])

    local res = c:check(test_key, TileCacheItem)
    assert.is_nil(res)
    assert.is_nil(lfs.attributes(cached_filename))
  end)
end)
