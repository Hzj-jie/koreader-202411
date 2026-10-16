local FFIUtil = require("ffi/util")
local util = require("util")

describe("Android device", function()
  local Device
  local mock_android

  setup(function()
    require("commonrequire")

    mock_android = {
      app = {
        activity = {
          sdkVersion = 30,
        },
        config = {},
      },
      lib = {
        AConfiguration_getDensity = function()
          return 440
        end,
      },
      prop = {
        product = "Pixel 6",
        version = "12",
        flavor = "fdroid",
      },
      LOGI = function() end,
      isColorScreen = function()
        return true
      end,
      hasLights = function()
        return true
      end,
      isWarmthDevice = function()
        return false
      end,
      isEink = function()
        return false
      end,
      isPackageEnabled = function()
        return true
      end,
      isFullscreen = function()
        return true
      end,
      setFullscreen = function() end,
      getScreenWidth = function()
        return 1080
      end,
      getScreenHeight = function()
        return 1920
      end,
      getStatusBarHeight = function()
        return 80
      end,
      isPathInsideSandbox = function()
        return false
      end,
      getExternalStoragePath = function()
        return "/storage/emulated/0"
      end,
      lights = {
        showDialog = function() end,
      },
    }

    package.loaded["android"] = mock_android
    package.loaded["device/android/device"] = nil
    Device = require("device/android/device")
  end)

  before_each(function()
    mock_android.isPathInsideSandbox = function()
      return false
    end
    mock_android.getExternalStoragePath = function()
      return "/storage/emulated/0"
    end
  end)

  describe("Device properties and capabilities", function()
    it("should report basic Android device properties", function()
      assert.is_true(Device:isAndroid())
      assert.are.equal("Pixel 6", Device.model)
      assert.is_true(Device:hasKeys())
      assert.is_false(Device:hasDPad())
      assert.is_false(Device:hasSeamlessWifiToggle())
      assert.is_false(Device:hasExitOptions())
    end)
  end)

  describe("Path validation", function()
    it("should allow paths inside sandbox", function()
      mock_android.isPathInsideSandbox = function(p)
        return p == "/data/data/org.koreader/files/test.epub"
      end
      assert.is_true(
        Device:isValidPath("/data/data/org.koreader/files/test.epub")
      )
    end)

    it("should allow valid paths under external storage", function()
      local orig_realpath = FFIUtil.realpath
      FFIUtil.realpath = function(p)
        return p
      end
      finally(function()
        FFIUtil.realpath = orig_realpath
      end)

      assert.is_true(Device:isValidPath("/storage/emulated/0/Books/novel.epub"))
    end)
  end)

  describe("Defect verifications", function()
    it("isValidPath prevents sibling directory prefix escape", function()
      -- External storage is "/storage/emulated/0"
      -- Sibling path is "/storage/emulated/00/secret.epub"
      -- Ensure boundary check prevents escape into sibling directories.
      local orig_realpath = FFIUtil.realpath
      FFIUtil.realpath = function(p)
        return p
      end
      finally(function()
        FFIUtil.realpath = orig_realpath
      end)

      local is_valid = Device:isValidPath("/storage/emulated/00/secret.epub")
      assert.is_false(
        is_valid,
        "Expected sibling prefix directory '/storage/emulated/00' to be rejected"
      )
    end)
  end)
end)
