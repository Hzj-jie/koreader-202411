describe("DocCache", function()
  local DocCache
  local ffiUtil
  local lfs
  local md5
  local temp_dir
  local orig_disk_cache
  local orig_cache_path
  local orig_size

  setup(function()
    require("commonrequire")
    DocCache = require("document/doccache")
    ffiUtil = require("ffi/util")
    lfs = require("libs/libkoreader-lfs")
    md5 = require("ffi/sha2").md5

    orig_disk_cache = DocCache.disk_cache
    orig_cache_path = DocCache.cache_path
    orig_size = DocCache.size
  end)

  before_each(function()
    temp_dir = "/tmp/test_doccache_" .. ffiUtil.getpid() .. "_" .. os.time()
    lfs.mkdir(temp_dir)
    DocCache.cache_path = temp_dir .. "/"
    DocCache.cache_dir = temp_dir .. "/"
    DocCache.disk_cache = true
    DocCache.cached = DocCache:_getDiskCache()
  end)

  after_each(function()
    DocCache.disk_cache = orig_disk_cache
    DocCache.cache_path = orig_cache_path
    DocCache.size = orig_size
    DocCache:clear()

    if temp_dir and lfs.attributes(temp_dir, "mode") == "directory" then
      for file in lfs.dir(temp_dir) do
        if file ~= "." and file ~= ".." then
          os.remove(temp_dir .. "/" .. file)
        end
      end
      lfs.rmdir(temp_dir)
    end
  end)

  describe("serialize", function()
    it("should do nothing when disk_cache is false", function()
      DocCache.disk_cache = false
      DocCache:clear()
      assert.has_no_errors(function()
        DocCache:serialize("/path/to/doc.epub")
      end)
    end)

    it("should serialize displayed page item and write dumped files", function()
      local doc_path = "/tmp/test_book_" .. ffiUtil.getpid() .. ".epub"

      local dumped_file_path
      local displayed_item = {
        persistent = true,
        doc_path = doc_path,
        dump = function(_self, path)
          dumped_file_path = path
          local f = assert(io.open(path, "w"))
          f:write("page_data_123")
          f:close()
          local sf = assert(io.open(path .. ".size", "w"))
          sf:write("123")
          sf:close()
          return 123
        end,
        onFree = function() end,
      }

      local hinted_dump_called = false
      local hinted_item = {
        persistent = true,
        doc_path = doc_path,
        dump = function(_self, _path)
          hinted_dump_called = true
          return 50
        end,
        onFree = function() end,
      }

      local other_doc_dump_called = false
      local other_item = {
        persistent = true,
        doc_path = "/other/book.epub",
        dump = function(_self, _path)
          other_doc_dump_called = true
          return 50
        end,
        onFree = function() end,
      }

      local non_persistent_called = false
      local non_persistent_item = {
        persistent = false,
        doc_path = doc_path,
        dump = function(_self, _path)
          non_persistent_called = true
          return 50
        end,
        onFree = function() end,
      }

      -- Insert other items first
      DocCache.cache:set("other_key", other_item, 100)
      DocCache.cache:set("non_pers_key", non_persistent_item, 100)
      -- Insert displayed page before hinted page so hinted page is newer (MRU)
      DocCache.cache:set("displayed_key", displayed_item, 100)
      DocCache.cache:set("hinted_key", hinted_item, 100)

      DocCache:serialize(doc_path)

      assert.is_false(hinted_dump_called)
      assert.is_false(other_doc_dump_called)
      assert.is_false(non_persistent_called)
      assert.is_string(dumped_file_path)
      assert.is_not_nil(lfs.attributes(dumped_file_path, "size"))
      assert.is_not_nil(lfs.attributes(dumped_file_path .. ".size", "size"))
    end)

    it("should evict oldest access-time cache files when exceeding budget", function()
      -- Pre-create older and newer cache files
      local old_file = temp_dir .. "/old_cache_file"
      local f1 = assert(io.open(old_file, "w"))
      f1:write(string.rep("a", 100))
      f1:close()
      lfs.touch(old_file, os.time() - 200, os.time() - 200)

      local mid_file = temp_dir .. "/mid_cache_file"
      local f2 = assert(io.open(mid_file, "w"))
      f2:write(string.rep("b", 100))
      f2:close()
      lfs.touch(mid_file, os.time() - 50, os.time() - 50)

      DocCache.cached = DocCache:_getDiskCache()
      DocCache.size = 150

      local doc_path = "/tmp/evict_book_" .. ffiUtil.getpid() .. ".epub"
      local item1 = {
        persistent = true,
        doc_path = doc_path,
        dump = function(_self, path)
          local f = assert(io.open(path, "w"))
          f:write(string.rep("c", 60))
          f:close()
          return 60
        end,
        onFree = function() end,
      }
      local item_hinted = {
        persistent = true,
        doc_path = doc_path,
        dump = function()
          return 10
        end,
        onFree = function() end,
      }
      DocCache.cache:set("evict_disp", item1, 60)
      DocCache.cache:set("evict_hint", item_hinted, 10)

      DocCache:serialize(doc_path)

      assert.is_nil(lfs.attributes(old_file))
      assert.is_nil(lfs.attributes(mid_file))

      local dumped_path = temp_dir .. "/" .. md5("evict_disp")
      assert.is_not_nil(lfs.attributes(dumped_path))
    end)

    it("should refresh disk cache snapshot via refreshSnapshot", function()
      local dummy_file = temp_dir .. "/snapshot_test"
      local f = assert(io.open(dummy_file, "w"))
      f:write("snapshot")
      f:close()

      DocCache:refreshSnapshot()
      assert.are.equal(dummy_file, DocCache.cached["snapshot_test"])

      os.remove(dummy_file)
      DocCache:refreshSnapshot()
      assert.is_nil(DocCache.cached["snapshot_test"])
    end)
  end)
end)
