describe("ListView", function()
  local ListView
  local Widget
  local Geom
  local Device
  local BD

  setup(function()
    require("commonrequire")
    ListView = require("ui/widget/listview")
    Widget = require("ui/widget/widget")
    Geom = require("ui/geometry")
    Device = require("device")
    BD = require("ui/bidi")
  end)

  local function createMockItem(w, h, name)
    local wgt = Widget:new({
      dimen = Geom:new({ w = w, h = h }),
      name = name,
    })
    return wgt
  end

  it("should return early if items is empty", function()
    local lv = ListView:new({
      width = 200,
      height = 400,
      items = {},
    })

    assert.is_nil(lv.show_page)
    assert.is_nil(lv.main_content)
  end)

  it("should initialize ListView and paginate items correctly", function()
    local updated_page, updated_total
    local items = {}
    for i = 1, 10 do
      table.insert(items, createMockItem(180, 40, "item" .. i))
    end

    local lv = ListView:new({
      width = 200,
      height = 120, -- 120 / 40 = 3 items per page -> ceil(10/3) = 4 pages
      items = items,
      page_update_cb = function(page, total)
        updated_page = page
        updated_total = total
      end,
    })

    assert.are.equal(1, lv.show_page)
    assert.are.equal(4, lv.pages)
    assert.are.equal(3, lv.items_per_page)
    assert.are.equal(1, updated_page)
    assert.are.equal(4, updated_total)
    assert.are.equal(3, #lv.main_content)
    assert.are.equal("item1", lv.main_content[1].name)
    assert.are.equal("item3", lv.main_content[3].name)

    -- Next page
    lv:nextPage()
    assert.are.equal(2, lv.show_page)
    assert.are.equal(2, updated_page)
    assert.are.equal("item4", lv.main_content[1].name)

    -- Navigate to last page (page 4, should have 1 item)
    lv:nextPage()
    lv:nextPage()
    assert.are.equal(4, lv.show_page)
    assert.are.equal(4, updated_page)
    assert.are.equal(1, #lv.main_content)
    assert.are.equal("item10", lv.main_content[1].name)

    -- nextPage when on last page is a no-op
    lv:nextPage()
    assert.are.equal(4, lv.show_page)

    -- prevPage
    lv:prevPage()
    assert.are.equal(3, lv.show_page)
    assert.are.equal(3, updated_page)

    -- prevPage all the way to first page
    lv:prevPage()
    lv:prevPage()
    assert.are.equal(1, lv.show_page)
    assert.are.equal(1, updated_page)

    -- prevPage when on first page is a no-op
    lv:prevPage()
    assert.are.equal(1, lv.show_page)
  end)

  it("should handle swipes for page turning", function()
    local orig_is_touch = Device.isTouchDevice
    Device.isTouchDevice = function() return true end

    local items = {}
    for i = 1, 6 do
      table.insert(items, createMockItem(180, 50, "item" .. i))
    end

    local lv = ListView:new({
      width = 200,
      height = 100, -- 2 items per page -> 3 pages
      items = items,
      page_update_cb = function() end,
    })

    assert.truthy(lv.ges_events.Swipe)

    local res_west = lv:onSwipe(nil, { direction = "west" })
    assert.is_true(res_west)
    assert.are.equal(2, lv.show_page)

    local res_east = lv:onSwipe(nil, { direction = "east" })
    assert.is_true(res_east)
    assert.are.equal(1, lv.show_page)

    local res_other = lv:onSwipe(nil, { direction = "north" })
    assert.is_nil(res_other)

    Device.isTouchDevice = orig_is_touch
  end)
end)
