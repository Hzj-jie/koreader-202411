describe("Trapper module", function()
  local Trapper

  setup(function()
    require("commonrequire")
    Trapper = require("ui/trapper")
  end)

  it("should initialize Trapper module", function()
    assert.is_table(Trapper)
    assert.is_function(Trapper.wrap)
  end)

  it("should execute wrapped functions successfully", function()
    local executed = false
    local result = Trapper:wrap(function()
      executed = true
    end)
    assert.is_true(result)
    assert.is_true(executed)
  end)

  it("should catch and log errors in wrapped functions", function()
    local resumed = Trapper:wrap(function()
      error("test error")
    end)
    assert.is_true(resumed)
  end)

  it("should execute dismissableRunInSubprocess fallback in-process when unwrapped", function()
    local run_count = 0
    local ok, res = Trapper:dismissableRunInSubprocess(function()
      run_count = run_count + 1
      return "done"
    end, "Processing...")
    assert.is_true(ok)
    assert.is_same(1, run_count)
    assert.is_same("done", res)
  end)
end)
