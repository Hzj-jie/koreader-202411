describe("DataStorage module", function()
  local DataStorage
  local original_getenv = os.getenv
  local env_mock = {}
  local util = require("util")
  local original_isDirRW = util.isDirRW
  local isDirRW_mock

  setup(function()
    require("commonrequire")
  end)

  before_each(function()
    package.loaded["datastorage"] = nil
    env_mock = {}
    isDirRW_mock = nil
    os.getenv = function(var)
      if env_mock[var] ~= nil then
        if env_mock[var] == false then
          return nil
        end
        return env_mock[var]
      end
      return original_getenv(var)
    end
    util.isDirRW = function(dir, create)
      if isDirRW_mock ~= nil then
        if type(isDirRW_mock) == "function" then
          return isDirRW_mock(dir, create)
        end
        return isDirRW_mock
      end
      return original_isDirRW(dir, create)
    end
  end)

  after_each(function()
    util.isDirRW = original_isDirRW
    os.getenv = original_getenv
    package.loaded["datastorage"] = nil
  end)

  it("should return correct default paths", function()
    env_mock["KO_MULTIUSER"] = false
    env_mock["APPIMAGE"] = false
    env_mock["FLATPAK"] = false
    env_mock["UBUNTU_APPLICATION_ISOLATION"] = false
    DataStorage = require("datastorage")

    assert.are.equal(".", DataStorage:getDataDir())
    assert.are.equal("./history", DataStorage:getHistoryDir())
    assert.are.equal("./settings", DataStorage:getSettingsDir())
    assert.are.equal("./docsettings", DataStorage:getDocSettingsDir())
    assert.are.equal("./hashdocsettings", DataStorage:getDocSettingsHashDir())

    local full_dir = DataStorage:getFullDataDir()
    assert.truthy(full_dir)
    assert.are.equal("/", string.sub(full_dir, 1, 1))
  end)

  it("should honor KO_MULTIUSER and XDG_CONFIG_HOME", function()
    env_mock["KO_MULTIUSER"] = "true"
    env_mock["XDG_CONFIG_HOME"] = "/tmp/my_xdg_config"

    local lfs = require("libs/libkoreader-lfs")
    local original_mkdir = lfs.mkdir
    local original_attributes = lfs.attributes

    lfs.mkdir = function()
      return true
    end
    lfs.attributes = function(path, mode)
      if
        path == "/tmp/my_xdg_config" or path == "/tmp/my_xdg_config/koreader"
      then
        return "directory"
      end
      return original_attributes(path, mode)
    end

    DataStorage = require("datastorage")
    assert.are.equal("/tmp/my_xdg_config/koreader", DataStorage:getDataDir())

    lfs.mkdir = original_mkdir
    lfs.attributes = original_attributes
  end)

  it("should honor KO_MULTIUSER and fallback to HOME", function()
    env_mock["KO_MULTIUSER"] = "true"
    env_mock["XDG_CONFIG_HOME"] = false
    env_mock["HOME"] = "/home/testuser"

    local lfs = require("libs/libkoreader-lfs")
    local original_mkdir = lfs.mkdir
    local original_attributes = lfs.attributes

    lfs.mkdir = function()
      return true
    end
    lfs.attributes = function(path, mode)
      if
        path == "/home/testuser/.config"
        or path == "/home/testuser/.config/koreader"
      then
        return "directory"
      end
      return original_attributes(path, mode)
    end

    DataStorage = require("datastorage")
    assert.are.equal(
      "/home/testuser/.config/koreader",
      DataStorage:getDataDir()
    )

    lfs.mkdir = original_mkdir
    lfs.attributes = original_attributes
  end)

  it("should honor UBUNTU_APPLICATION_ISOLATION", function()
    env_mock["UBUNTU_APPLICATION_ISOLATION"] = "true"
    env_mock["APP_ID"] = "com.koreader.app_12345"
    env_mock["XDG_DATA_HOME"] = "/xdg/data"

    local lfs = require("libs/libkoreader-lfs")
    local original_mkdir = lfs.mkdir
    local original_attributes = lfs.attributes

    lfs.mkdir = function()
      return true
    end
    lfs.attributes = function(path, mode)
      if path == "/xdg/data/com.koreader.app" then
        return "directory"
      end
      return original_attributes(path, mode)
    end

    DataStorage = require("datastorage")
    assert.are.equal("/xdg/data/com.koreader.app", DataStorage:getDataDir())

    lfs.mkdir = original_mkdir
    lfs.attributes = original_attributes
  end)

  describe("getTmpDir()", function()
    it("returns tmp directory string", function()
      DataStorage = require("datastorage")
      local tmp = DataStorage:getTmpDir()
      assert.is_string(tmp)
      assert.is_true(#tmp > 0)
    end)

    it("respects TMPDIR environment variable if present", function()
      env_mock["TMPDIR"] = "/custom/env/tmp"
      isDirRW_mock = function(dir)
        return dir == "/custom/env/tmp"
      end
      DataStorage = require("datastorage")
      assert.are.equal("/custom/env/tmp", DataStorage:getTmpDir())
    end)

    it("falls back to /tmp when TMPDIR is unset or unwritable", function()
      env_mock["TMPDIR"] = "/unwritable/tmp"
      isDirRW_mock = function(dir)
        return dir == "/tmp"
      end
      DataStorage = require("datastorage")
      assert.are.equal("/tmp", DataStorage:getTmpDir())
    end)

    it("caches result on subsequent calls", function()
      DataStorage = require("datastorage")
      local first = DataStorage:getTmpDir()
      local second = DataStorage:getTmpDir()
      assert.are.equal(first, second)
    end)

    it("clears cached tmp_dir on reset()", function()
      env_mock["TMPDIR"] = "/first/tmp"
      isDirRW_mock = function(dir)
        return dir == "/first/tmp" or dir == "/second/tmp"
      end
      DataStorage = require("datastorage")
      assert.are.equal("/first/tmp", DataStorage:getTmpDir())

      DataStorage:reset()
      env_mock["TMPDIR"] = "/second/tmp"
      assert.are.equal("/second/tmp", DataStorage:getTmpDir())
    end)

    it(
      "falls back to /data/local/tmp on Android when TMPDIR is unset",
      function()
        local lfs = require("libs/libkoreader-lfs")
        local orig_mkdir = lfs.mkdir
        local orig_attrs = lfs.attributes
        lfs.mkdir = function()
          return true
        end
        lfs.attributes = function()
          return "directory"
        end
        package.loaded["android"] = {
          getExternalStoragePath = function()
            return "/sdcard"
          end,
        }
        package.loaded["datastorage"] = nil
        env_mock["TMPDIR"] = false
        isDirRW_mock = function(dir)
          return dir == "/data/local/tmp"
        end
        DataStorage = require("datastorage")
        assert.are.equal("/data/local/tmp", DataStorage:getTmpDir())
        package.loaded["android"] = nil
        lfs.mkdir = orig_mkdir
        lfs.attributes = orig_attrs
      end
    )

    it(
      "falls back to /tmp on Android when /data/local/tmp is unwritable",
      function()
        local lfs = require("libs/libkoreader-lfs")
        local orig_mkdir = lfs.mkdir
        local orig_attrs = lfs.attributes
        lfs.mkdir = function()
          return true
        end
        lfs.attributes = function()
          return "directory"
        end
        package.loaded["android"] = {
          getExternalStoragePath = function()
            return "/sdcard"
          end,
        }
        package.loaded["datastorage"] = nil
        env_mock["TMPDIR"] = false
        isDirRW_mock = function(dir)
          return dir == "/tmp"
        end
        DataStorage = require("datastorage")
        assert.are.equal("/tmp", DataStorage:getTmpDir())
        package.loaded["android"] = nil
        lfs.mkdir = orig_mkdir
        lfs.attributes = orig_attrs
      end
    )

    it(
      "returns nil when no candidate temporary directory is writable",
      function()
        env_mock["TMPDIR"] = false
        isDirRW_mock = function()
          return false
        end
        DataStorage = require("datastorage")
        assert.is_nil(DataStorage:getTmpDir())
      end
    )
  end)
end)
