describe("slt2 template engine module", function()
  local slt2, ffiUtil, DataStorage

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    slt2 = require("plugins/exporter.koplugin/template/slt2")
    ffiUtil = require("ffi/util")
    DataStorage = require("datastorage")
  end)

  local function get_temp_file(suffix)
    local dir = DataStorage:getDataDir()
    return string.format("%s/slt2_%d_%d_%s.txt", dir, ffiUtil.getpid(), os.time(), suffix)
  end

  it("should precompile template strings with nested file inclusions", function()
    local tmpl = "Hello #{= name }#!"
    local compiled = slt2.precompile(tmpl)
    assert.is_string(compiled)
    assert.are.equal(tmpl, compiled)

    -- Test nested inclusions: root -> child -> grandchild
    local file_grandchild = get_temp_file("grandchild")
    local file_child = get_temp_file("child")

    local fg = assert(io.open(file_grandchild, "w"))
    fg:write("[Grandchild Content: #{= val }#]")
    fg:close()

    local fc = assert(io.open(file_child, "w"))
    fc:write("Child Start -> #{include: " .. string.format("%q", file_grandchild) .. "}# <- Child End")
    fc:close()

    local root_tmpl = "Root: #{include: " .. string.format("%q", file_child) .. "}#"

    finally(function()
      os.remove(file_grandchild)
      os.remove(file_child)
    end)

    local precompiled = slt2.precompile(root_tmpl)
    assert.is_string(precompiled)

    local t = slt2.loadstring(root_tmpl)
    local rendered = slt2.render(t, { val = "42" })
    assert.are.equal("Root: Child Start -> [Grandchild Content: 42] <- Child End", rendered)
  end)

  it("should support custom start_tag and end_tag in loadstring", function()
    local tmpl = "Greeting: <% for i, name in ipairs(names) do %><% if i > 1 then %>, <% end %><%= name %><% end %>!"
    local t = slt2.loadstring(tmpl, "<%", "%>")
    assert.is_table(t)

    local rendered = slt2.render(t, { names = { "Alice", "Bob", "Charlie" } })
    assert.are.equal("Greeting: Alice, Bob, Charlie!", rendered)
  end)

  it("should raise errors for missing end tags in include and templates", function()
    -- Missing end tag in loadstring
    assert.has_error(function()
      slt2.loadstring("Hello #{= name")
    end)

    -- Missing end tag in include_fold
    assert.has_error(function()
      slt2.precompile("Include #{include: 'some_file'")
    end)
  end)

  it("should load template from file and render", function()
    local tmp_file = get_temp_file("loadfile")
    local f = assert(io.open(tmp_file, "w"))
    f:write("Title: #{= title }# | Score: #{= score * 2 }#")
    f:close()

    finally(function()
      os.remove(tmp_file)
    end)

    local t = slt2.loadfile(tmp_file)
    assert.is_table(t)
    assert.are.equal(tmp_file, t.name)

    local rendered = slt2.render(t, { title = "Test", score = 50 })
    assert.are.equal("Title: Test | Score: 100", rendered)
  end)

  it("should support render_co coroutine streaming", function()
    local tmpl = "#{ for i = 1, 3 do }#Item #{= i }#; #{ end }#"
    local t = slt2.loadstring(tmpl)

    local render_fn = slt2.render_co(t, {})
    assert.is_function(render_fn)

    local co = coroutine.create(render_fn)
    local chunks = {}
    while coroutine.status(co) ~= "dead" do
      local ok, chunk = coroutine.resume(co)
      if not ok then
        error(chunk)
      end
      if chunk then
        table.insert(chunks, chunk)
      end
    end

    local rendered = table.concat(chunks)
    assert.are.equal("Item 1; Item 2; Item 3; ", rendered)
  end)

  it("should handle loops, expressions, and propagate runtime execution errors", function()
    -- Loops and expressions
    local tmpl = "Sum: #{ local sum = 0; for _, n in ipairs(numbers) do sum = sum + n end }##{= sum }#"
    local t = slt2.loadstring(tmpl)
    local rendered = slt2.render(t, { numbers = { 10, 20, 30 } })
    assert.are.equal("Sum: 60", rendered)

    -- Runtime error propagation
    local err_tmpl = "Before #{ error('template execution failed!') }# After"
    local t_err = slt2.loadstring(err_tmpl)
    assert.has_error(function()
      slt2.render(t_err, {})
    end)
  end)
end)
