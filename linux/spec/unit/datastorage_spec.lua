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
    os.getenv = original_getenv
    util.isDirRW = original_isDirRW
    package.loaded["datastorage"] = nil
  end)

  it("should return correct default paths", function()
    env_mock["KO_MULTIUSER"] = false
    env_mock["APPIMAGE"] = false
    env_mock["FLATPAK"] = false
    env_mock["UBUNTU_APPLICATION_ISOLATION"] = false
    env_mock["XDG_CONFIG_HOME"] = false
    env_mock["HOME"] = false
    DataStorage = require("datastorage")

    assert.are.equal(".", DataStorage:getDataDir())
    assert.are.equal("./history", DataStorage:getHistoryDir())
    assert.are.equal("./settings", DataStorage:getSettingsDir())
    assert.are.equal("./docsettings", DataStorage:getDocSettingsDir())
    assert.are.equal("./hashdocsettings", DataStorage:getDocSettingsHashDir())

    local full_dir = DataStorage:getFullDataDir()
    assert.truthy(full_dir)
    assert.are.equal("/", string.sub(full_dir, 1, 1))
    assert.are.equal(require("libs/libkoreader-lfs").currentdir(), full_dir)
  end)

  it(
    "should prefer XDG_CONFIG_HOME and HOME over dot even without KO_MULTIUSER",
    function()
      env_mock["KO_MULTIUSER"] = false
      env_mock["APPIMAGE"] = false
      env_mock["FLATPAK"] = false
      env_mock["UBUNTU_APPLICATION_ISOLATION"] = false
      env_mock["XDG_CONFIG_HOME"] = "/tmp/test_xdg_config"
      isDirRW_mock = function(dir)
        return dir == "/tmp/test_xdg_config/koreader"
      end

      DataStorage = require("datastorage")
      assert.are.equal(
        "/tmp/test_xdg_config/koreader",
        DataStorage:getDataDir()
      )
    end
  )

  it("should prefer HOME over dot when XDG_CONFIG_HOME is unset", function()
    env_mock["KO_MULTIUSER"] = false
    env_mock["APPIMAGE"] = false
    env_mock["FLATPAK"] = false
    env_mock["UBUNTU_APPLICATION_ISOLATION"] = false
    env_mock["XDG_CONFIG_HOME"] = false
    env_mock["HOME"] = "/home/testuser"
    isDirRW_mock = function(dir)
      return dir == "/home/testuser/.config/koreader"
    end

    DataStorage = require("datastorage")
    assert.are.equal(
      "/home/testuser/.config/koreader",
      DataStorage:getDataDir()
    )
  end)

  it(
    "should fall back to dot when XDG_CONFIG_HOME and HOME are unwritable",
    function()
      env_mock["KO_MULTIUSER"] = false
      env_mock["APPIMAGE"] = false
      env_mock["FLATPAK"] = false
      env_mock["UBUNTU_APPLICATION_ISOLATION"] = false
      env_mock["XDG_CONFIG_HOME"] = "/tmp/test_xdg_config"
      env_mock["HOME"] = "/home/testuser"
      isDirRW_mock = function(dir)
        return dir == "."
      end

      DataStorage = require("datastorage")
      assert.are.equal(".", DataStorage:getDataDir())
    end
  )

  it("should honor KO_MULTIUSER and XDG_CONFIG_HOME", function()
    env_mock["KO_MULTIUSER"] = "true"
    env_mock["XDG_CONFIG_HOME"] = "/tmp/my_xdg_config"
    isDirRW_mock = function(dir)
      return dir == "/tmp/my_xdg_config/koreader"
    end

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
    isDirRW_mock = function(dir)
      return dir == "/home/testuser/.config/koreader"
    end

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
    isDirRW_mock = function(dir)
      return dir == "/xdg/data/com.koreader.app"
    end

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

  it(
    "should fail if APP_ID is missing when UBUNTU_APPLICATION_ISOLATION is set",
    function()
      env_mock["UBUNTU_APPLICATION_ISOLATION"] = "true"
      env_mock["APP_ID"] = false
      assert.has_error(function()
        require("datastorage")
      end)
    end
  )

  it(
    "should fallback to secondary candidate if preferred is unwritable",
    function()
      env_mock["KO_MULTIUSER"] = "true"
      env_mock["XDG_CONFIG_HOME"] = "/fake/xdg"
      env_mock["HOME"] = "/fake/home"
      isDirRW_mock = function(dir)
        return dir == "/fake/home/.config/koreader"
      end

      DataStorage = require("datastorage")
      assert.are.equal("/fake/home/.config/koreader", DataStorage:getDataDir())
      assert.is_false(DataStorage:isStorageTemporary())
      assert.is_false(DataStorage:isStorageReadOnly())
    end
  )

  it(
    "should fallback to temporary storage if all standard candidates are unwritable",
    function()
      env_mock["KO_MULTIUSER"] = "true"
      env_mock["XDG_CONFIG_HOME"] = "/fake/xdg"
      env_mock["HOME"] = "/fake/home"
      env_mock["TMPDIR"] = "/fake/tmp"
      isDirRW_mock = function(dir)
        return dir == "/fake/tmp/koreader" or dir == "/fake/tmp"
      end

      DataStorage = require("datastorage")
      assert.are.equal("/fake/tmp/koreader", DataStorage:getDataDir())
      assert.is_true(DataStorage:isStorageTemporary())
      assert.is_false(DataStorage:isStorageReadOnly())
    end
  )

  it(
    "should enter read-only mode if even temporary storage is unwritable",
    function()
      env_mock["KO_MULTIUSER"] = "true"
      env_mock["XDG_CONFIG_HOME"] = "/fake/xdg"
      isDirRW_mock = function()
        return false
      end

      DataStorage = require("datastorage")
      assert.are.equal("/fake/xdg/koreader", DataStorage:getDataDir())
      assert.is_true(DataStorage:isStorageReadOnly())
      assert.is_false(DataStorage:isStorageTemporary())
    end
  )

  it("should show modal confirmation when storage is temporary", function()
    DataStorage = require("datastorage")
    DataStorage:setStorageTemporary(true)
    DataStorage:setStorageReadOnly(false)

    local UIManager = require("ui/uimanager")
    local quit_called = false
    local shown_widget = nil
    local orig_show = UIManager.show
    local orig_quit = UIManager.quit

    UIManager.show = function(_, widget)
      shown_widget = widget
    end
    UIManager.quit = function()
      quit_called = true
    end

    DataStorage:showStorageWarningIfNeeded()
    assert.is_not_nil(shown_widget)
    assert.is_truthy(shown_widget.text:find("temporary storage"))
    assert.is_truthy(shown_widget.ok_text)
    assert.is_truthy(shown_widget.cancel_text)

    -- Test cancel callback calls quit
    shown_widget.cancel_callback()
    assert.is_true(quit_called)

    UIManager.show = orig_show
    UIManager.quit = orig_quit
  end)

  it(
    "should show modal confirmation when storage is completely read-only",
    function()
      DataStorage = require("datastorage")
      DataStorage:setStorageTemporary(false)
      DataStorage:setStorageReadOnly(true)

      local UIManager = require("ui/uimanager")
      local quit_called = false
      local shown_widget = nil
      local orig_show = UIManager.show
      local orig_quit = UIManager.quit

      UIManager.show = function(_, widget)
        shown_widget = widget
      end
      UIManager.quit = function()
        quit_called = true
      end

      DataStorage:showStorageWarningIfNeeded()
      assert.is_not_nil(shown_widget)
      assert.is_truthy(shown_widget.text:find("completely read%-only"))

      shown_widget.cancel_callback()
      assert.is_true(quit_called)

      UIManager.show = orig_show
      UIManager.quit = orig_quit
    end
  )

  it("should return preferred cache dir when writable", function()
    DataStorage = require("datastorage")
    local expected = DataStorage:getDataDir() .. "/cache"
    isDirRW_mock = function(dir)
      return dir == expected or dir == DataStorage:getDataDir()
    end

    assert.are.equal(expected, DataStorage:getCacheDir())
  end)

  it(
    "should fallback to temporary cache dir when preferred cache is not writable",
    function()
      DataStorage = require("datastorage")
      env_mock["TMPDIR"] = "/tmp/mock_tmp"
      isDirRW_mock = function(dir)
        if dir == "./cache" then
          return false
        end
        if dir == "/tmp/mock_tmp" or dir == "/tmp/mock_tmp/koreader_cache" then
          return true
        end
        return dir == "."
      end

      assert.are.equal(
        "/tmp/mock_tmp/koreader_cache",
        DataStorage:getCacheDir()
      )
    end
  )

  it("should cache getCacheDir result on repeated calls", function()
    DataStorage = require("datastorage")
    local expected = DataStorage:getDataDir() .. "/cache"
    local count = 0
    isDirRW_mock = function(dir)
      if dir == expected then
        count = count + 1
        return true
      end
      return true
    end

    local first = DataStorage:getCacheDir()
    local second = DataStorage:getCacheDir()
    assert.are.equal(first, second)
    assert.are.equal(1, count)
  end)

  it(
    "should fallback getCacheDir to getTmpDir when preferred is unwritable",
    function()
      env_mock["TMPDIR"] = "/mock/tmp"
      DataStorage = require("datastorage")

      local preferred = DataStorage:getDataDir() .. "/cache"
      isDirRW_mock = function(dir)
        if dir == preferred then
          return false
        end
        if dir == "/mock/tmp" or dir == "/mock/tmp/koreader_cache" then
          return true
        end
        return dir == DataStorage:getDataDir()
      end

      assert.are.equal("/mock/tmp/koreader_cache", DataStorage:getCacheDir())
    end
  )

  it(
    "should fallback getCacheDir to preferred when even temporary fallback is unwritable",
    function()
      DataStorage = require("datastorage")
      local preferred = DataStorage:getDataDir() .. "/cache"
      isDirRW_mock = function(dir)
        if dir == DataStorage:getDataDir() then
          return true
        end
        return false
      end

      assert.are.equal(preferred, DataStorage:getCacheDir())
    end
  )

  it("should reset all cached directories and flags on reset()", function()
    DataStorage = require("datastorage")
    DataStorage:setStorageTemporary(true)
    DataStorage:setStorageReadOnly(true)
    DataStorage:getDataDir()
    DataStorage:getCacheDir()
    DataStorage:getFullDataDir()
    DataStorage:getTmpDir()

    DataStorage:reset()

    assert.is_false(DataStorage:isStorageTemporary())
    assert.is_false(DataStorage:isStorageReadOnly())
  end)

  it("should handle relative subdirectory in getFullDataDir()", function()
    env_mock["KO_MULTIUSER"] = "true"
    env_mock["XDG_CONFIG_HOME"] = "relative/config"
    isDirRW_mock = function(dir)
      return dir == "relative/config/koreader"
    end
    DataStorage = require("datastorage")

    local lfs = require("libs/libkoreader-lfs")
    local full = DataStorage:getFullDataDir()
    assert.are.equal(lfs.currentdir() .. "/relative/config/koreader", full)
    -- Verify cached return
    assert.are.equal(full, DataStorage:getFullDataDir())
  end)

  it(
    "should not show storage warning if storage is normal or already shown",
    function()
      DataStorage = require("datastorage")
      DataStorage:setStorageTemporary(false)
      DataStorage:setStorageReadOnly(false)

      local UIManager = require("ui/uimanager")
      local show_called = false
      local orig_show = UIManager.show
      UIManager.show = function()
        show_called = true
      end

      DataStorage:showStorageWarningIfNeeded()
      assert.is_false(show_called)

      -- Now trigger warning once, then verify second call is a no-op
      DataStorage:setStorageTemporary(true)
      DataStorage:showStorageWarningIfNeeded()
      assert.is_true(show_called)

      show_called = false
      DataStorage:showStorageWarningIfNeeded()
      assert.is_false(show_called)

      UIManager.show = orig_show
    end
  )

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
      end
    )

    it(
      "falls back to /tmp on Android when /data/local/tmp is unwritable",
      function()
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
