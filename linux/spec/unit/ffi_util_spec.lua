-- luacheck: ignore 122
local ffiUtil

describe("ffi/util module", function()
  setup(function()
    require("commonrequire")
    ffiUtil = require("ffi/util")
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
          elseif path == "dummy_dst" and mode == "wb" then
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
  end)

  describe("getpid()", function()
    it("returns a valid numeric process ID", function()
      local pid = ffiUtil.getpid()
      assert.is_number(pid)
      assert.is_true(pid > 0)
    end)
  end)

  describe("purgeDir()", function()
    local lfs = require("libs/libkoreader-lfs")

    it("returns nil and error without raising on missing directory", function()
      local pid = ffiUtil.getpid()
      local nonexistent = "/tmp/nonexistent_purge_dir_" .. pid
      local ok, err
      assert.has_no.errors(function()
        ok, err = ffiUtil.purgeDir(nonexistent)
      end)
      assert.is_nil(ok)
      assert.is_not_nil(err)
    end)

    it("returns nil and error without raising on unreadable directory", function()
      local pid = ffiUtil.getpid()
      local unreadable = "/tmp/unreadable_purge_dir_" .. pid
      lfs.mkdir(unreadable)
      os.execute("chmod 000 " .. unreadable)
      finally(function()
        os.execute("chmod 755 " .. unreadable)
        os.remove(unreadable)
      end)

      local ok, err
      assert.has_no.errors(function()
        ok, err = ffiUtil.purgeDir(unreadable)
      end)
      assert.is_nil(ok)
      assert.is_not_nil(err)
    end)
  end)
end)
