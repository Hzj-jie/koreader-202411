-- luacheck: ignore 122
local ffiUtil
local lfs

describe("ffi/util module", function()
  setup(function()
    require("commonrequire")
    ffiUtil = require("ffi/util")
    lfs = require("libs/libkoreader-lfs")
  end)

  describe("joinPath()", function()
    it("joins relative paths with directory separators", function()
      assert.are.equal("/a/b/c", ffiUtil.joinPath("/a/b", "c"))
      assert.are.equal("/a/b/c", ffiUtil.joinPath("/a/b/", "c"))
    end)

    it(
      "returns absolute path2 directly when path2 starts with slash",
      function()
        assert.are.equal(
          "/absolute/target",
          ffiUtil.joinPath("/some/dir", "/absolute/target")
        )
      end
    )
  end)

  describe("copyFile()", function()
    local orig_io_open

    setup(function()
      orig_io_open = io.open
    end)

    teardown(function()
      io.open = orig_io_open
    end)

    it("copies file contents between valid paths", function()
      local pid = ffiUtil.getpid()
      local src = "/tmp/koreader_test_copy_" .. pid .. "_src.txt"
      local dst = "/tmp/koreader_test_copy_" .. pid .. "_dst.txt"
      finally(function()
        os.remove(src)
        os.remove(dst)
      end)

      local f = io.open(src, "wb")
      f:write("hello ffiUtil copy")
      f:close()

      local err = ffiUtil.copyFile(src, dst)
      assert.is_nil(err)

      local f_dst = io.open(dst, "rb")
      local content = f_dst:read("*all")
      f_dst:close()
      assert.are.equal("hello ffiUtil copy", content)
    end)

    it(
      "closes source file handle when destination file cannot be opened",
      function()
        local source_closed = false
        io.open = function(path, mode)
          if path == "dummy_src" and mode == "rb" then
            return {
              read = function()
                return nil
              end,
              close = function()
                source_closed = true
              end,
            }
          elseif (path == "dummy_dst" or path == "dummy_dst.new") and mode == "wb" then
            return nil, "Permission denied"
          end
          return orig_io_open(path, mode)
        end

        local err = ffiUtil.copyFile("dummy_src", "dummy_dst")
        io.open = orig_io_open
        assert.are.equal("Permission denied", err)
        assert.is_true(source_closed)
      end
    )

    it("cleans up .new and preserves original destination when write fails", function()
      local pid = ffiUtil.getpid()
      local src = "/tmp/koreader_test_copy_wfail_" .. pid .. "_src.txt"
      local dst = "/tmp/koreader_test_copy_wfail_" .. pid .. "_dst.txt"
      local new_dst = dst .. ".new"
      finally(function()
        os.remove(src)
        os.remove(dst)
        os.remove(new_dst)
      end)

      local f_src = io.open(src, "wb")
      f_src:write("source data")
      f_src:close()

      local f_dst = io.open(dst, "wb")
      f_dst:write("old destination")
      f_dst:close()

      io.open = function(path, mode)
        if path == new_dst then
          local real = orig_io_open(path, mode)
          return {
            write = function() return nil, "disk full" end,
            close = function() if real then real:close() end return true end,
          }
        end
        return orig_io_open(path, mode)
      end

      local err = ffiUtil.copyFile(src, dst)
      io.open = orig_io_open

      assert.same("disk full", err)
      assert.is_nil(lfs.attributes(new_dst))
      local f_check = io.open(dst, "rb")
      local content = f_check:read("*all")
      f_check:close()
      assert.same("old destination", content)
    end)

    it("cleans up .new and preserves original destination when fsync fails", function()
      local pid = ffiUtil.getpid()
      local src = "/tmp/koreader_test_copy_sfail_" .. pid .. "_src.txt"
      local dst = "/tmp/koreader_test_copy_sfail_" .. pid .. "_dst.txt"
      local new_dst = dst .. ".new"
      finally(function()
        os.remove(src)
        os.remove(dst)
        os.remove(new_dst)
      end)

      local f_src = io.open(src, "wb")
      f_src:write("source data")
      f_src:close()

      local f_dst = io.open(dst, "wb")
      f_dst:write("old destination")
      f_dst:close()

      local orig_fsync = ffiUtil.fsyncOpenedFile
      ffiUtil.fsyncOpenedFile = function() return false, "sync error" end

      local err = ffiUtil.copyFile(src, dst)
      ffiUtil.fsyncOpenedFile = orig_fsync

      assert.same("sync error", err)
      assert.is_nil(lfs.attributes(new_dst))
      local f_check = io.open(dst, "rb")
      local content = f_check:read("*all")
      f_check:close()
      assert.same("old destination", content)
    end)

    it("cleans up .new and preserves original destination when close fails", function()
      local pid = ffiUtil.getpid()
      local src = "/tmp/koreader_test_copy_cfail_" .. pid .. "_src.txt"
      local dst = "/tmp/koreader_test_copy_cfail_" .. pid .. "_dst.txt"
      local new_dst = dst .. ".new"
      finally(function()
        os.remove(src)
        os.remove(dst)
        os.remove(new_dst)
      end)

      local f_src = io.open(src, "wb")
      f_src:write("source data")
      f_src:close()

      local f_dst = io.open(dst, "wb")
      f_dst:write("old destination")
      f_dst:close()

      local orig_fsync = ffiUtil.fsyncOpenedFile
      ffiUtil.fsyncOpenedFile = function() return true end

      io.open = function(path, mode)
        if path == new_dst then
          local real = orig_io_open(path, mode)
          return {
            write = function(self, d) return real:write(d) end,
            close = function()
              if real then real:close() end
              return nil, "close failed"
            end,
          }
        end
        return orig_io_open(path, mode)
      end

      local err = ffiUtil.copyFile(src, dst)
      io.open = orig_io_open
      ffiUtil.fsyncOpenedFile = orig_fsync

      assert.same("close failed", err)
      assert.is_nil(lfs.attributes(new_dst))
      local f_check = io.open(dst, "rb")
      local content = f_check:read("*all")
      f_check:close()
      assert.same("old destination", content)
    end)

    it("cleans up .new and preserves original destination when rename fails", function()
      local pid = ffiUtil.getpid()
      local src = "/tmp/koreader_test_copy_rfail_" .. pid .. "_src.txt"
      local dst = "/tmp/koreader_test_copy_rfail_" .. pid .. "_dst.txt"
      local new_dst = dst .. ".new"
      finally(function()
        os.remove(src)
        os.remove(dst)
        os.remove(new_dst)
      end)

      local f_src = io.open(src, "wb")
      f_src:write("source data")
      f_src:close()

      local f_dst = io.open(dst, "wb")
      f_dst:write("old destination")
      f_dst:close()

      local orig_rename = os.rename
      os.rename = function(from, to)
        if from == new_dst then
          return nil, "rename failed"
        end
        return orig_rename(from, to)
      end

      local err = ffiUtil.copyFile(src, dst)
      os.rename = orig_rename

      assert.same("rename failed", err)
      assert.is_nil(lfs.attributes(new_dst))
      local f_check = io.open(dst, "rb")
      local content = f_check:read("*all")
      f_check:close()
      assert.same("old destination", content)
    end)
  end)

  describe("getpid()", function()
    it("returns a valid numeric process ID", function()
      local pid = ffiUtil.getpid()
      assert.is_number(pid)
      assert.is_true(pid > 0)
    end)
  end)
end)
