local Dispatcher
local UIManager
local Event

describe("dispatcher", function()
  local captured_inputs = {}
  local captured_broadcasts = {}

  setup(function()
    require("commonrequire")
    UIManager = require("ui/uimanager")
    Event = require("ui/event")
    Dispatcher = require("dispatcher")

    UIManager.userInput = function(_, event)
      if type(event) == "string" then
        event = Event:new(event)
      end
      table.insert(captured_inputs, event)
    end

    UIManager.broadcastEvent = function(_, event)
      if type(event) == "string" then
        event = Event:new(event)
      end
      table.insert(captured_broadcasts, event)
    end
  end)

  before_each(function()
    captured_inputs = {}
    captured_broadcasts = {}
  end)

  describe("registerAction and removeAction", function()
    after_each(function()
      Dispatcher:removeAction("test_action")
    end)

    it("registers and removes custom action successfully", function()
      package.loaded["apps/reader/readerui"] = {
        instance = {
          paging = true,
        },
      }

      local action_def = {
        category = "none",
        event = "MyCustomEvent",
        reader = true,
      }

      -- Should register custom action
      assert.is_true(Dispatcher:registerAction("test_action", action_def))

      -- Should trigger the event upon execution
      Dispatcher:execute({ test_action = true })
      assert.are.equal(1, #captured_inputs)
      assert.are.equal("onMyCustomEvent", captured_inputs[1].handler)

      -- Should remove custom action
      assert.is_true(Dispatcher:removeAction("test_action"))

      -- Execution should no longer trigger the event
      captured_inputs = {}
      Dispatcher:execute({ test_action = true })
      assert.are.equal(0, #captured_inputs)
    end)
  end)

  describe("isActionEnabled", function()
    it("handles condition-based activation", function()
      assert.is_true(Dispatcher:isActionEnabled({}))
      assert.is_true(Dispatcher:isActionEnabled({ condition = true }))
      assert.is_false(Dispatcher:isActionEnabled({ condition = false }))
    end)

    it("handles FileManager context when reader context is missing", function()
      package.loaded["apps/reader/readerui"] = {
        instance = nil,
      }

      -- Should be disabled if it's reader only
      assert.is_false(Dispatcher:isActionEnabled({ reader = true }))
      assert.is_false(Dispatcher:isActionEnabled({ paging = true }))
      assert.is_false(Dispatcher:isActionEnabled({ rolling = true }))

      -- Should be enabled if not restricted or explicitly filemanager
      assert.is_true(Dispatcher:isActionEnabled({ filemanager = true }))
      assert.is_true(
        Dispatcher:isActionEnabled({ filemanager = true, reader = true })
      )
    end)

    it("handles Paging Reader context", function()
      package.loaded["apps/reader/readerui"] = {
        instance = {
          paging = true,
        },
      }

      assert.is_true(Dispatcher:isActionEnabled({ reader = true }))
      assert.is_true(Dispatcher:isActionEnabled({ paging = true }))
      assert.is_false(Dispatcher:isActionEnabled({ rolling = true }))
    end)

    it("handles Rolling Reader context", function()
      package.loaded["apps/reader/readerui"] = {
        instance = {
          paging = false,
        },
      }

      assert.is_true(Dispatcher:isActionEnabled({ reader = true }))
      assert.is_false(Dispatcher:isActionEnabled({ paging = true }))
      assert.is_true(Dispatcher:isActionEnabled({ rolling = true }))
    end)
  end)

  describe("execute categories", function()
    setup(function()
      package.loaded["apps/reader/readerui"] = {
        instance = {
          paging = true,
        },
      }
    end)

    after_each(function()
      Dispatcher:removeAction("test_action")
    end)

    it("handles category 'none' without arguments", function()
      Dispatcher:registerAction("test_action", {
        category = "none",
        event = "EventNone",
        reader = true,
      })

      Dispatcher:execute({ test_action = true })
      assert.are.equal(1, #captured_inputs)
      assert.are.equal("onEventNone", captured_inputs[1].handler)
      assert.are.equal(0, captured_inputs[1].args.n)
    end)

    it("handles category 'none' with static argument", function()
      Dispatcher:registerAction("test_action", {
        category = "none",
        event = "EventNoneWithArg",
        arg = "static_value",
        reader = true,
      })

      local exec_props = { gesture = "some_gesture" }
      Dispatcher:execute({ test_action = true }, exec_props)
      assert.are.equal(1, #captured_inputs)
      assert.are.equal("onEventNoneWithArg", captured_inputs[1].handler)
      assert.are.equal(2, captured_inputs[1].args.n)
      assert.are.equal("static_value", captured_inputs[1].args[1])
      assert.are.same(exec_props, captured_inputs[1].args[2])
    end)

    it("handles category 'absolutenumber'", function()
      Dispatcher:registerAction("test_action", {
        category = "absolutenumber",
        event = "EventAbsoluteNumber",
        reader = true,
      })

      Dispatcher:execute({ test_action = 42 })
      assert.are.equal(1, #captured_inputs)
      assert.are.equal("onEventAbsoluteNumber", captured_inputs[1].handler)
      assert.are.equal(1, captured_inputs[1].args.n)
      assert.are.equal(42, captured_inputs[1].args[1])
    end)

    it("handles category 'string'", function()
      Dispatcher:registerAction("test_action", {
        category = "string",
        event = "EventString",
        reader = true,
      })

      Dispatcher:execute({ test_action = "value_str" })
      assert.are.equal(1, #captured_inputs)
      assert.are.equal("onEventString", captured_inputs[1].handler)
      assert.are.equal(1, captured_inputs[1].args.n)
      assert.are.equal("value_str", captured_inputs[1].args[1])
    end)

    it("handles category 'arg' with gesture", function()
      Dispatcher:registerAction("test_action", {
        category = "arg",
        event = "EventArg",
        arg = "default_arg",
        reader = true,
      })

      Dispatcher:execute({ test_action = true }, { gesture = "swipe_down" })
      assert.are.equal(1, #captured_inputs)
      assert.are.equal("onEventArg", captured_inputs[1].handler)
      assert.are.equal(1, captured_inputs[1].args.n)
      assert.are.equal("swipe_down", captured_inputs[1].args[1])
    end)

    it("handles category 'arg' without gesture", function()
      Dispatcher:registerAction("test_action", {
        category = "arg",
        event = "EventArg",
        arg = "default_arg",
        reader = true,
      })

      Dispatcher:execute({ test_action = true })
      assert.are.equal(1, #captured_inputs)
      assert.are.equal("onEventArg", captured_inputs[1].handler)
      assert.are.equal(1, captured_inputs[1].args.n)
      assert.are.equal("default_arg", captured_inputs[1].args[1])
    end)

    it("handles category 'incrementalnumber' with value", function()
      Dispatcher:registerAction("test_action", {
        category = "incrementalnumber",
        event = "EventIncNum",
        reader = true,
      })

      Dispatcher:execute({ test_action = 3 })
      assert.are.equal(1, #captured_inputs)
      assert.are.equal("onEventIncNum", captured_inputs[1].handler)
      assert.are.equal(1, captured_inputs[1].args.n)
      assert.are.equal(3, captured_inputs[1].args[1])
    end)

    it("handles category 'incrementalnumber' with gesture", function()
      Dispatcher:registerAction("test_action", {
        category = "incrementalnumber",
        event = "EventIncNum",
        reader = true,
      })

      Dispatcher:execute({ test_action = 0 }, { gesture = "swipe_left" })
      assert.are.equal(1, #captured_inputs)
      assert.are.equal("onEventIncNum", captured_inputs[1].handler)
      assert.are.equal(1, captured_inputs[1].args.n)
      assert.are.equal("swipe_left", captured_inputs[1].args[1])
    end)

    it("handles batched updates for multiple actions", function()
      Dispatcher:registerAction("test_action1", {
        category = "none",
        event = "Event1",
        reader = true,
      })
      Dispatcher:registerAction("test_action2", {
        category = "none",
        event = "Event2",
        reader = true,
      })

      -- We use ordered settings list or simple settings map
      -- If we pass simple map, order is arbitrary, but both should be triggered
      Dispatcher:execute({ test_action1 = true, test_action2 = true })

      Dispatcher:removeAction("test_action1")
      Dispatcher:removeAction("test_action2")

      assert.are.equal(2, #captured_inputs)
      local event_names =
        { captured_inputs[1].handler, captured_inputs[2].handler }
      table.sort(event_names)
      assert.are.same({ "onEvent1", "onEvent2" }, event_names)

      -- Should also broadcast BatchedUpdate and BatchedUpdateDone
      assert.are.equal(2, #captured_broadcasts)
      assert.are.equal("onBatchedUpdate", captured_broadcasts[1].handler)
      assert.are.equal("onBatchedUpdateDone", captured_broadcasts[2].handler)
    end)

    it("handles configurable and notification in execute", function()
      local Notification = require("ui/widget/notification")
      local old_notify = Notification.notify
      local notified_text
      Notification.notify = function(_, text)
        notified_text = text
      end

      Dispatcher:registerAction("test_conf", {
        category = "string",
        event = "SetMargin",
        reader = true,
        args = { "small", "large" },
        configurable = {
          name = "margin_size",
          values = { 10, 50 },
        },
      })

      local settings = {
        test_conf = "large",
        settings = {
          notify = true,
          name = "My Profile",
          order = { "test_conf" },
        },
      }

      Dispatcher:execute(settings)

      Dispatcher:removeAction("test_conf")
      Notification.notify = old_notify

      assert.is_truthy(notified_text)
      -- Check ConfigChange input event
      local config_change = false
      for _, ev in ipairs(captured_inputs) do
        if ev.handler == "onConfigChange" then
          config_change = true
          assert.are.equal("margin_size", ev.args[1])
          assert.are.equal(50, ev.args[2])
        end
      end
      assert.is_true(config_change)
    end)
  end)

  describe("helper and UI methods", function()
    setup(function()
      Dispatcher:init()
    end)

    it("getNameFromItem formats titles correctly", function()
      assert.are.equal("Unknown item", Dispatcher:getNameFromItem("non_existent_key"))

      -- none category
      assert.are.equal("Reading progress", Dispatcher:getNameFromItem("reading_progress"))

      -- string / configurable category with table
      Dispatcher:registerAction("test_table_val", {
        category = "string",
        title = "Table Option",
        unit = "pt",
      })
      assert.are.equal("Table Option: 10 / 20 pt", Dispatcher:getNameFromItem("test_table_val", { test_table_val = { 10, 20 } }))
      Dispatcher:removeAction("test_table_val")

      -- string with args_func
      Dispatcher:registerAction("test_dynamic_args", {
        category = "string",
        title = "Dynamic",
        args_func = function()
          return { "opt1", "opt2" }, { "Option One", "Option Two" }
        end,
      })
      assert.are.equal("Dynamic: Option One", Dispatcher:getNameFromItem("test_dynamic_args", { test_dynamic_args = "opt1" }))
      Dispatcher:removeAction("test_dynamic_args")

      -- absolutenumber
      Dispatcher:registerAction("test_abs_num", {
        category = "absolutenumber",
        title = "Brightness",
        unit = "%",
      })
      assert.are.equal("Brightness: 75 %", Dispatcher:getNameFromItem("test_abs_num", { test_abs_num = 75 }))
      Dispatcher:removeAction("test_abs_num")

      -- incrementalnumber
      Dispatcher:registerAction("test_inc_num", {
        category = "incrementalnumber",
        title = "Scroll",
      })
      assert.are.equal("Scroll: gesture distance", Dispatcher:getNameFromItem("test_inc_num", { test_inc_num = 0 }))
      assert.are.equal("Scroll: 10", Dispatcher:getNameFromItem("test_inc_num", { test_inc_num = 10 }))
      Dispatcher:removeAction("test_inc_num")
    end)

    it("getArgFromValue maps configurable values to args", function()
      Dispatcher:registerAction("test_map", {
        category = "string",
        args = { "small", "medium", "large" },
        configurable = {
          values = { 10, 20, 30 },
        },
      })
      assert.are.equal("medium", Dispatcher:getArgFromValue("test_map", 20))
      Dispatcher:removeAction("test_map")
    end)

    it("manages order via _addToOrder and _removeFromOrder", function()
      local loc = {
        prof = {
          reading_progress = true,
          history = true,
        },
      }
      -- add all
      Dispatcher:_addToOrder(loc, "prof", nil)
      assert.is_not_nil(loc.prof.settings.order)
      assert.are.equal(2, #loc.prof.settings.order)

      -- add specific
      Dispatcher:_addToOrder(loc, "prof", "favorites")
      assert.is_true(require("util").arrayContains(loc.prof.settings.order, "favorites") ~= false)

      -- remove specific
      Dispatcher:_removeFromOrder(loc, "prof", "favorites")
      assert.is_false(require("util").arrayContains(loc.prof.settings.order, "favorites") ~= false)

      -- remove all
      Dispatcher:_removeFromOrder(loc, "prof", nil)
      assert.is_nil(loc.prof.settings)
    end)

    it("menuTextFunc returns correct strings", function()
      assert.are.equal("Pass through", Dispatcher:menuTextFunc(nil))
      assert.are.equal("Nothing", Dispatcher:menuTextFunc({}))
      assert.are.equal("Reading progress", Dispatcher:menuTextFunc({ reading_progress = true }))
      local multi = Dispatcher:menuTextFunc({ reading_progress = true, history = true })
      assert.is_truthy(multi:match("actions"))
    end)

    it("getDisplayList returns items matching conditions", function()
      Dispatcher:registerAction("test_cond_true", {
        category = "none",
        title = "Enabled Cond",
        condition = true,
      })
      Dispatcher:registerAction("test_cond_false", {
        category = "none",
        title = "Disabled Cond",
        condition = false,
      })

      local list = Dispatcher:getDisplayList({
        test_cond_true = true,
        test_cond_false = true,
        settings = { order = { "test_cond_true", "test_cond_false" } },
      })

      assert.are.equal(1, #list)
      assert.are.equal("Enabled Cond", list[1].text)
      assert.are.equal("test_cond_true", list[1].key)

      Dispatcher:removeAction("test_cond_true")
      Dispatcher:removeAction("test_cond_false")
    end)

    it("builds menus with addSubMenu and _addItem callbacks", function()
      local caller = { updated = false }
      local menus = {}
      local location = {
        my_prof = {
          reading_progress = true,
          font_size = 20,
        },
      }

      Dispatcher:addSubMenu(caller, menus, location, "my_prof")
      assert.is_true(#menus > 0)

      -- Find Nothing item
      local nothing_item = menus[1]
      assert.are.equal("Nothing", nothing_item.text)
      nothing_item.callback({ updateItems = function() end })
      assert.is_true(caller.updated)
      assert.are.equal(0, Dispatcher:_itemsCount(location.my_prof))

      -- Trigger section submenu callbacks and checked_func
      for _, m in ipairs(menus) do
        if m.sub_item_table then
          if m.checked_func then m.checked_func() end
          if m.hold_callback then m.hold_callback({ updateItems = function() end }) end
          for _, sub in ipairs(m.sub_item_table) do
            if sub.checked_func then sub.checked_func() end
            if sub.callback then
              -- mock UIManager:show for spin/sort widgets
              local old_show = UIManager.show
              UIManager.show = function(_, widget)
                if widget and widget.callback then
                  widget.value = widget.value or 10
                  widget.callback(widget)
                end
              end
              pcall(sub.callback, { updateItems = function() end })
              UIManager.show = old_show
            end
            if sub.hold_callback then
              pcall(sub.hold_callback, { updateItems = function() end })
            end
            if sub.sub_item_table then
              for _, subsub in ipairs(sub.sub_item_table) do
                if subsub.checked_func then subsub.checked_func() end
                if subsub.callback then pcall(subsub.callback) end
              end
            end
          end
        end
        if m.text == "Arrange actions" then
          if m.checked_func then m.checked_func() end
          local old_show = UIManager.show
          UIManager.show = function(_, widget)
            if widget and widget.callback then widget.callback() end
          end
          pcall(m.callback, { updateItems = function() end })
          if m.hold_callback then pcall(m.hold_callback, { updateItems = function() end }) end
          UIManager.show = old_show
        elseif m.text == "Show as QuickMenu" then
          m.callback()
          assert.is_true(location.my_prof.settings.show_as_quickmenu)
          m.callback()
          assert.is_nil(location.my_prof.settings and location.my_prof.settings.show_as_quickmenu)
        elseif m.text == "Keep QuickMenu open" then
          m.callback()
          assert.is_true(location.my_prof.settings.keep_open_on_apply)
          m.callback()
          assert.is_nil(location.my_prof.settings and location.my_prof.settings.keep_open_on_apply)
        end
      end
    end)

    it("_showAsMenu opens QuickMenu and executes actions", function()
      local shown_dialog
      local old_show = UIManager.show
      local old_close = UIManager.close
      UIManager.show = function(_, w) shown_dialog = w end
      UIManager.close = function(_, w) end

      local settings = {
        reading_progress = true,
        settings = {
          name = "Test QM",
          show_as_quickmenu = true,
          order = { "reading_progress" },
        },
      }

      Dispatcher:execute(settings, { qm_show = true })
      assert.is_not_nil(shown_dialog)
      assert.are.equal("Test QM", shown_dialog.title)

      -- Test button callback in quickmenu
      assert.is_truthy(#shown_dialog.buttons >= 1)
      local exec_all_btn = shown_dialog.buttons[1][1]
      exec_all_btn.callback()

      UIManager.show = old_show
      UIManager.close = old_close
    end)
  end)
end)

