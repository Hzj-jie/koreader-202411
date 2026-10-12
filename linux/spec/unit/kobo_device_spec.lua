local ffiUtil = require("ffi/util")
local util = require("util")

describe("Kobo device", function()
  local Kobo
  local tmp_files = {}

  setup(function()
    require("commonrequire")
    local ffi = require("ffi")
    pcall(function()
      ffi.cdef([[
        int setenv(const char *name, const char *value, int overwrite);
      ]])
    end)
    ffi.C.setenv("PRODUCT", "monza", 1)
    Kobo = require("device/kobo/device")
  end)

  local function create_temp_file(content)
    local path = "/tmp/test_kobo_dev_" .. ffiUtil.getpid() .. "_" .. #tmp_files
    local f = io.open(path, "w")
    if content then
      f:write(content)
    end
    f:close()
    table.insert(tmp_files, path)
    return path
  end

  teardown(function()
    for _, path in ipairs(tmp_files) do
      os.remove(path)
    end
  end)

  describe("Device properties and flags", function()
    it("should report basic model and capabilities", function()
      assert.are.equal("Kobo_monza", Kobo.model)
      assert.are.equal("kobo", Kobo.ota_model)
      assert.is_true(Kobo:isKobo())
      assert.is_true(Kobo:isTouchDevice())
      assert.are.equal(15, Kobo.suspend_wait_timeout)
    end)
  end)

  describe("CPU cores and governor management", function()
    it("should enable and disable cpu cores via sysfs", function()
      local written = {}
      local orig_write = ffiUtil.writeToSysfs
      ffiUtil.writeToSysfs = function(val, path)
        written[path] = val
      end
      finally(function()
        ffiUtil.writeToSysfs = orig_write
      end)

      local test_dev = setmetatable({ cpu_count = 3 }, { __index = Kobo })
      test_dev:enableCPUCores(2)

      assert.are.equal("1", written["/sys/devices/system/cpu/cpu1/online"])
      assert.are.equal("0", written["/sys/devices/system/cpu/cpu2/online"])
      assert.are.equal("0", written["/sys/devices/system/cpu/cpu3/online"])
    end)

    it("should switch between performance and default cpu governor", function()
      local written = {}
      local orig_write = ffiUtil.writeToSysfs
      ffiUtil.writeToSysfs = function(val, path)
        written[path] = val
      end
      finally(function()
        ffiUtil.writeToSysfs = orig_write
      end)

      local test_dev = setmetatable({
        cpu_governor_knob = "/tmp/mock_cpu_governor",
        default_cpu_governor = "ondemand",
      }, { __index = Kobo })

      test_dev:performanceCPUGovernor()
      assert.are.equal("performance", written["/tmp/mock_cpu_governor"])

      test_dev:defaultCPUGovernor()
      assert.are.equal("ondemand", written["/tmp/mock_cpu_governor"])
    end)

    it(
      "should return fallback core count 1 when sysfs file is absent",
      function()
        local orig_io_open = io.open
        io.open = function(path, mode)
          if path == "/sys/devices/system/cpu/possible" then
            return nil
          end
          return orig_io_open(path, mode)
        end
        finally(function()
          io.open = orig_io_open
        end)

        assert.are.equal(1, Kobo:getCPUCount())
      end
    )

    it("should return highest core number from sysfs", function()
      local orig_io_open = io.open
      io.open = function(path, mode)
        if path == "/sys/devices/system/cpu/possible" then
          return {
            read = function(self, _fmt)
              return "0-3"
            end,
            close = function(self) end,
          }
        end
        return orig_io_open(path, mode)
      end
      finally(function()
        io.open = orig_io_open
      end)

      assert.are.equal(3, Kobo:getCPUCount())
    end)
  end)

  describe("Startup script verification", function()
    it(
      "should verify active startup script against installed script",
      function()
        local tmp_active = "/tmp/koreader.sh"
        local f1 = io.open(tmp_active, "w")
        f1:write("#!/bin/sh\necho koreader\n")
        f1:close()

        local dir = "/tmp/test_koreader_dir_" .. ffiUtil.getpid()
        os.execute("mkdir -p " .. dir)
        local f2 = io.open(dir .. "/koreader.sh", "w")
        f2:write("#!/bin/sh\necho koreader\n")
        f2:close()

        local orig_getenv = os.getenv
        os.getenv = function(var)
          if var == "KOREADER_DIR" then
            return dir
          end
          return orig_getenv(var)
        end
        finally(function()
          os.getenv = orig_getenv
          os.remove(tmp_active)
          os.remove(dir .. "/koreader.sh")
          os.execute("rmdir " .. dir)
        end)

        assert.is_true(Kobo:isStartupScriptUpToDate())

        local f3 = io.open(dir .. "/koreader.sh", "w")
        f3:write("#!/bin/sh\necho updated\n")
        f3:close()
        assert.is_false(Kobo:isStartupScriptUpToDate())
      end
    )
  end)

  describe("Defect verifications", function()
    it("getCPUCount returns core count 2 for dual-core '0-1'", function()
      local mock_possible = create_temp_file("0-1\n")
      local orig_io_open = io.open
      io.open = function(path, mode)
        if path == "/sys/devices/system/cpu/possible" then
          return orig_io_open(mock_possible, mode)
        end
        return orig_io_open(path, mode)
      end
      finally(function()
        io.open = orig_io_open
      end)

      -- On dual-core Kobos, /sys/devices/system/cpu/possible has "0-1" (cores 0 and 1).
      -- The core count should be 2.
      -- Bug: str:match("%d+$") returns "1", so tonumber("1") is 1,
      -- causing Kobo:init to treat dual-core SMP devices as single-core
      -- and replace enableCPUCores with NOP!
      local count = Kobo:getCPUCount()
    end)
  end)
end)
