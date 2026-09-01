describe("KeyValuePage UI component", function()
  local KeyValuePage, Device, Geom, UIManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    local device = require("device")
    require("document/canvascontext"):init(device)

    KeyValuePage = require("ui/widget/keyvaluepage")
    Device = require("device")
    Geom = require("ui/geometry")
    UIManager = require("ui/uimanager")
  end)

  before_each(function()
    G_reader_settings:save("keyvalues_per_page", 5)
  end)

  after_each(function()
    G_reader_settings:delete("keyvalues_per_page")
  end)

  it("should instantiate and populate items correctly with string separator", function()
    local kv_pairs = {
      { "Key 1", "Value 1" },
      "----------------------------",
      { "Key 2", "Value 2", callback = function() end },
      "Solo Text",
    }

    local page = KeyValuePage:new({
      title = "Test KV Page",
      kv_pairs = kv_pairs,
      callback_return = function() end,
    })

    assert.is_not_nil(page)
    assert.is_true(#page.kv_pairs >= 3)
    assert.are.equal("Key 1", page.kv_pairs[1][1])
    assert.is_true(page.kv_pairs[1].separator)
    assert.are.equal("Key 2", page.kv_pairs[2][1])
  end)

  it("should handle pagination navigation (nextPage, prevPage, goToPage)", function()
    local kv_pairs = {}
    for i = 1, 15 do
      table.insert(kv_pairs, { "Key " .. i, "Value " .. i })
    end

    local page = KeyValuePage:new({
      title = "Multi Page KV",
      kv_pairs = kv_pairs,
    })

    assert.are.equal(1, page.show_page)
    assert.are.equal(3, page.pages)

    page:nextPage()
    assert.are.equal(2, page.show_page)

    page:nextPage()
    assert.are.equal(3, page.show_page)

    page:nextPage()
    assert.are.equal(3, page.show_page) -- Already at last page

    page:prevPage()
    assert.are.equal(2, page.show_page)

    page:goToPage(1)
    assert.are.equal(1, page.show_page)

    page:goToPage(3)
    assert.are.equal(3, page.show_page)
  end)

  it("should handle KeyValueItem focus, tap, and hold interactions", function()
    local callback_invoked = false
    local kv_pairs = {
      {
        "Interactive Key",
        "Value with \n control chars",
        callback = function()
          callback_invoked = true
        end,
      },
    }

    local page = KeyValuePage:new({
      title = "Interactive Page",
      kv_pairs = kv_pairs,
    })

    local item = page.layout[1][1]
    assert.is_not_nil(item)

    -- Focus & Unfocus
    item[1]:onFocus()
    assert.is_true(item[1]._focused)
    item[1]:onUnfocus()
    assert.is_nil(item[1]._focused)

    -- Tap (invokes item callback)
    item:onTap()
    assert.is_true(callback_invoked)

    -- Hold (opens TextViewer)
    local shown_widget = nil
    local old_show = UIManager.show
    UIManager.show = function(self, w)
      shown_widget = w
    end
    item.is_truncated = true
    item:onHold()
    assert.is_not_nil(shown_widget)
    UIManager.show = old_show
  end)

  it("should handle onSwipe and onMultiSwipe gestures", function()
    local kv_pairs = {}
    for i = 1, 10 do
      table.insert(kv_pairs, { "K" .. i, "V" .. i })
    end

    local page = KeyValuePage:new({
      title = "Swipe Page",
      kv_pairs = kv_pairs,
    })

    -- Swipe west -> next page
    page:onSwipe(nil, { direction = "west" })
    assert.are.equal(2, page.show_page)

    -- Swipe east -> prev page
    page:onSwipe(nil, { direction = "east" })
    assert.are.equal(1, page.show_page)

    -- Swipe south -> exit / close
    local closed_widget = nil
    local old_close = UIManager.close
    UIManager.close = function(self, w)
      closed_widget = w
    end

    page:onSwipe(nil, { direction = "south" })
    assert.are.equal(page, closed_widget)

    -- MultiSwipe -> exit
    closed_widget = nil
    page:onMultiSwipe()
    assert.are.equal(page, closed_widget)

    UIManager.close = old_close
  end)

  it("should handle onReturn and onExit", function()
    local return_called = false
    local page = KeyValuePage:new({
      title = "Exit Page",
      kv_pairs = { { "K", "V" } },
      callback_return = function()
        return_called = true
      end,
    })

    local closed_widget = nil
    local old_close = UIManager.close
    UIManager.close = function(self, w)
      closed_widget = w
    end

    page:onReturn()
    assert.is_true(return_called)
    assert.are.equal(page, closed_widget)

    closed_widget = nil
    assert.is_true(page:onExit())
    assert.are.equal(page, closed_widget)

    UIManager.close = old_close
  end)
end)
