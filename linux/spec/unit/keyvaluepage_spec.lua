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
    _G.G_reader_settings = {
      read = function(self, key)
        if key == "keyvalues_per_page" then
          return 5
        end
        return nil
      end,
    }
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
      keyvalues_per_page = 5,
    })

    assert.are.equal(1, page.page)
    assert.are.equal(3, page.total_pages)

    page:nextPage()
    assert.are.equal(2, page.page)

    page:nextPage()
    assert.are.equal(3, page.page)

    page:nextPage()
    assert.are.equal(3, page.page) -- Already at last page

    page:prevPage()
    assert.are.equal(2, page.page)

    page:goToPage(1)
    assert.are.equal(1, page.page)

    page:goToPage(3)
    assert.are.equal(3, page.page)
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

    local item = page.kv_item_table[1]
    assert.is_not_nil(item)

    -- Focus & Unfocus
    item:onFocus()
    assert.is_true(item.frame.invert)
    item:onUnfocus()
    assert.is_false(item.frame.invert)

    -- Tap (invokes item callback)
    item:onTap()
    assert.is_true(callback_invoked)

    -- Hold (opens TextViewer)
    local shown_widget = nil
    page.showWidget = function(self, w)
      shown_widget = w
    end
    item:onHold()
    assert.is_not_nil(shown_widget)
  end)

  it("should handle onSwipe and onMultiSwipe gestures", function()
    local kv_pairs = {}
    for i = 1, 10 do
      table.insert(kv_pairs, { "K" .. i, "V" .. i })
    end

    local page = KeyValuePage:new({
      title = "Swipe Page",
      kv_pairs = kv_pairs,
      keyvalues_per_page = 5,
    })

    -- Swipe west -> next page
    page:onSwipe(nil, { direction = "west" })
    assert.are.equal(2, page.page)

    -- Swipe east -> prev page
    page:onSwipe(nil, { direction = "east" })
    assert.are.equal(1, page.page)

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

  it("should handle onReturn, onClose, and onExit", function()
    local return_called = false
    local page = KeyValuePage:new({
      title = "Exit Page",
      kv_pairs = { { "K", "V" } },
      callback_return = function()
        return_called = true
      end,
    })

    page:onReturn()
    assert.is_true(return_called)

    local closed_widget = nil
    local old_close = UIManager.close
    UIManager.close = function(self, w)
      closed_widget = w
    end

    assert.is_true(page:onExit())
    assert.are.equal(page, closed_widget)

    page:onClose()

    UIManager.close = old_close
  end)
end)
