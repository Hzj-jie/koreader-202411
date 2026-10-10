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

    -- Write module that returns nil (or returns nothing)
    local f2 =
      io.open(test_dir .. "/plugins/dummy.koplugin/nil_module.lua", "w")
    if f2 then
      f2:write("-- Module that returns nothing\nlocal x = 1 + 1\n")
      f2:close()
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

  it("loads plugins returning nil without throwing module not found", function()
    -- Standard Lua require succeeds and returns true/package.loaded when a module returns nil.
    -- In production loadlib.lua line 199, if loaded_module == nil it throws module not found.
    local ok, res = pcall(function()
      return require("plugins/dummy.koplugin/nil_module")
    end)
    assert.is_true(ok)
    assert.is_not_nil(res)
  end)
end)
