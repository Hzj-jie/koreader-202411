describe("QuickStart module", function()
  setup(function()
    require("commonrequire")
  end)
  it(
    "should return false shown_version lower than force_show_version",
    function()
      G_reader_settings:save("quickstart_shown_version", 1)
      G_reader_settings:flush()
      local QuickStart = require("ui/quickstart")
      QuickStart.quickstart_force_show_version = 2
      assert.is_false(QuickStart:isShown())
    end
  )
  it(
    "should return true when shown_version equal to force_show_version",
    function()
      G_reader_settings:save("quickstart_shown_version", 1)
      G_reader_settings:flush()
      local QuickStart = require("ui/quickstart")
      QuickStart.quickstart_force_show_version = 1
      assert.is_true(QuickStart:isShown())
    end
  )
  it(
    "should return true when shown_version higher than force_show_version",
    function()
      G_reader_settings:save("quickstart_shown_version", 2)
      G_reader_settings:flush()
      local QuickStart = require("ui/quickstart")
      QuickStart.quickstart_force_show_version = 1
      assert.is_true(QuickStart:isShown())
    end
  )
  it("should return a proper quickstart filename", function()
    local DataStorage = require("datastorage")
    local QuickStart = require("ui/quickstart")
    local Version = require("version")
    local language = "en"
    local rev = Version:getCurrentRevision()
    local quickstart_dir =
      string.format("%s%s", DataStorage:getDataDir(), "/help")
    local expected_quickstart_filename = ("%s/quickstart-%s-%s.html"):format(
      quickstart_dir,
      language,
      rev
    )
    assert.is.same(expected_quickstart_filename, QuickStart:getQuickStart())
  end)

  it("generates quickstart guide for RTL and various device input capabilities", function()
    local Device = require("device")
    local stub = require("luassert.stub")

    -- Test RTL language
    G_reader_settings:save("language", "ar")
    package.loaded["ui/quickstart"] = nil
    local QuickStart = require("ui/quickstart")
    local fn_rtl = QuickStart:getQuickStart()
    assert.is_string(fn_rtl)

    -- Test ScreenKB device
    local screenkb_stub = stub(Device, "hasScreenKB", function() return true end)
    package.loaded["ui/quickstart"] = nil
    QuickStart = require("ui/quickstart")
    local fn_screenkb = QuickStart:getQuickStart()
    assert.is_string(fn_screenkb)
    screenkb_stub:revert()

    -- Test SymKey device
    local symkey_stub = stub(Device, "hasSymKey", function() return true end)
    package.loaded["ui/quickstart"] = nil
    QuickStart = require("ui/quickstart")
    local fn_symkey = QuickStart:getQuickStart()
    assert.is_string(fn_symkey)
    symkey_stub:revert()

    -- Reset language
    G_reader_settings:save("language", "en")
  end)
end)
