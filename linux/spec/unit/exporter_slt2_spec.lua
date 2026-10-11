describe("slt2 template engine", function()
  local slt2

  setup(function()
    require("commonrequire")
    slt2 = require("plugins/exporter.koplugin/template/slt2")
  end)

  it(
    "should compile and render basic templates with variable interpolation",
    function()
      local t = slt2.loadstring("Hello #{= name }#!")
      local result = slt2.render(t, { name = "KOReader" })
      assert.are.equal("Hello KOReader!", result)
    end
  )

  it("preserves caller's existing metatable on env table", function()
    local t = slt2.loadstring("Value: #{= val }#")
    local custom_mt = {
      __index = function(_, k)
        if k == "val" then
          return "custom_value"
        end
      end,
    }
    local env = setmetatable({}, custom_mt)

    slt2.render_co(t, env)
    assert.are.equal(custom_mt, getmetatable(env))
  end)

  it(
    "isolates environments between concurrent coroutines using same template",
    function()
      local t = slt2.loadstring("#{ coroutine.yield(val) }#")
      local env1 = { val = "first" }
      local env2 = { val = "second" }

      local co1 = coroutine.create(slt2.render_co(t, env1))
      local co2 = coroutine.create(slt2.render_co(t, env2))

      local ok1, val1 = coroutine.resume(co1)
      assert.is_true(ok1)

      local ok2, val2 = coroutine.resume(co2)
      assert.is_true(ok2)
      assert.are.equal("second", val2)
      assert.are.equal("first", val1)
    end
  )
end)
