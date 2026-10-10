local DataStorage = require("datastorage")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local md5 = require("ffi/sha2").md5
local util = require("util")

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
end)

describe("Cache unit behavior", function()
  local Cache

  setup(function()
    Cache = require("cache")
  end)

  it(
    "should support slot-only mode without disk cache and enforce LRU eviction",
    function()
      local c = Cache:new({ slots = 2 })
      c:init()

      c:insert("a", "val_a")
      assert.are.equal("val_a", c:check("a"))
      assert.are.equal("val_a", c:get("a"))
      assert.is_nil(c.cached)
      c:refreshSnapshot()
      assert.is_nil(c.cached)

      c:insert("b", "val_b")
      assert.are.equal("val_a", c:check("a")) -- touches "a", making "b" the LRU entry
      c:insert("c", "val_c")

      assert.are.equal("val_a", c:check("a"))
      assert.is_nil(c:check("b")) -- "b" evicted by LRU
      assert.are.equal("val_c", c:check("c"))
    end
  )

  it(
    "should enforce willAccept and reject oversized items in size-bounded mode",
    function()
      local c = Cache:new({
        size = 1000,
        avg_itemsize = 100,
        enable_eviction_cb = true,
      })
      c:init()

      assert.is_true(c:willAccept(499))
      assert.is_false(c:willAccept(500))

      c:insert("oversized", {
        size = 500,
        onFree = function() end,
      })
      assert.is_nil(c:check("oversized"))

      local fit_obj = {
        size = 499,
        onFree = function() end,
      }
      c:insert("fits", fit_obj)
      assert.are.equal(fit_obj, c:check("fits"))
    end
  )

  it(
    "should promote valid on-disk items into RAM and purge corrupt cache files",
    function()
      local tmp_dir = DataStorage:getDataDir()
        .. "/cache_unit_spec_tmp_"
        .. ffiUtil.getpid()
        .. "/"
      util.makePath(tmp_dir)
      local good_file = tmp_dir .. md5("good_key")
      local bad_file = tmp_dir .. md5("bad_key")

      local fg = io.open(good_file, "w")
      fg:write("good_content")
      fg:close()

      local fb = io.open(bad_file, "w")
      fb:write("corrupt_content")
      fb:close()

      finally(function()
        os.remove(good_file)
        os.remove(bad_file)
        util.removePath(tmp_dir)
      end)

      local c = Cache:new({
        size = 1000,
        avg_itemsize = 100,
        enable_eviction_cb = true,
        disk_cache = true,
        cache_path = tmp_dir,
      })
      c:init()

      local ItemClass = {
        new = function(self_cls)
          return {
            size = 100,
            onFree = function() end,
            load = function(self_item, path)
              if path:find("bad_key") or path == bad_file then
                error("corrupt cache file")
              end
              self_item.loaded_from = path
            end,
          }
        end,
      }

      local item = c:check("good_key", ItemClass)
      assert.is_not_nil(item)
      assert.are.equal(good_file, item.loaded_from)

      -- Promoted into RAM: subsequent check without ItemClass succeeds
      assert.are.equal(item, c:check("good_key"))

      -- Corrupt cache file check
      assert.is_nil(c:check("bad_key", ItemClass))
      assert.is_nil(lfs.attributes(bad_file, "mode"))
      assert.is_nil(c.cached[md5("bad_key")])
    end
  )

  it(
    "should handle memoryPressureCheck based on free RAM thresholds",
    function()
      local saved_calc = util.calcFreeMem
      finally(function()
        util.calcFreeMem = saved_calc
      end)

      local c = Cache:new({
        size = 1000,
        avg_itemsize = 100,
        enable_eviction_cb = true,
      })
      c:init()
      for i = 1, 4 do
        c:insert("k" .. i, {
          size = 100,
          onFree = function() end,
        })
      end
      assert.are.equal(4, c.cache:used_slots())

      -- When util.calcFreeMem returns nil, nil -> skips eviction
      util.calcFreeMem = function()
        return nil, nil
      end
      c:memoryPressureCheck()
      assert.are.equal(4, c.cache:used_slots())

      -- When 25% free RAM (>= 20%) -> does not chop
      util.calcFreeMem = function()
        return 250 * 1024 * 1024, 1000 * 1024 * 1024
      end
      c:memoryPressureCheck()
      assert.are.equal(4, c.cache:used_slots())

      -- When 15% free RAM (< 20%) -> chops half the cache
      util.calcFreeMem = function()
        return 150 * 1024 * 1024, 1000 * 1024 * 1024
      end
      c:memoryPressureCheck()
      assert.are.equal(2, c.cache:used_slots())
    end
  )
end)
