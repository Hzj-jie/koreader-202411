describe("DateTimeWidget module", function()
  local DateTimeWidget
  local UIManager
  local Geom
  local Device

  local orig_setDirty
  local orig_show
  local orig_close

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    DateTimeWidget = require("ui/widget/datetimewidget")
    UIManager = require("ui/uimanager")
    Geom = require("ui/geometry")
    Device = require("device")

    orig_setDirty = UIManager.setDirty
    orig_show = UIManager.show
    orig_close = UIManager.close
  end)

  before_each(function()
    UIManager.setDirty = function() end
    UIManager.show = function() end
    UIManager.close = function(_, widget)
      if widget and widget.onClose then
        widget:onClose()
      end
    end
  end)

  after_each(function()
    UIManager.setDirty = orig_setDirty
    UIManager.show = orig_show
    UIManager.close = orig_close
  end)

  describe("Initialization and picker layouts", function()
    it("should initialize time picker (2 pickers)", function()
      local widget = DateTimeWidget:new({
        hour = 10,
        min = 30,
        ok_text = "Set time",
        title_text = "Set time",
      })
      assert.is_table(widget)
      assert.are.equal(2, widget.nb_pickers)
      assert.truthy(widget.width)
      assert.truthy(widget.hour_widget)
      assert.truthy(widget.min_widget)
    end)

    it("should initialize date picker (3 pickers)", function()
      local widget = DateTimeWidget:new({
        year = 2024,
        month = 11,
        day = 15,
        title_text = "Set date",
      })
      assert.are.equal(3, widget.nb_pickers)
      assert.truthy(widget.year_widget)
      assert.truthy(widget.month_widget)
      assert.truthy(widget.day_widget)
    end)

    it("should initialize full date-time picker (6 pickers)", function()
      local widget = DateTimeWidget:new({
        year = 2024,
        month = 11,
        day = 15,
        hour = 14,
        min = 45,
        sec = 30,
        title_text = "Set full timestamp",
      })
      assert.are.equal(6, widget.nb_pickers)
      assert.truthy(widget.sec_widget)
    end)

    it("should initialize duration picker (day, hour, min)", function()
      local widget = DateTimeWidget:new({
        day = 5,
        hour = 12,
        min = 0,
        title_text = "Set duration",
      })
      assert.are.equal(3, widget.nb_pickers)
    end)
  end)

  describe("Buttons and callbacks", function()
    it("should handle default button callback", function()
      local default_res = nil
      local widget = DateTimeWidget:new({
        year = 2024,
        month = 5,
        day = 1,
        default_value = "2024-05-01",
        default_text = "Reset to 2024-05-01",
        default_callback = function(vals)
          default_res = vals
        end,
      })

      local btn_table = widget.date_frame[1][3][1]
      local default_btn = btn_table.buttons[1][1]
      assert.are.equal("Reset to 2024-05-01", default_btn.text)

      default_btn.callback()
      assert.truthy(default_res)
      assert.are.equal(2024, default_res.year)
      assert.are.equal(5, default_res.month)
      assert.are.equal(1, default_res.day)
    end)

    it("should handle extra button callback", function()
      local extra_called = false
      local widget = DateTimeWidget:new({
        hour = 8,
        min = 0,
        extra_text = "Now",
        extra_callback = function(self)
          extra_called = true
        end,
      })

      local btn_table = widget.date_frame[1][3][1]
      local extra_btn = btn_table.buttons[1][1]
      assert.are.equal("Now", extra_btn.text)

      extra_btn.callback()
      assert.is_true(extra_called)
    end)

    it("should handle apply and cancel callbacks", function()
      local applied = false
      local cancelled = false

      local widget = DateTimeWidget:new({
        hour = 10,
        min = 20,
        callback = function(self)
          applied = true
        end,
        cancel_callback = function(self)
          cancelled = true
        end,
      })

      local btn_table = widget.date_frame[1][3][1]
      local cancel_btn = btn_table.buttons[1][1]
      local apply_btn = btn_table.buttons[1][2]

      apply_btn.callback()
      assert.is_true(applied)
      assert.are.equal(10, widget.hour)
      assert.are.equal(20, widget.min)

      cancel_btn.callback()
      assert.is_true(cancelled)
    end)
  end)

  describe("Widget extension, updates, and lifecycle", function()
    it("should add custom widgets and return available width", function()
      local TextWidget = require("ui/widget/textwidget")
      local custom_text = TextWidget:new({ text = "Timezone: UTC" })

      local widget = DateTimeWidget:new({
        hour = 12,
        min = 0,
      })

      widget:addWidget(custom_text)
      assert.truthy(widget:getAddedWidgetAvailableWidth())
    end)

    it("should update picker values via update method", function()
      local widget = DateTimeWidget:new({
        year = 2020,
        month = 1,
        day = 1,
        hour = 0,
        min = 0,
        sec = 0,
      })

      widget:update(2025, 12, 31, 23, 59, 59)
      assert.are.equal(2025, widget.year_widget.value)
      assert.are.equal(12, widget.month_widget.value)
      assert.are.equal(31, widget.day_widget.value)
      assert.are.equal(23, widget.hour_widget.value)
      assert.are.equal(59, widget.min_widget.value)
      assert.are.equal(59, widget.sec_widget.value)
    end)

    it("should handle onShow, onClose, and onTapClose", function()
      local dirty_called = false
      UIManager.setDirty = function()
        dirty_called = true
      end

      local widget = DateTimeWidget:new({
        hour = 12,
        min = 0,
      })

      assert.is_true(widget:onShow())
      assert.is_true(dirty_called)

      widget:onClose()

      -- Tap inside vs outside
      widget.date_frame.dimen = Geom:new({ x = 100, y = 100, w = 200, h = 200 })

      local inside_ev = { pos = Geom:new({ x = 150, y = 150, w = 1, h = 1 }) }
      assert.is_true(widget:onTapClose(nil, inside_ev))

      local outside_ev = { pos = Geom:new({ x = 10, y = 10, w = 1, h = 1 }) }
      assert.is_true(widget:onTapClose(nil, outside_ev))
    end)
  end)
end)
