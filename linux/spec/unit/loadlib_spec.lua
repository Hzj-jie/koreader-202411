local ffiUtil

describe("ffi/loadlib module", function()
  local test_dir
  local orig_path

  setup(function()
    require("commonrequire")
    ffiUtil = require("ffi/util")
    test_dir = "/tmp/loadlib_test_" .. tostring(ffiUtil.getpid())
    orig_path = package.path

    -- Create test plugin hierarchy
    os.execute("mkdir -p " .. test_dir .. "/plugins/dummy.koplugin")

    -- Write module that returns a table
    local f1 =
      io.open(test_dir .. "/plugins/dummy.koplugin/table_module.lua", "w")
    if f1 then
      f1:write("return { answer = 42 }\n")
      f1:close()
    end

    package.path = test_dir .. "/?.lua;" .. package.path
  end)

  teardown(function()
    package.path = orig_path
    os.execute("rm -rf " .. test_dir)
  end)

  it("loads plugins returning a table correctly", function()
    local mod = require("plugins/dummy.koplugin/table_module")
    assert.is_table(mod)
    assert.are.equal(42, mod.answer)
  end)
end)
