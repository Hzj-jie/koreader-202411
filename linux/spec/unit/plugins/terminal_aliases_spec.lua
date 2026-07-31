describe("Terminal Aliases plugin module", function()
  local Aliases, lfs

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    lfs = require("libs/libkoreader-lfs")
    Aliases = require("plugins/terminal.koplugin/aliases")
  end)

  it("should load alias file entries into kv_pairs", function()
    local tmp_file = os.tmpname()
    local f = io.open(tmp_file, "w")
    f:write("# Comment line\n")
    f:write("alias ll=\"ls -la\"\n")
    f:write("alias gs=\"git status\"\n")
    f:close()

    local inst = {
      filename = tmp_file,
      kv_pairs = {},
    }
    setmetatable(inst, { __index = Aliases })

    inst:load()
    assert.is_table(inst.kv_pairs)
    assert.is_true(#inst.kv_pairs >= 3) -- Create new, separator, plus loaded aliases

    os.remove(tmp_file)
  end)

  it("should save kv_pairs to target alias file", function()
    local tmp_file = lfs.currentdir() .. "/test_aliases_" .. os.time()
    local f = io.open(tmp_file, "w")
    f:write("")
    f:close()

    local inst = {
      filename = tmp_file,
      kv_pairs = {
        { "Create a new alias", "" },
        "---",
        { "gs", "git status" },
        { "ll", "ls -la" },
      },
    }
    setmetatable(inst, { __index = Aliases })

    inst:save()

    local readFile = io.open(tmp_file, "r")
    assert.is_not_nil(readFile)
    local content = readFile:read("*a")
    readFile:close()

    assert.is_not_nil(content:find('alias gs="git status"', 1, true))
    assert.is_not_nil(content:find('alias ll="ls -la"', 1, true))

    os.remove(tmp_file)
  end)
end)
