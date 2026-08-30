-- luacheck: ignore 122

describe("FontSettings element", function()
  local FontSettings
  local Device
  local UIManager
  local util

  setup(function()
    require("commonrequire")
    FontSettings = require("ui/elements/font_settings")
    Device = require("device")
    UIManager = require("ui/uimanager")
    util = require("util")
  end)

  local orig_home_dir
  local orig_jit_os

  before_each(function()
    orig_home_dir = Device.home_dir
    orig_jit_os = jit.os

    G_reader_settings:save("system_fonts", nil)
  end)

  after_each(function()
    Device.home_dir = orig_home_dir
    jit.os = orig_jit_os

    G_reader_settings:save("system_fonts", nil)
  end)

  describe("getPath and getDir across platforms", function()
    local function resetDeviceStubs()
      if Device.isAndroid.revert then
        Device.isAndroid:revert()
      end
      if Device.isPocketBook.revert then
        Device.isPocketBook:revert()
      end
      if Device.isRemarkable.revert then
        Device.isRemarkable:revert()
      end
      if Device.isDesktop.revert then
        Device.isDesktop:revert()
      end
    end

    before_each(function()
      stub(Device, "isAndroid")
      stub(Device, "isPocketBook")
      stub(Device, "isRemarkable")
      stub(Device, "isDesktop")

      Device.isAndroid.returns(false)
      Device.isPocketBook.returns(false)
      Device.isRemarkable.returns(false)
      Device.isDesktop.returns(false)
    end)

    after_each(function()
      resetDeviceStubs()
    end)

    it("should handle Desktop Linux without XDG_DATA_HOME", function()
      Device.isDesktop.returns(true)
      Device.home_dir = "/home/testuser"
      jit.os = "Linux"

      -- System fonts disabled
      assert.are.equal(
        "/home/testuser/.local/share/fonts",
        FontSettings:getPath()
      )

      -- System fonts enabled
      G_reader_settings:save("system_fonts", true)
      assert.are.equal(
        "/home/testuser/.local/share/fonts;/usr/share/fonts",
        FontSettings:getPath()
      )
    end)

    it("should handle Desktop Linux with XDG_DATA_HOME", function()
      Device.isDesktop.returns(true)
      Device.home_dir = "/home/testuser"
      jit.os = "Linux"

      local orig_getenv = os.getenv
      os.getenv = function(var)
        if var == "XDG_DATA_HOME" then
          return "/custom/xdg/data"
        end
        return orig_getenv(var)
      end

      -- System fonts disabled
      assert.are.equal("/custom/xdg/data/fonts", FontSettings:getPath())

      -- System fonts enabled
      G_reader_settings:save("system_fonts", true)
      assert.are.equal(
        "/custom/xdg/data/fonts;/usr/share/fonts",
        FontSettings:getPath()
      )

      os.getenv = orig_getenv
    end)

    it("should handle Desktop OSX", function()
      Device.isDesktop.returns(true)
      Device.home_dir = "/Users/testuser"
      jit.os = "OSX"

      -- System fonts disabled
      assert.are.equal("/Users/testuser/Library/fonts", FontSettings:getPath())

      -- System fonts enabled
      G_reader_settings:save("system_fonts", true)
      assert.are.equal(
        "/Users/testuser/Library/fonts;/Library/fonts",
        FontSettings:getPath()
      )
    end)

    it("should handle Android device", function()
      Device.isAndroid.returns(true)
      Device.home_dir = "/sdcard/koreader"

      -- System fonts disabled
      assert.are.equal(
        "/sdcard/koreader/fonts;/sdcard/koreader/koreader/fonts",
        FontSettings:getPath()
      )

      -- System fonts enabled
      G_reader_settings:save("system_fonts", true)
      assert.are.equal(
        "/sdcard/koreader/fonts;/sdcard/koreader/koreader/fonts;/system/fonts",
        FontSettings:getPath()
      )
    end)

    it("should handle PocketBook device", function()
      Device.isPocketBook.returns(true)
      Device.home_dir = "/mnt/ext1"

      -- System fonts disabled
      assert.are.equal("/mnt/ext1/system/fonts", FontSettings:getPath())

      -- System fonts enabled
      G_reader_settings:save("system_fonts", true)
      assert.are.equal(
        "/mnt/ext1/system/fonts;/ebrmain/adobefonts;/ebrmain/fonts",
        FontSettings:getPath()
      )
    end)

    it("should handle Remarkable device", function()
      Device.isRemarkable.returns(true)
      Device.home_dir = "/home/root"

      -- System fonts disabled
      assert.are.equal("/home/root/.local/share/fonts", FontSettings:getPath())

      -- System fonts enabled
      G_reader_settings:save("system_fonts", true)
      assert.are.equal(
        "/home/root/.local/share/fonts;/usr/share/fonts",
        FontSettings:getPath()
      )
    end)

    it("should return nil or system path when home_dir is missing", function()
      Device.isAndroid.returns(true)
      Device.home_dir = false

      -- System fonts disabled -> user path is nil -> returns nil
      assert.is_nil(FontSettings:getPath())

      -- System fonts enabled -> user path is nil, system path exists -> returns system path
      G_reader_settings:save("system_fonts", true)
      assert.are.equal("/system/fonts", FontSettings:getPath())
    end)

    it("should return nil for unsupported devices", function()
      Device.home_dir = "/mnt/onboard"

      assert.is_nil(FontSettings:getPath())

      G_reader_settings:save("system_fonts", true)
      assert.is_nil(FontSettings:getPath())
    end)
  end)

  describe("getSystemFontMenuItems", function()
    before_each(function()
      stub(Device, "isDesktop")
    end)

    after_each(function()
      if Device.isDesktop.revert then
        Device.isDesktop:revert()
      end
    end)

    it(
      "should return 1 menu item on non-desktop and handle toggle callback",
      function()
        Device.isDesktop.returns(false)
        stub(UIManager, "askForRestart")

        local items = FontSettings:getSystemFontMenuItems()
        assert.are.equal(1, #items)

        -- Test checked_func
        G_reader_settings:save("system_fonts", false)
        assert.is_false(items[1].checked_func())

        G_reader_settings:save("system_fonts", true)
        assert.is_true(items[1].checked_func())

        -- Test callback (toggles setting and requests restart)
        G_reader_settings:save("system_fonts", false)
        items[1].callback()
        assert.is_true(G_reader_settings:isTrue("system_fonts"))
        assert.stub(UIManager.askForRestart).was.called(1)

        items[1].callback()
        assert.is_false(G_reader_settings:isTrue("system_fonts"))
        assert.stub(UIManager.askForRestart).was.called(2)

        UIManager.askForRestart:revert()
      end
    )

    it("should return 2 menu items on desktop including openFontDir", function()
      Device.isDesktop.returns(true)

      local items = FontSettings:getSystemFontMenuItems()
      assert.are.equal(2, #items)
      assert.is_true(items[2].keep_menu_open)
      assert.is_function(items[2].callback)
    end)

    it(
      "should handle openFontDir callback when link cannot be opened",
      function()
        Device.isDesktop.returns(true)
        stub(Device, "canOpenLink")
        stub(Device, "openLink")
        stub(util, "pathExists")
        stub(util, "makePath")

        Device.canOpenLink.returns(false)

        local items = FontSettings:getSystemFontMenuItems()
        items[2].callback()

        assert.stub(util.pathExists).was.called(0)
        assert.stub(util.makePath).was.called(0)
        assert.stub(Device.openLink).was.called(0)

        Device.canOpenLink:revert()
        Device.openLink:revert()
        util.pathExists:revert()
        util.makePath:revert()
      end
    )

    it("should handle openFontDir callback when folder exists", function()
      Device.isDesktop.returns(true)
      Device.home_dir = "/home/testuser"
      jit.os = "Linux"

      stub(Device, "canOpenLink")
      stub(Device, "openLink")
      stub(util, "pathExists")
      stub(util, "makePath")

      Device.canOpenLink.returns(true)
      util.pathExists.returns(true)

      local items = FontSettings:getSystemFontMenuItems()
      items[2].callback()

      assert
        .stub(util.pathExists).was
        .called_with("/home/testuser/.local/share/fonts")
      assert.stub(util.makePath).was.called(0)
      assert
        .stub(Device.openLink).was
        .called_with(Device, "/home/testuser/.local/share/fonts")

      Device.canOpenLink:revert()
      Device.openLink:revert()
      util.pathExists:revert()
      util.makePath:revert()
    end)

    it(
      "should handle openFontDir callback when creating folder succeeds",
      function()
        Device.isDesktop.returns(true)
        Device.home_dir = "/home/testuser"
        jit.os = "Linux"

        stub(Device, "canOpenLink")
        stub(Device, "openLink")
        stub(util, "pathExists")
        stub(util, "makePath")

        Device.canOpenLink.returns(true)
        util.pathExists.returns(false)
        util.makePath.returns(true)

        local items = FontSettings:getSystemFontMenuItems()
        items[2].callback()

        assert
          .stub(util.makePath).was
          .called_with("/home/testuser/.local/share/fonts")
        assert
          .stub(Device.openLink).was
          .called_with(Device, "/home/testuser/.local/share/fonts")

        Device.canOpenLink:revert()
        Device.openLink:revert()
        util.pathExists:revert()
        util.makePath:revert()
      end
    )

    it(
      "should handle openFontDir callback when creating folder fails",
      function()
        Device.isDesktop.returns(true)
        Device.home_dir = "/home/testuser"
        jit.os = "Linux"

        stub(Device, "canOpenLink")
        stub(Device, "openLink")
        stub(util, "pathExists")
        stub(util, "makePath")

        Device.canOpenLink.returns(true)
        util.pathExists.returns(false)
        util.makePath.returns(false)

        local items = FontSettings:getSystemFontMenuItems()
        items[2].callback()

        assert
          .stub(util.makePath).was
          .called_with("/home/testuser/.local/share/fonts")
        assert.stub(Device.openLink).was.called(0)

        Device.canOpenLink:revert()
        Device.openLink:revert()
        util.pathExists:revert()
        util.makePath:revert()
      end
    )
  end)
end)
