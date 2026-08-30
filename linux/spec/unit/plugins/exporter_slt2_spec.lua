describe("slt2 template engine module", function()
  local slt2

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    slt2 = require("plugins/exporter.koplugin/template/slt2")
  end)

  it("should precompile template strings", function()
    local tmpl = "Hello #{= name }#!"
    local compiled = slt2.precompile(tmpl)
    assert.is_string(compiled)
    assert.are.equal(tmpl, compiled)
  end)

  it("should load template string and render with env", function()
    local tmpl =
      "Hello #{= name }#! Count: #{ for i = 1, 2 do }##{= i }# #{ end }#"
    local t = slt2.loadstring(tmpl)
    assert.is_table(t)
    assert.is_function(t.code)

    local rendered = slt2.render(t, { name = "World" })
    assert.are.equal("Hello World! Count: 1 2 ", rendered)
  end)

  it("should load template from file and render", function()
    local tmp_file = os.tmpname()
    local f = io.open(tmp_file, "w")
    f:write("Title: #{= title }#")
    f:close()

    local t = slt2.loadfile(tmp_file)
    assert.is_table(t)
    assert.are.equal(tmp_file, t.name)

    local rendered = slt2.render(t, { title = "Test" })
    assert.are.equal("Title: Test", rendered)

    os.remove(tmp_file)
  end)

  it("should support template file inclusion", function()
    local inc_file = os.tmpname()
    local f = io.open(inc_file, "w")
    f:write("Included Content")
    f:close()

    local tmpl = "Start #{include:" .. string.format("%q", inc_file) .. "}# End"
    local t = slt2.loadstring(tmpl)
    local rendered = slt2.render(t, {})
    assert.are.equal("Start Included Content End", rendered)

    os.remove(inc_file)
  end)
end)
