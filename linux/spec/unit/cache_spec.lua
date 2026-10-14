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

  it(
    "initializes DocCache.cache_path using DataStorage:getCacheDir()",
    function()
      local DataStorage = require("datastorage")
      assert.are.equal(DataStorage:getCacheDir() .. "/", DocCache.cache_path)
    end
  )

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

  describe("disk cache fallback", function()
    local Cache = require("cache")
    local lfs = require("libs/libkoreader-lfs")
    local util = require("util")
    local original_isDirRW = util.isDirRW
    local original_lfs_dir = lfs.dir
    local original_lfs_attributes = lfs.attributes
    local original_lfs_mkdir = lfs.mkdir
    local original_disk_cache

    before_each(function()
      original_disk_cache = DocCache.disk_cache
      package.loaded["datastorage"] = nil
    end)

    after_each(function()
      util.isDirRW = original_isDirRW
      lfs.dir = original_lfs_dir
      lfs.attributes = original_lfs_attributes
      lfs.mkdir = original_lfs_mkdir
      DocCache.disk_cache = original_disk_cache
      package.loaded["datastorage"] = nil
    end)

    it(
      "falls back to temporary cache dir when configured cache_path is not writable",
      function()
        util.isDirRW = function(dir)
          if dir == "/nonexistent/cache/" then
            return false
          end
          return true
        end

        local c = Cache:new({
          slots = 10,
          disk_cache = true,
          cache_path = "/nonexistent/cache/",
        })

        assert.is_true(c.disk_cache)
        assert.are_not.equal("/nonexistent/cache/", c.cache_path)
        assert.is_truthy(c.cache_path:find("cache"))
      end
    )

    it("disables disk cache when no writable cache dir exists", function()
      util.isDirRW = function()
        return false
      end

      local c = Cache:new({
        slots = 10,
        disk_cache = true,
        cache_path = "/nonexistent/cache/",
      })

      assert.is_false(c.disk_cache)
    end)

    it("skips serialization safely when disk_cache is disabled", function()
      DocCache.disk_cache = false
      assert.has_no_errors(function()
        DocCache:serialize()
      end)
    end)

    it("skips serialization safely when cache_path is unwritable", function()
      util.isDirRW = function(dir)
        if dir == DocCache.cache_path then
          return false
        end
        return true
      end
      assert.has_no_errors(function()
        DocCache:serialize()
      end)
    end)

    it(
      "skips refreshSnapshot when disk_cache is disabled",
      function()
        local c = Cache:new({
          slots = 10,
          disk_cache = false,
          cache_path = "/nonexistent/cache/",
        })
        c:refreshSnapshot()
        assert.is_nil(c.cached)
      end
    )

    it(
      "asserts in refreshSnapshot when disk_cache is enabled but cache_path is nil",
      function()
        local c = Cache:new({
          slots = 10,
          disk_cache = false,
        })
        c.disk_cache = true
        c.cache_path = nil
        assert.has_error(function()
          c:refreshSnapshot()
        end)
      end
    )

    it(
      "populates self.cached from existing cache even if cache_path is not writable",
      function()
        lfs.dir = function(path)
          local items = { "abc", "def" }
          local i = 0
          return function()
            i = i + 1
            return items[i]
          end
        end

        lfs.attributes = function(path, request)
          if request == "mode" then
            if path == "/readonly/cache/" then
              return "directory"
            end
            return "file"
          end
          return nil
        end

        local c = Cache:new({
          slots = 10,
          disk_cache = false,
          cache_path = "/readonly/cache/",
        })
        c.disk_cache = true
        util.isDirRW = function()
          return false
        end

        c:refreshSnapshot()
        assert.is_not_nil(c.cached)
        assert.are.equal("/readonly/cache/abc", c.cached["abc"])
        assert.are.equal("/readonly/cache/def", c.cached["def"])
      end
    )

    it(
      "creates cache directory via lfs.mkdir in refreshSnapshot if it does not exist",
      function()
        local dir_created = false
        lfs.mkdir = function(path)
          if path == "/missing/cache/" then
            dir_created = true
            return true
          end
          return nil
        end

        lfs.attributes = function(path, request)
          if request == "mode" then
            if path == "/missing/cache/" then
              return dir_created and "directory" or nil
            end
          end
          return nil
        end

        lfs.dir = function(path)
          return function() return nil end
        end

        local c = Cache:new({
          slots = 10,
          disk_cache = false,
          cache_path = "/missing/cache/",
        })
        c.disk_cache = true

        c:refreshSnapshot()
        assert.is_true(dir_created)
        assert.is_table(c.cached)
        assert.are.same({}, c.cached)
      end
    )

    it(
      "safely returns empty table in refreshSnapshot if directory does not exist and cannot be created",
      function()
        lfs.mkdir = function()
          return nil, "Permission denied"
        end

        lfs.attributes = function(path, request)
          if request == "mode" and path == "/unwritable/cache/" then
            return nil
          end
          return nil
        end

        local dir_called = false
        lfs.dir = function(path)
          dir_called = true
          error("lfs.dir should not be called on nonexistent directory")
        end

        local c = Cache:new({
          slots = 10,
          disk_cache = false,
          cache_path = "/unwritable/cache/",
        })
        c.disk_cache = true

        assert.has_no_errors(function()
          c:refreshSnapshot()
        end)
        assert.is_false(dir_called)
        assert.is_table(c.cached)
        assert.are.same({}, c.cached)
      end
    )

    it(
      "handles lfs.dir error in refreshSnapshot gracefully",
      function()
        lfs.attributes = function(path, request)
          if request == "mode" then
            return "directory"
          end
          return nil
        end

        lfs.dir = function()
          error("permission denied")
        end

        local c = Cache:new({
          slots = 10,
          disk_cache = false,
          cache_path = "/unreadable/cache/",
        })
        c.disk_cache = true

        assert.has_no_errors(function()
          c:refreshSnapshot()
        end)
        assert.is_table(c.cached)
        assert.are.same({}, c.cached)
      end
    )

    it(
      "falls back to DataStorage:getCacheDirOrNil when configured cache_path is unwritable",
      function()
        lfs.dir = function()
          return function()
            return nil
          end
        end

        package.loaded["datastorage"] = {
          getCacheDirOrNil = function()
            return "/mock/ds/cache"
          end,
        }

        util.isDirRW = function(dir)
          if dir == "/nonexistent/cache/" then
            return false
          end
          return true
        end

        local c = Cache:new({
          slots = 10,
          disk_cache = true,
          cache_path = "/nonexistent/cache/",
        })

        assert.is_true(c.disk_cache)
        assert.are.equal("/mock/ds/cache/", c.cache_path)
      end
    )
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
