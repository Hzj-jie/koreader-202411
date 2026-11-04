describe("BinaryVersions", function()
  local BinaryVersions
  local gettext

  setup(function()
    require("commonrequire")
    BinaryVersions = require("binary_versions")
    gettext = require("gettext")
  end)

  it("enumerates all 43 ELF binaries in order", function()
    local kv_pairs = BinaryVersions:getKeyValuePairs()
    assert.are.equal(43, #kv_pairs)

    local section = 1
    local prev_path = ""
    for _, pair in ipairs(kv_pairs) do
      local path = pair[1]
      local cur_section = path:match("^common/") and 2 or (path:match("^libs/") and 3 or 1)
      assert.is_true(cur_section >= section)
      if cur_section == section then
        assert.is_true(prev_path < path)
      end
      section = cur_section
      prev_path = path
    end
  end)

  it("resolves dynamic versions and marks known-unknown libraries", function()
    local unknown = gettext("Unknown")
    local known_unknown = {
      ["libs/libblitbuffer.so"] = true,
      ["libs/libgif.so.7"] = true,
      ["libs/libk2pdfopt.so.2"] = true,
      ["libs/libkoreader-cre.so"] = true,
      ["libs/libkoreader-djvu.so"] = true,
      ["libs/libkoreader-nnsvg.so"] = true,
      ["libs/libkoreader-xtext.so"] = true,
    }

    local by_path = {}
    for _, pair in ipairs(BinaryVersions:getKeyValuePairs()) do
      local path, ver = pair[1], pair[2]
      by_path[path] = ver
      assert.is_string(ver)
      assert.is_true(#ver > 0)
      if known_unknown[path] then
        assert.are.equal(unknown, ver)
      else
        assert.are_not.equal(unknown, ver)
      end
    end

    assert.is_truthy(by_path["lua"]:match("^Lua "))
    assert.is_truthy(by_path["luajit"]:match("^LuaJIT "))
    assert.is_truthy(by_path["common/lpeg.so"]:match("%d+%.%d+"))
    assert.is_truthy(by_path["libs/libfreetype.so.6"]:match("^%d+%.%d+%.%d+$"))
    assert.is_truthy(by_path["libs/libfribidi.so.0"]:match("%d+%.%d+"))
    assert.is_truthy(by_path["libs/libunibreak.so.8"]:match("^%d+%.%d+$"))
    assert.is_truthy(by_path["libs/liblodepng.so"]:match("%d+"))
    assert.are.equal("3.5.0", by_path["libs/liblunasvg.so"])
    assert.is_truthy(by_path["libs/libarchive.so.13"]:match("^libarchive "))
    assert.is_truthy(by_path["libs/libxxhash.so.0"]:match("^%d+%.%d+%.%d+$"))
    assert.are.equal(require("ffi/mupdf").version, by_path["libs/libwrap-mupdf.so"])
    assert.is_truthy(by_path["libs/libjpeg.so.8"]:match("^libjpeg%-turbo version "))
  end)

  it("shows Binary versions button in About dialog and opens KeyValuePage", function()
    local UIManager = require("ui/uimanager")
    local common_info = require("ui/elements/common_info_menu_table")
    local shown = {}
    stub(UIManager, "show", function(_self, widget)
      table.insert(shown, widget)
    end)
    finally(function()
      UIManager.show:revert()
    end)

    common_info.about.callback()
    assert.are.equal(1, #shown)
    local btn = shown[1].other_buttons[1][1]
    assert.are.equal(gettext("Binary versions"), btn.text)

    btn.callback()
    assert.are.equal(2, #shown)
    local kv_page = shown[2]
    assert.are.equal(gettext("Binary versions"), kv_page.title)
    assert.are.equal(43, #kv_page.kv_pairs)
  end)

  it("scans version banners straddling a 64 KiB read boundary", function()
    local lfs = require("libs/libkoreader-lfs")
    local orig_cwd = assert(lfs.currentdir())
    local tmpdir = os.tmpname()
    os.remove(tmpdir)
    assert(lfs.mkdir(tmpdir))
    finally(function()
      lfs.chdir(orig_cwd)
      os.remove(tmpdir .. "/libs/libkoreader-djvu.so")
      lfs.rmdir(tmpdir .. "/libs")
      lfs.rmdir(tmpdir .. "/common")
      lfs.rmdir(tmpdir)
    end)

    assert(lfs.mkdir(tmpdir .. "/common"))
    assert(lfs.mkdir(tmpdir .. "/libs"))
    local f = assert(io.open(tmpdir .. "/libs/libkoreader-djvu.so", "wb"))
    f:write("\127ELF", string.rep("\0", 65521 - 4), "DjVuLibre-3.5.28\0")
    f:close()

    assert(lfs.chdir(tmpdir))
    assert.are.same({ { "libs/libkoreader-djvu.so", "DjVuLibre-3.5.28" } }, BinaryVersions:getKeyValuePairs())
  end)
end)
