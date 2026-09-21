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
        local lfs = require("libs/libkoreader-lfs")
        local orig_lfs_dir = lfs.dir
        local orig_lfs_attributes = lfs.attributes

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

        lfs.dir = orig_lfs_dir
        lfs.attributes = orig_lfs_attributes
      end
    )

    it(
      "creates cache directory via lfs.mkdir in refreshSnapshot if it does not exist",
      function()
        local lfs = require("libs/libkoreader-lfs")
        local orig_lfs_dir = lfs.dir
        local orig_lfs_attributes = lfs.attributes
        local orig_lfs_mkdir = lfs.mkdir

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

        lfs.dir = orig_lfs_dir
        lfs.attributes = orig_lfs_attributes
        lfs.mkdir = orig_lfs_mkdir
      end
    )

    it(
      "safely returns empty table in refreshSnapshot if directory does not exist and cannot be created",
      function()
        local lfs = require("libs/libkoreader-lfs")
        local orig_lfs_dir = lfs.dir
        local orig_lfs_attributes = lfs.attributes
        local orig_lfs_mkdir = lfs.mkdir

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

        lfs.dir = orig_lfs_dir
        lfs.attributes = orig_lfs_attributes
        lfs.mkdir = orig_lfs_mkdir
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
