describe("Linux runner wrapper scripts", function()
  setup(function()
    require("commonrequire")
  end)

  it("forwards command-line arguments from run.sh and run.lua.sh to _run.sh", function()
    local tmp_dir = "tmp_linux_run_args_spec"
    assert(require("libs/libkoreader-lfs").mkdir(tmp_dir))

    finally(function()
      os.execute("rm -rf " .. tmp_dir)
    end)

    assert.are.equal(
      0,
      os.execute(
        string.format(
          "cp %q %q %s/",
          assert(os.getenv("KO_WORKSPACE_DIR"), "KO_WORKSPACE_DIR must be set") .. "/linux/run.sh",
          assert(os.getenv("KO_WORKSPACE_DIR"), "KO_WORKSPACE_DIR must be set") .. "/linux/run.lua.sh",
          tmp_dir
        )
      )
    )

    local stub_fh = assert(io.open(tmp_dir .. "/_run.sh", "w"))
    stub_fh:write("#!/usr/bin/env bash\nprintf '%s\\n' \"$LUA\" \"$@\"\n")
    stub_fh:close()
    assert.are.equal(
      0,
      os.execute("chmod +x " .. tmp_dir .. "/_run.sh " .. tmp_dir .. "/run.sh " .. tmp_dir .. "/run.lua.sh")
    )

    local function runWrapper(script_name)
      local pipe = assert(
        io.popen(string.format('cd %q && ./%s "my book.epub" --flag', tmp_dir, script_name), "r")
      )
      local lines = {}
      for line in pipe:lines() do
        table.insert(lines, line)
      end
      pipe:close()
      return lines
    end

    assert.are.same({ "./luajit", "my book.epub", "--flag" }, runWrapper("run.sh"))
    assert.are.same({ "./lua", "my book.epub", "--flag" }, runWrapper("run.lua.sh"))
  end)
end)
