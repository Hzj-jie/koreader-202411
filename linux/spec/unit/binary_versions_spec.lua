describe("BinaryVersions", function()
  local BinaryVersions
  local gettext

  setup(function()
    require("commonrequire")
    BinaryVersions = require("binary_versions")
    gettext = require("gettext")
  end)

  it("enumerates all 43 ELF binaries in order", function()
    assert.is_nil(BinaryVersions.getKeyValuePairs)
    local items = BinaryVersions:getMenuItems()
    assert.are.equal(43, #items)

    local section = 1
    local prev_path = ""
    for _, item in ipairs(items) do
      assert.is_false(item.select_enabled)
      assert.is_nil(item.dim)
      local path = item.text:match("^(.-): .+$")
      assert.is_string(path)
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
    local T = require("ffi/util").template
    local lfs = require("libs/libkoreader-lfs")
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
    for _, item in ipairs(BinaryVersions:getMenuItems()) do
      assert.is_false(item.select_enabled)
      local path, ver = item.text:match("^(.-): (.+)$")
      by_path[path] = ver
      assert.is_string(ver)
      assert.is_true(#ver > 0)
      if known_unknown[path] then
        local expected = T(
          gettext("Last modified: %1"),
          os.date("%Y-%m-%d %H:%M", lfs.attributes(path, "modification"))
        )
        assert.are.equal(expected, ver)
      else
        assert.is_nil(ver:find(T(gettext("Last modified: %1"), ""), 1, true))
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

  it("falls back to file modification time when binary version is unknown", function()
    local T = require("ffi/util").template
    local lfs = require("libs/libkoreader-lfs")
    local tmp_dir = os.tmpname()
    os.remove(tmp_dir)
    lfs.mkdir(tmp_dir)
    lfs.mkdir(tmp_dir .. "/common")
    lfs.mkdir(tmp_dir .. "/libs")
    local tmp_file = tmp_dir .. "/libs/libdummy_unknown.so"
    local f = io.open(tmp_file, "w")
    f:write("\x7fELF")
    f:close()
    local fixed_time = 1700000000
    lfs.touch(tmp_file, fixed_time, fixed_time)

    local old_dir = lfs.currentdir()
    lfs.chdir(tmp_dir)
    finally(function()
      lfs.chdir(old_dir)
      os.remove(tmp_file)
      lfs.rmdir(tmp_dir .. "/libs")
      lfs.rmdir(tmp_dir .. "/common")
      lfs.rmdir(tmp_dir)
    end)

    assert.are.same({
      {
        text = "libs/libdummy_unknown.so: " .. T(
          gettext("Last modified: %1"),
          os.date("%Y-%m-%d %H:%M", fixed_time)
        ),
        select_enabled = false,
      },
    }, BinaryVersions:getMenuItems())
  end)

  it("shows Binary versions button in About dialog and opens Menu", function()
    local UIManager = require("ui/uimanager")
    local common_info = require("ui/elements/common_info_menu_table")
    local shown = {}
    stub(UIManager, "show", function(_self, widget)
      table.insert(shown, widget)
    end)
    spy.on(UIManager, "close")
    finally(function()
      UIManager.show:revert()
      UIManager.close:revert()
    end)

    common_info.about.callback()
    assert.are.equal(1, #shown)
    local btn = shown[1].other_buttons[1][1]
    assert.are.equal(gettext("Binary versions"), btn.text)

    btn.callback()
    assert.are.equal(2, #shown)
    local menu = shown[2]
    assert.are.equal(gettext("Binary versions"), menu.title)
    assert.is_true(menu.is_borderless)
    assert.is_false(menu.is_popout)
    assert.is_true(menu.title_bar_fm_style)
    assert.is_true(menu.multilines_show_more_text)
    assert.is_table(menu.item_table)
    assert.are.equal(43, #menu.item_table)
    assert.is_false(menu.item_table[1].select_enabled)
    assert.is_nil(menu.item_table[1].dim)

    assert.is_true(menu:onMenuSelect(menu.item_table[1]))
    assert.spy(UIManager.close).was_not_called()
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
    assert.are.same({
      {
        text = "libs/libkoreader-djvu.so: DjVuLibre-3.5.28",
        select_enabled = false,
      },
    }, BinaryVersions:getMenuItems())
  end)
end)
