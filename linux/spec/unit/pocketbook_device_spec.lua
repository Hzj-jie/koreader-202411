-- luacheck: ignore 122
local ffi = require("ffi")
local orig_load = ffi.load
local version_c = ffi.new("char[16]", "U632.5.19.832")
local model_c = ffi.new("char[16]", "PB632")
local sleepmode_val = nil
local poweroff_called = false

local mock_inkview = {
  SetSubtaskInfo = function() end,
  GetCurrentTask = function()
    return 1
  end,
  iv_sleepmode = function(mode)
    sleepmode_val = mode
  end,
  PowerOff = function()
    poweroff_called = true
  end,
  GetSoftwareVersion = function()
    return version_c
  end,
  GetDeviceModel = function()
    return model_c
  end,
}

ffi.load = function(name, global)
  if name == "inkview" then
    return mock_inkview
  end
  return orig_load(name, global)
end

require("commonrequire")
package.loaded["device/pocketbook/device"] = nil
local PocketBook = require("device/pocketbook/device")

describe("PocketBook device", function()
  teardown(function()
    ffi.load = orig_load
  end)

  describe("properties and hardware queries", function()
    it("reports correct model and platform capabilities for PB632", function()
      assert.are.equal("PBTouchHDPlus", PocketBook.model)
      assert.is_true(PocketBook:isPocketBook())
      assert.is_true(PocketBook:canAssociateFileExtensions())
      assert.are.equal(
        "/mnt/ext1/system/logo/offlogo/cover.bmp",
        PocketBook:getDefaultCoverPath()
      )
      assert.are.equal("U632.5.19.832", PocketBook:getSoftwareVersion())
      assert.are.equal("PB632", PocketBook:getDeviceModel())
    end)

    it("handles auto standby and power off via inkview calls", function()
      sleepmode_val = nil
      PocketBook:setAutoStandby(true)
      assert.are.equal(1, sleepmode_val)

      PocketBook:setAutoStandby(false)
      assert.are.equal(0, sleepmode_val)

      poweroff_called = false
      PocketBook:powerOff()
      assert.is_true(poweroff_called)
    end)
  end)

  describe("associateFileExtensions", function()
    local orig_lines = io.lines
    local orig_open = io.open
    local written_files = {}

    before_each(function()
      written_files = {}
      io.lines = function(path)
        if path == "/ebrmain/config/extensions.cfg" then
          local lines = {
            "epub:application/epub+zip:1:viewer.app:ICON_EPUB",
            "pdf:application/pdf:1:pdfviewer.app:ICON_PDF",
          }
          local i = 0
          return function()
            i = i + 1
            return lines[i]
          end
        end
        return orig_lines(path)
      end

      io.open = function(path, mode)
        if path == "/mnt/ext1/system/config/extensions.cfg" then
          local buf = {}
          return {
            write = function(self, data)
              table.insert(buf, data)
            end,
            close = function(self)
              written_files[path] = table.concat(buf)
            end,
          }
        end
        return orig_open(path, mode)
      end
    end)

    after_each(function()
      io.lines = orig_lines
      io.open = orig_open
    end)

    it("updates existing system extension entries with koreader.app", function()
      PocketBook:associateFileExtensions({ ["epub"] = true })
      local out = written_files["/mnt/ext1/system/config/extensions.cfg"]
      assert.is_not_nil(out)
      assert.is_truthy(out:find("^#koreader"))
      assert.is_truthy(
        out:find(
          "epub:application/epub%+zip:1:koreader%.app,viewer%.app:ICON_EPUB"
        )
      )
    end)
  end)
end)
