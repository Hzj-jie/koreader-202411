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

  describe("disk cache fallback", function()
    local Cache = require("cache")
    local util = require("util")
    local original_isDirRW = util.isDirRW

    before_each(function()
      require("datastorage"):reset()
    end)

    after_each(function()
      util.isDirRW = original_isDirRW
      local ds = package.loaded["datastorage"]
      if ds and ds.reset then
        ds:reset()
      end
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
      local orig_disk_cache = DocCache.disk_cache
      DocCache.disk_cache = false
      assert.has_no_errors(function()
        DocCache:serialize()
      end)
      DocCache.disk_cache = orig_disk_cache
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
      "returns empty table in _getDiskCache when cache_path is unwritable",
      function()
        local c = Cache:new({
          slots = 10,
          disk_cache = false,
          cache_path = "/nonexistent/cache/",
        })
        util.isDirRW = function()
          return false
        end
        local cached = c:_getDiskCache()
        assert.is_table(cached)
        assert.are.same({}, cached)
      end
    )

    it(
      "falls back to DataStorage:getCacheDirOrNil when configured cache_path is unwritable",
      function()
        local lfs = require("libs/libkoreader-lfs")
        local orig_lfs_dir = lfs.dir
        lfs.dir = function()
          return function()
            return nil
          end
        end

        local orig_ds = package.loaded["datastorage"]
        package.loaded["datastorage"] = {
          getCacheDirOrNil = function()
            return "/mock/ds/cache"
          end,
          reset = function() end,
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

        lfs.dir = orig_lfs_dir
        package.loaded["datastorage"] = orig_ds
      end
    )
  end)
end)
