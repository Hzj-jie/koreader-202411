describe("Coverbrowser MosaicMenu module", function()
  local CoverMenu
  local MosaicMenu
  local UIManager

  setup(function()
    require("commonrequire")
    CoverMenu = require("plugins/coverbrowser.koplugin/covermenu")
    MosaicMenu = require("plugins/coverbrowser.koplugin/mosaicmenu")
    UIManager = require("ui/uimanager")
  end)

  it("should initialize MosaicMenu module", function()
    assert.is_table(MosaicMenu)
  end)

  local function newMenu(orig_fn)
    return {
      path = "/tmp",
      showFileDialog = orig_fn,
      item_group = { clear = function() end },
      _recalculateDimen = function() end,
      page_info = { resetLayout = function() end },
      return_button = { resetLayout = function() end },
      content_group = { resetLayout = function() end },
      _updateItemsBuildUI = function() end,
      updatePageInfo = function() end,
      showParent = function() end,
    }
  end

  it("does not recurse infinitely when updateItems is called twice before nextTick drains", function()
    local next_ticks = {}
    stub(UIManager, "nextTick", function(_self, cb)
      table.insert(next_ticks, cb)
    end)
    finally(function()
      UIManager.nextTick:revert()
    end)

    local orig_calls = 0
    local function orig_fn()
      orig_calls = orig_calls + 1
    end
    local menu = newMenu(orig_fn)

    CoverMenu.updateItems(menu)
    CoverMenu.updateItems(menu)
    assert.are.equal(2, #next_ticks)

    for _, cb in ipairs(next_ticks) do
      cb()
    end

    assert.are.equal(orig_fn, menu.showFileDialog_orig)
    menu:showFileDialog({ path = "/tmp/book.epub" })
    assert.are.equal(1, orig_calls)
  end)

  it("re-wraps showFileDialog when FileManager assigns a new showFileDialog", function()
    local next_ticks = {}
    stub(UIManager, "nextTick", function(_self, cb)
      table.insert(next_ticks, cb)
    end)
    finally(function()
      UIManager.nextTick:revert()
    end)

    local fm_fn1_calls = 0
    local function fm_fn1()
      fm_fn1_calls = fm_fn1_calls + 1
    end
    local fm_fn2_calls = 0
    local function fm_fn2()
      fm_fn2_calls = fm_fn2_calls + 1
    end

    local menu = newMenu(fm_fn1)
    CoverMenu.updateItems(menu)
    table.remove(next_ticks, 1)()
    assert.are.equal(fm_fn1, menu.showFileDialog_orig)

    menu.showFileDialog = fm_fn2
    CoverMenu.updateItems(menu)
    table.remove(next_ticks, 1)()
    assert.are.equal(fm_fn2, menu.showFileDialog_orig)

    menu:showFileDialog({ path = "/tmp/book.epub" })
    assert.are.equal(0, fm_fn1_calls)
    assert.are.equal(1, fm_fn2_calls)
  end)
end)
