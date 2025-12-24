--[[--
This module manages widgets.
]]

local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local dbg = require("dbg")
local logger = require("logger")
local ffiUtil = require("ffi/util")
local util = require("util")
local time = require("ui/time")
local _ = require("gettext")
local Input = Device.input
local Screen = Device.screen

-- This is a singleton
local UIManager = {
  FULL_REFRESH_COUNT = G_named_settings.default.full_refresh_count(),
  refresh_count = 0,

  -- How long to wait between ZMQ wakeups: 50ms.
  ZMQ_TIMEOUT = 50 * 1000,

  event_handlers = nil,

  _window_stack = {},
  _task_queue = {},
  _task_queue_dirty = false,
  _dirty = {},
  _zeromqs = {},
  _refresh_stack = {},
  _refresh_func_stack = {},
  _entered_poweroff_stage = false,
  _exit_code = nil,
  _gated_quit = nil,
  _prevent_standby_count = 0,
  _prev_prevent_standby_count = 0,
  _input_gestures_disabled = false,
  _last_user_action_time = 0,
  _force_fast_refresh = false,
}

function UIManager:init()
  self.event_handlers = {
    Power = function(input_event)
      Device:handlePowerEvent(input_event)
    end,
    -- This is for hotpluggable evdev input devices (e.g., USB OTG)
    UsbDevicePlugIn = function(input_event)
      -- Retrieve the argument set by Input:handleKeyBoardEv
      local evdev = table.remove(Input.fake_event_args[input_event])
      local path = "/dev/input/event" .. tostring(evdev)

      self:broadcastEvent(Event:new("EvdevInputInsert", path))
    end,
    UsbDevicePlugOut = function(input_event)
      local evdev = table.remove(Input.fake_event_args[input_event])
      local path = "/dev/input/event" .. tostring(evdev)

      self:broadcastEvent(Event:new("EvdevInputRemove", path))
    end,
  }
  self.poweroff_action = function()
    self._entered_poweroff_stage = true
    logger.info("Powering off the device...")
    self:broadcastEvent(Event:new("PowerOff"))
    self:broadcastEvent("ExitKOReader")
    local Screensaver = require("ui/screensaver")
    Screensaver:setup("poweroff", _("Powered off"))
    Screensaver:show()
    self:nextTick(function()
      Device:saveSettings()
      Device:powerOff()
      if Device:isKobo() then
        self:quit(88)
      else
        self:quit()
      end
    end)
  end
  self.reboot_action = function()
    self._entered_poweroff_stage = true
    logger.info("Rebooting the device...")
    self:broadcastEvent(Event:new("Reboot"))
    self:broadcastEvent("ExitKOReader")
    local Screensaver = require("ui/screensaver")
    Screensaver:setup("reboot", _("Rebooting…"))
    Screensaver:show()
    self:nextTick(function()
      Device:saveSettings()
      Device:reboot()
      if Device:isKobo() then
        self:quit(88)
      else
        self:quit()
      end
    end)
  end

  -- The first user action is always the one starts koreader.
  self:updateLastUserActionTime()
  self:updateRefreshRate()

  -- Tell Device that we're now available, so that it can setup PM event handlers
  Device:_UIManagerReady(self)

  -- A simple wrapper for UIManager:quit()
  -- This may be overwritten by setRunForeverMode(); for testing purposes
  self:unsetRunForeverMode()
end

-- Crappy wrapper because of circular dependencies
function UIManager:setIgnoreTouchInput(state)
  local InputContainer = require("ui/widget/container/inputcontainer")
  InputContainer:setIgnoreTouchInput(state)
end

function UIManager:_widgetDebugStr(widget)
  assert(widget ~= nil)
  return widget.name or widget.id or tostring(widget)
end

--[[--
Registers and shows a widget.

Widgets are registered in a stack, from bottom to top in registration order,
with a few tweaks to handle modals & toasts:
toast widgets are stacked together on top,
then modal widgets are stacked together, and finally come standard widgets.

If you think about how painting will be handled (also bottom to top), this makes perfect sense ;).

For more details about refreshtype, refreshregion & refreshdither see the description of `setDirty`.
If refreshtype is omitted, no refresh will be enqueued at this time.

@param widget a @{ui.widget.widget|widget} object
]]
function UIManager:show(widget)
  -- TODO: Should assert
  if not widget then
    logger.dbg("attempted to show a nil widget")
    return
  end
  assert(not self:isWidgetShown(widget))

  logger.dbg("show widget:", self:_widgetDebugStr(widget))

  -- The window x and y are never used.
  local window = { x = 0, y = 0, widget = widget }
  -- put this window on top of the topmost non-modal window
  for i = #self._window_stack, 0, -1 do
    local top_window = self._window_stack[i]
    -- toasts are stacked on top of other toasts,
    -- then come modals, and then other widgets
    if top_window and top_window.widget.toast then
      if widget.toast then
        table.insert(self._window_stack, i + 1, window)
        break
      end
    elseif widget.modal or not top_window or not top_window.widget.modal then
      table.insert(self._window_stack, i + 1, window)
      break
    end
  end
  self._dirty[widget] = true
  -- tell the widget that it is shown now
  widget:handleEvent(Event:new("Show"))
  -- check if this widget disables double tap gesture
  Input.disable_double_tap = widget.disable_double_tap ~= false
  -- a widget may override tap interval (when it doesn't, nil restores the default)
  Input.tap_interval_override = widget.tap_interval_override
  -- If input was disabled, re-enable it while this widget is shown so we can actually interact with it.
  -- The only thing that could actually call show in this state is something automatic, so we need to be able to deal with it.
  if UIManager._input_gestures_disabled then
    logger.dbg(
      "Gestures were disabled, temporarily re-enabling them to allow interaction with widget"
    )
    self:setIgnoreTouchInput(false)
    widget._restored_input_gestures = true
  end
end

--[[--
Unregisters a widget.

It will be removed from the stack.
Will flag uncovered widgets as dirty.

For more details about refreshtype, refreshregion & refreshdither see the description of `setDirty`.
If refreshtype is omitted, no extra refresh will be enqueued at this time, leaving only those from the uncovered widgets.

@param widget a @{ui.widget.widget|widget} object
]]
function UIManager:close(widget)
  -- TODO: Should assert
  if not widget then
    logger.dbg("attempted to close a nil widget")
    return
  end
  logger.dbg("close widget:", widget.name or widget.id or tostring(widget))
  local dirty = false
  -- First notify the closed widget to save its settings...
  widget:broadcastEvent(Event:new("FlushSettings"))
  -- ...and notify it that it ought to be gone now.
  widget:broadcastEvent(Event:new("Close"))
  -- Make sure it's disabled by default and check if there are any widgets that want it disabled or enabled.
  Input.disable_double_tap = true
  local requested_disable_double_tap = nil
  -- Then remove all references to that widget on stack and refresh.
  for i = #self._window_stack, 1, -1 do
    local w = self._window_stack[i].widget
    if w == widget then
      self._dirty[w] = nil
      self:_scheduleRefreshWindowWidget(self._window_stack[i])
      table.remove(self._window_stack, i)
      dirty = true
    else
      if w.dithered then
        logger.dbg(
          "Lower widget",
          self:_widgetDebugStr(w),
          "was dithered, honoring the dithering hint"
        )
      end
      -- Set double tap to how the topmost widget with that flag wants it
      if
        requested_disable_double_tap == nil and w.disable_double_tap ~= nil
      then
        requested_disable_double_tap = w.disable_double_tap
      end
    end
  end
  if requested_disable_double_tap ~= nil then
    Input.disable_double_tap = requested_disable_double_tap
  end
  if self._window_stack[1] then
    -- set tap interval override to what the topmost widget specifies (when it doesn't, nil restores the default)
    Input.tap_interval_override =
      self._window_stack[#self._window_stack].widget.tap_interval_override
  end
  if dirty then
    -- TODO: Similar to the UIManager:show, an optimization can be calculating
    -- the covered area and not repainting all the invisible widgets, but it's
    -- hard to demonstrate the imporantce.
    for i = 1, #self._window_stack do
      self._dirty[self._window_stack[i].widget] = true
    end
  end
  if widget._restored_input_gestures then
    logger.dbg("Widget is gone, disabling gesture handling again")
    self:setIgnoreTouchInput(true)
  end
end

--- Shift the execution times of all scheduled tasks.
-- UIManager uses CLOCK_MONOTONIC (which doesn't tick during standby), so shifting the execution
-- time by a negative value will lead to an execution at the expected time.
-- @param time if positive execute the tasks later, if negative they should be executed earlier
function UIManager:shiftScheduledTasksBy(shift_time)
  for i, v in ipairs(self._task_queue) do
    v.time = v.time + shift_time
  end
end

-- Schedule an execution task; task queue is in descending order
function UIManager:schedule(sched_time, action, ...)
  local lo, hi = 1, #self._task_queue
  -- Leftmost binary insertion
  while lo <= hi do
    -- NOTE: We should be (mostly) free from overflow here, thanks to LuaJIT's BitOp semantics.
    --     For more fun details about this particular overflow,
    --     c.f., https://ai.googleblog.com/2006/06/extra-extra-read-all-about-it-nearly.html
    -- NOTE: For more fun reading about the binary search algo in general,
    --     c.f., https://reprog.wordpress.com/2010/04/19/are-you-one-of-the-10-percent/
    local mid = bit.rshift(lo + hi, 1)
    local mid_time = self._task_queue[mid].time
    if mid_time <= sched_time then
      hi = mid - 1
    else
      lo = mid + 1
    end
  end

  table.insert(self._task_queue, lo, {
    time = sched_time,
    action = action,
    args = table.pack(...),
  })
  self._task_queue_dirty = true
end
dbg:guard(UIManager, "schedule", function(self, sched_time, action)
  assert(sched_time >= 0, "Only positive time allowed")
  assert(action ~= nil, "No action")
end)

--[[--
Schedules a task to be run a certain amount of seconds from now.

@number seconds scheduling delay in seconds (supports decimal values, 1ms resolution).
@func action reference to the task to be scheduled (may be anonymous)
@param ... optional arguments passed to action

@see unschedule
]]
function UIManager:scheduleIn(seconds, action, ...)
  -- We might run significantly late inside an UI frame, so we can't use the cached value here.
  -- It would also cause some bad interactions with the way nextTick & co behave.
  local when = time.monotonic() + time.s(seconds)
  self:schedule(when, action, ...)
end
dbg:guard(UIManager, "scheduleIn", function(self, seconds, action)
  assert(seconds >= 0, "Only positive seconds allowed")
end)

--[[--
Schedules a task for the next UI tick.

@func action reference to the task to be scheduled (may be anonymous)
@param ... optional arguments passed to action
@see scheduleIn
]]
function UIManager:nextTick(action, ...)
  return self:scheduleIn(0, action, ...)
end

--[[--
Schedules a task to be run two UI ticks from now.

Useful to run UI callbacks ASAP without skipping repaints.

@func action reference to the task to be scheduled (may be anonymous)
@param ... optional arguments passed to action

@return A reference to the initial nextTick wrapper function,
necessary if the caller wants to unschedule action *before* it actually gets inserted in the task queue by nextTick.
@see nextTick
]]
function UIManager:tickAfterNext(action, ...)
  -- We need to keep a reference to this anonymous function, as it is *NOT* quite `action` yet,
  -- and the caller might want to unschedule it early...
  local action_wrapper = function(...)
    self:nextTick(action, ...)
  end
  self:nextTick(action_wrapper, ...)

  return action_wrapper
end
--[[
-- NOTE: This appears to work *nearly* just as well, but does sometimes go too fast (might depend on kernel HZ & NO_HZ settings?)
function UIManager:tickAfterNext(action)
  return self:scheduleIn(0.001, action)
end
--]]

function UIManager:debounce(seconds, immediate, action)
  -- Ported from underscore.js
  local args = nil
  local previous_call_at = nil
  local is_scheduled = false
  local result = nil

  local scheduled_action
  scheduled_action = function()
    local passed_from_last_call = time.since(previous_call_at)
    if seconds > passed_from_last_call then
      self:scheduleIn(seconds - passed_from_last_call, scheduled_action)
      is_scheduled = true
    else
      is_scheduled = false
      if not immediate then
        result = action(unpack(args, 1, args.n))
      end
      if not is_scheduled then
        -- This check is needed because action can recursively call debounced_action_wrapper
        args = nil
      end
    end
  end
  local debounced_action_wrapper = function(...)
    args = table.pack(...)
    previous_call_at = time.monotonic()
    if not is_scheduled then
      self:scheduleIn(seconds, scheduled_action)
      is_scheduled = true
      if immediate then
        result = action(unpack(args, 1, args.n))
      end
    end
    return result
  end

  return debounced_action_wrapper
end

--[[--
Unschedules a previously scheduled task.

In order to unschedule anonymous functions, store a reference.

@func action
@see scheduleIn

@usage

self.anonymousFunction = function() self:regularFunction() end
UIManager:scheduleIn(10.5, self.anonymousFunction)
UIManager:unschedule(self.anonymousFunction)
]]
function UIManager:unschedule(action)
  local removed = false
  for i = #self._task_queue, 1, -1 do
    if self._task_queue[i].action == action then
      table.remove(self._task_queue, i)
      removed = true
    end
  end
  return removed
end
dbg:guard(UIManager, "unschedule", function(self, action)
  assert(action ~= nil)
end)

-- A workaround to handle most of the existing logic
function UIManager:setDirty(widget, refreshMode, region)
  if type(refreshMode) == "function" then
    -- Have to repaint the widget first; still use :setDirty to handle various
    -- conditions of the widget itself.
    if widget ~= nil then
      self:setDirty(widget)
    end
    table.insert(self._refresh_func_stack, function()
      local m, r = refreshMode()
      r = region or r
      if widget ~= nil then
        r = r or widget.dimen
      end
      self:scheduleRefresh(m, r, widget ~= nil and widget.dithered)
    end)
    return
  end
  if widget == nil then
    self:scheduleRefresh(refreshMode, region)
    return
  end
  if widget == "all" then
    self:scheduleRepaintAll(refreshMode)
    return
  end
  self:scheduleWidgetRepaint(widget, refreshMode)
end
--[[
-- NOTE: While nice in theory, this is *extremely* verbose in practice,
--     because most widgets will call setDirty at least once during their initialization,
--     and that happens before they make it to the window stack...
--     Plus, setDirty(nil, ...) is a completely valid use-case with documented semantics...
dbg:guard(UIManager, 'setDirty',
  nil,
  function(self, widget, refreshtype, refreshregion, refreshdither)
    if not widget or widget == "all" then return end
    -- when debugging, we check if we were handed a valid window-level widget,
    -- which would be a widget that was previously passed to `show`.
    local found = false
    for i = 1, #self._window_stack do
      if self._window_stack[i].widget == widget then
        found = true
        break
      end
    end
    if not found then
      dbg:v("INFO: invalid widget for setDirty()", debug.traceback())
    end
  end)
--]]

--[[--
Clear the full repaint & refresh queues.

NOTE: Beware! This doesn't take any prisonners!
You shouldn't have to resort to this unless in very specific circumstances!
plugins/coverbrowser.koplugin/covermenu.lua building a franken-menu out of buttondialog
and wanting to avoid inheriting their original paint/refresh cycle being a prime example.
--]]
function UIManager:clearRenderStack()
  logger.dbg("clearRenderStack: Clearing the full render stack!")
  self._dirty = {}
  self._refresh_func_stack = {}
  self._refresh_stack = {}
end

function UIManager:insertZMQ(zeromq)
  table.insert(self._zeromqs, zeromq)
  return zeromq
end

function UIManager:removeZMQ(zeromq)
  for i = #self._zeromqs, 1, -1 do
    if self._zeromqs[i] == zeromq then
      table.remove(self._zeromqs, i)
    end
  end
end

--- Returns the full refresh rate for e-ink screens (`FULL_REFRESH_COUNT`).
function UIManager:updateRefreshRate()
  local function refresh_count()
    local r = G_named_settings.full_refresh_count()
    -- Never fully refresh screen.
    if r == 0 then
      return 0
    end
    -- Double the refresh rate in night_mode, black area would be way larger,
    -- and causes more blur.
    if G_reader_settings:isTrue("night_mode") then
      r = math.floor(refresh_count / 2)
    end
    if r < 1 then
      return 1
    end
    return r
  end
  self.FULL_REFRESH_COUNT = refresh_count()
end

function UIManager:toggleNightMode()
  self:onRotation()
  self:updateRefreshRate()
end

--- Get n.th topmost widget
function UIManager:getNthTopWidget(n)
  n = n and n - 1 or 0
  if #self._window_stack - n < 1 then
    -- No or not enough widgets in the stack, bye!
    return nil
  end

  local widget = self._window_stack[#self._window_stack - n].widget
  return widget
end

--- Top-to-bottom widgets iterator
--- NOTE: VirtualKeyboard can be instantiated multiple times, and is a modal,
--    so don't be surprised if you find a couple of instances of it at the top ;).
function UIManager:topdown_widgets_iter()
  local n = #self._window_stack
  local i = n + 1
  return function()
    i = i - 1
    if i > 0 then
      return self._window_stack[i].widget
    end
  end
end

--- Get the topmost visible widget
function UIManager:getTopmostVisibleWidget()
  for i = #self._window_stack, 1, -1 do
    local widget = self._window_stack[i].widget
    -- This is a dirty hack to skip invisible widgets (i.e., TrapWidget)
    if not widget.invisible then
      return widget
    end
  end
end

--- Same as `isSubwidgetShown`, but only check window-level widgets (e.g., what's directly registered in the window stack), don't recurse.
function UIManager:isWidgetShown(widget)
  for i = #self._window_stack, 1, -1 do
    if self._window_stack[i].widget == widget then
      return true
    end
  end
  return false
end

--- Signals to quit.
-- An exit_code of false is not allowed.
function UIManager:quit(exit_code, implicit)
  if exit_code == false then
    logger.err("UIManager:quit() called with false")
    return
  end
  -- Also honor older exit codes; default to 0
  self._exit_code = exit_code or self._exit_code or 0
  if not implicit then
    -- Explicit call via UIManager:quit (as opposed to self:_gated_quit)
    if exit_code then
      logger.info("Preparing to quit UIManager with exit code:", exit_code)
    else
      logger.info("Preparing to quit UIManager")
    end
  end
  self._task_queue_dirty = false
  self._window_stack = {}
  self._task_queue = {}
  for i = #self._zeromqs, 1, -1 do
    self._zeromqs[i]:stop()
  end
  self._zeromqs = {}
  if self.looper then
    self.looper:close()
    self.looper = nil
  end
  return self._exit_code
end
dbg:guard(UIManager, "quit", function(self, exit_code)
  assert(exit_code ~= false, "exit_code == false is not supported")
end)

-- Disable automatic UIManager quit; for testing purposes
function UIManager:setRunForeverMode()
  self._gated_quit = function()
    return false
  end
end

-- Enable automatic UIManager quit; for testing purposes
function UIManager:unsetRunForeverMode()
  self._gated_quit = function()
    return self:quit(nil, true)
  end
end

-- Ignore an empty window stack *once*; for startup w/ a missing last_file shenanigans...
function UIManager:runOnce()
  -- We don't actually want to call self.quit, and we need to deal with a bit of trickery in there anyway...
  self._gated_quit = function()
    -- We need this set to break the loop in UIManager:run()
    self._exit_code = 0
    -- And this is to break the loop in UIManager:handleInput()
    return true
  end
  -- The idea being that we want to *return* from this run call, but *without* quitting.
  -- NOTE: This implies that calling run multiple times across a single session *needs* to be safe.
  self:run()
  -- Restore standard behavior
  self:unsetRunForeverMode()
  self._exit_code = nil
end

--[[--
Transmits an @{ui.event.Event|Event} to active widgets, top to bottom.
Stops at the first handler that returns `true`.
Note that most complex widgets are based on @{ui.widget.container.WidgetContainer|WidgetContainer},
which itself will take care of propagating an event to its members.

@param event an @{ui.event.Event|Event} object or string, string will be
             converted to Event:new().
]]
function UIManager:userInput(event)
  if type(event) == "string" then
    event = Event:new(event)
  end
  event:asUserInput()
  local top_widget
  local checked_widgets = {}
  -- Toast widgets, which, by contract, must be at the top of the window stack, never stop event propagation.
  for i = #self._window_stack, 1, -1 do
    local widget = self._window_stack[i].widget
    -- Whether it's a toast or not, we'll call handleEvent now,
    -- so we'll want to skip it during the table walk later.
    checked_widgets[widget] = true
    if widget.toast then
      -- We never stop event propagation on toasts, but we still want to send the event to them.
      -- (In particular, because we want them to close on user input).
      widget:handleEvent(event)
    else
      -- The first widget to consume events as designed is the topmost non-toast one
      top_widget = widget
      break
    end
  end

  -- Extremely unlikely, but we can't exclude the possibility of *everything* being a toast ;).
  -- In which case, the event has nowhere else to go, so, we're done.
  if not top_widget then
    return
  end

  if top_widget:handleEvent(event) then
    return
  end

  -- If the event was not consumed (no handler returned true), active widgets (from top to bottom) can access it.
  -- NOTE: _window_stack can shrink/grow when widgets are closed (CloseWidget & Close events) or opened.
  --     Simply looping in reverse would only cover the list shrinking, and that only by a *single* element,
  --     something we can't really guarantee, hence the more dogged iterator below,
  --     which relies on a hash check of already processed widgets (LuaJIT actually hashes the table's GC reference),
  --     rather than a simple loop counter, and will in fact iterate *at least* #items ^ 2 times.
  --     Thankfully, that list should be very small, so the overhead should be minimal.
  local i = #self._window_stack
  while i > 0 do
    local widget = self._window_stack[i].widget
    if not checked_widgets[widget] then
      checked_widgets[widget] = true
      if widget.is_always_active then
        -- Widget itself is flagged always active, let it handle the event
        -- NOTE: is_always_active widgets are currently widgets that want to show a VirtualKeyboard or listen to Dispatcher events
        if widget:handleEvent(event) then
          return
        end
      end
      -- As mentioned above, event handlers might have shown/closed widgets,
      -- so all bets are off on our old window tally being accurate, so let's take it from the top again ;).
      i = #self._window_stack
    else
      i = i - 1
    end
  end
end

--[[--
Transmits an @{ui.event.Event|Event} to all registered widgets.

@param event an @{ui.event.Event|Event} object or string, string will be
             converted to Event:new()
]]
function UIManager:broadcastEvent(event)
  if type(event) == "string" then
    event = Event:new(event)
  end
  -- Unlike sendEvent, we send the event to *all* (window-level) widgets (i.e., we don't stop, even if a handler returns true).
  -- NOTE: Same defensive approach to _window_stack changing from under our feet as above.
  local checked_widgets = {}
  local i = #self._window_stack
  while i > 0 do
    local widget = self._window_stack[i].widget
    if not checked_widgets[widget] then
      checked_widgets[widget] = true
      widget:broadcastEvent(event)
      i = #self._window_stack
    else
      i = i - 1
    end
  end
end

--[[
function UIManager:getNextTaskTimes(count)
  count = math.min(count or 1, #self._task_queue)
  local times = {}
  for i = 1, count do
    times[i] = self._task_queue[i].time - time.monotonic()
  end
  return times
end
--]]

function UIManager:getNextTaskTime()
  local next_task = self._task_queue[#self._task_queue]
  if next_task then
    return next_task.time - time.monotonic()
  end
end

function UIManager:_checkTasks()
  local _now = time.monotonic()
  local wait_until = nil

  -- Tasks due for execution might themselves schedule more tasks (that might also be immediately due for execution ;)).
  -- Flipping this switch ensures we'll consume all such tasks *before* yielding to input polling.
  self._task_queue_dirty = false
  while self._task_queue[1] do
    local task_time = self._task_queue[#self._task_queue].time
    if task_time <= _now then
      -- Remove the upcoming task, as it is due for execution...
      local task = table.remove(self._task_queue)
      -- ...so do it now.
      -- NOTE: Said task's action might modify _task_queue.
      --     To avoid race conditions and catch new upcoming tasks during this call,
      --     we repeatedly check the head of the queue (c.f., #1758).
      task.action(unpack(task.args, 1, task.args.n))
    else
      -- As the queue is sorted in descending order, it's safe to assume all items are currently future tasks.
      wait_until = task_time
      break
    end
  end

  return wait_until, _now
end

--[[--
Returns a time (fts) corresponding to the last UI tick plus the time in standby.
]]
function UIManager:getElapsedTimeSinceBoot()
  return time.monotonic()
    + Device.total_standby_time
    + Device.total_suspend_time
end

function UIManager:lastUserActionTime()
  return self._last_user_action_time
end

function UIManager:updateLastUserActionTime()
  self._last_user_action_time = self:getElapsedTimeSinceBoot()
  if Device:isKindle() then
    -- Always reset the timeout timer when processing input event, even it's fake.
    Device:getPowerDevice():resetT1Timeout()
  end
end

function UIManager:timeSinceLastUserAction()
  return self:getElapsedTimeSinceBoot() - self:lastUserActionTime()
end

-- precedence of refresh modes:
local refresh_modes = {
  a2 = 1,
  fast = 2,
  ui = 3,
  partial = 4,
  ["[ui]"] = 5,
  ["[partial]"] = 6,
  flashui = 7,
  flashpartial = 8,
  full = 9,
}
-- NOTE: We might want to introduce a "force_a2" that points to fast, but has the highest priority,
--     for the few cases where we might *really* want to enforce fast (for stuff like panning or skimming?).
-- refresh methods in framebuffer implementation
local refresh_methods = {
  a2 = Screen.refreshA2,
  fast = Screen.refreshFast,
  ui = Screen.refreshUI,
  partial = Screen.refreshPartial,
  ["[ui]"] = Screen.refreshNoMergeUI,
  ["[partial]"] = Screen.refreshNoMergePartial,
  flashui = Screen.refreshFlashUI,
  flashpartial = Screen.refreshFlashPartial,
  full = Screen.refreshFull,
}

--[[
Compares refresh mode.

Will return the mode that takes precedence.
]]
local function update_mode(mode1, mode2)
  if refresh_modes[mode1] > refresh_modes[mode2] then
    logger.dbg("update_mode: Update refresh mode", mode2, "to", mode1)
    return mode1
  else
    return mode2
  end
end

--[[
Compares dither hints.

Dither always wins.
]]
local function update_dither(dither1, dither2)
  if dither1 and not dither2 then
    logger.dbg("update_dither: Update dither hint", dither2, "to", dither1)
    return dither1
  else
    return dither2
  end
end

function UIManager:forceFastRefresh()
  self._force_fast_refresh = true
end

function UIManager:resetForceFastRefresh()
  self._force_fast_refresh = false
end

function UIManager:duringForceFastRefresh()
  return self._force_fast_refresh
end

--[[--
Enqueues a refresh.

It's very uncommon to call this function directly out of UIManager, but it's
still usable. It notifies UIManager that a certain part of the screen needs to
be refreshed and will be performed later.

@string mode
  refresh mode (`"full"`, `"flashpartial"`, `"flashui"`, `"[partial]"`, `"[ui]"`, `"partial"`, `"ui"`, `"fast"`, `"a2"`)
@param region
  A rectangle @{ui.geometry.Geom|Geom} object that specifies the region to be updated.
  Optional, update will affect whole screen if not specified.
  Note that this should be the exception.
@bool dither
  A hint to request hardware dithering (if supported).
  Optional, no dithering requested if not specified or not supported.
]]
function UIManager:scheduleRefresh(mode, region, dither)
  if mode == nil then
    logger.warn("No mode provided when scheduleRefresh ", debug.traceback())
    return
  end

  assert(refresh_modes[mode] ~= nil, "Unknown refresh mode " .. tostring(mode))

  -- Downgrade all refreshes to "fast" when ReaderPaging or ReaderScrolling have set this flag
  if self:duringForceFastRefresh() then
    mode = "fast"
  end

  -- Handle downgrading flashing modes to non-flashing modes, according to user settings.
  -- NOTE: Do it before "full" promotion and collision checks/update_mode.
  if G_reader_settings:nilOrTrue("avoid_flashing_ui") then
    if mode == "flashui" then
      mode = "ui"
      logger.dbg("_refresh: downgraded flashui refresh to", mode)
    elseif mode == "flashpartial" then
      mode = "partial"
      logger.dbg("_refresh: downgraded flashpartial refresh to", mode)
    elseif mode == "partial" and region then
      mode = "ui"
      logger.dbg("_refresh: downgraded regional partial refresh to", mode)
    end
  else
    if mode == "fast" or mode == "a2" then
      mode = "flashui"
    end
  end

  -- if no region is specified, use the screen's dimensions
  region = region
    or Geom:new({ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() })

  -- if no dithering hint was specified, don't request dithering
  dither = dither or false

  -- NOTE: While, ideally, we shouldn't merge refreshes w/ different waveform modes,
  --     this allows us to optimize away a number of quirks of our rendering stack
  --     (e.g., multiple setDirty calls queued when showing/closing a widget because of update mechanisms),
  --     as well as a few actually effective merges
  --     (e.g., the disappearance of a selection HL with the following menu update).
  for i, refresh in ipairs(self._refresh_stack) do
    -- Check for collisions with refreshes that are already enqueued.
    -- NOTE: We use the open range variant, as we want to combine rectangles that share an edge (like the EPDC).
    if region:openIntersectWith(refresh.region) then
      -- combine both refreshes' regions
      local combined = region:combine(refresh.region)
      -- update the mode, if needed
      mode = update_mode(mode, refresh.mode)
      -- dithering hints are viral, one is enough to infect the whole queue
      dither = update_dither(dither, refresh.dither)
      -- remove colliding refresh
      table.remove(self._refresh_stack, i)
      -- and try again with combined data
      return self:scheduleRefresh(mode, combined, dither)
    end
  end

  -- if we've stopped hitting collisions, enqueue the refresh
  logger.dbg(
    "_refresh: Enqueued",
    mode,
    "update for region",
    region.x,
    region.y,
    region.w,
    region.h,
    "dithering:",
    dither
  )
  table.insert(
    self._refresh_stack,
    { mode = mode, region = region, dither = dither }
  )
end

function UIManager:_scheduleRefreshWindowWidget(window)
  assert(window ~= nil)
  local widget = window.widget
  local dimen = widget.dimen
  -- window.x and window.y are never used, but keept the potential logic right.
  if window.x > 0 or window.y > 0 then
    dimen = dimen:copy():offsetBy(window.x, window.y)
  end
  self:scheduleRefresh(widget:refreshMode(), dimen, widget.dithered)
end

--[[--
Repaints dirty widgets.

This will also drain the refresh queue, effectively refreshing the screen region(s) matching those freshly repainted widgets.

There may be refreshes enqueued without any widgets needing to be repainted (c.f., `setDirty`'s behavior when passed a `nil` widget),
in which case, nothing is repainted, but the refreshes are still drained and executed.

@local Not to be used outside of UIManager!
--]]
function UIManager:forceRepaint()
  -- flag in which we will record if we did any repaints at all
  -- will trigger a refresh if set.
  local dirty = false
  -- remember if any of our repaints were dithered
  local dithered = false

  -- TODO: A potential improvement is calculating the covered area from
  -- for i = #self._window_stack, 1, -1 do
  -- and ignore anything covered by other widget. But considering the number of
  -- widgets showing up in the stack, it's very hard to demonstrate if it's even
  -- necessary.

  for i = 1, #self._window_stack do
    local window = self._window_stack[i]
    local widget = window.widget
    -- paint if current widget or any widget underneath is dirty
    if dirty or self._dirty[widget] then
      -- pass hint to widget that we got when setting widget dirty
      -- the widget can use this to decide which parts should be refreshed
      logger.dbg("painting widget:", self:_widgetDebugStr(widget))
      Screen:beforePaint()
      widget:paintTo(Screen.bb, window.x, window.y)
      self:_scheduleRefreshWindowWidget(window)

      -- and remove from list after painting
      self._dirty[widget] = nil

      -- trigger a repaint for every widget above us, too
      dirty = true

      -- if any of 'em were dithered, we'll want to dither the final refresh
      if widget.dithered then
        logger.dbg("_repaint: it was dithered, infecting the refresh queue")
        dithered = true
      end
    end
  end

  if util.tableSize(self._dirty) > 0 then
    logger.warn("Found unrecognized widgets being scheduled to repaint. Ignored.")
    for _, widget in self._dirty do
      logger.warn("  Widget ", self:_widgetDebugStr(widget))
    end
    self._dirty = {}
  end

  -- execute pending refresh functions
  for _, refreshfunc in ipairs(self._refresh_func_stack) do
    refreshfunc()
  end
  self._refresh_func_stack = {}

  -- We should have at least one refresh if we did repaint.
  -- If we don't, add one now and log a warning if we are debugging.
  if dirty and not self._refresh_stack[1] then
    logger.dbg(
      "no refresh got enqueued. Will do a partial full screen refresh, which might be inefficient"
    )
    self:scheduleRefresh("partial")
  end

  if #self._refresh_stack > 0 then
    -- execute refreshes:
    for _, refresh in ipairs(self._refresh_stack) do
      -- Honor dithering hints from *anywhere* in the dirty stack
      refresh.dither = update_dither(refresh.dither, dithered)
      -- If HW dithering is disabled, unconditionally drop the dither flag
      if not Screen.hw_dithering then
        refresh.dither = nil
      end
      dbg:v("triggering refresh", refresh)

      local mode = refresh.mode
      -- special case: "partial" refreshes
      -- will get promoted every self.FULL_REFRESH_COUNT refreshes
      -- since _refresh can be called multiple times via setDirty called in
      -- different widgets before a real screen repaint, we should make sure
      -- refresh_count is incremented by only once at most for each repaint
      -- NOTE: Ideally, we'd only check for "partial"" w/ no region set (that neatly narrows it down to just the reader).
      --     In practice, we also want to promote refreshes in a few other places, except purely text-poor UI elements.
      --     (Putting "ui" in that list is problematic with a number of UI elements, most notably, ReaderHighlight,
      --     because it is implemented as "ui" over the full viewport, since we can't devise a proper bounding box).
      --     So we settle for only "partial", but treating full-screen ones slightly differently.
      if mode == "partial" and self.FULL_REFRESH_COUNT > 0 then
        if self.refresh_count == self.FULL_REFRESH_COUNT - 1 then
          -- NOTE: Promote to "full" if no region (reader), to "flashui" otherwise (UI)
          if refresh.region.x == 0 and refresh.region.y == 0 and refresh.region.w == Screen:getWidth() and refresh.region.h == Screen:getHeight() then
            mode = "full"
          else
            mode = "flashui"
          end
          logger.dbg("_refresh: promote refresh to", mode)
        end
        -- Reset the refresh_count to 0 after an explicit full screen refresh.
        -- Technically speaking, in the case, it should be the only refresh, but
        -- who knows.
        self.refresh_count = -1
      end
      --[[
      -- Remember the refresh region
      self._last_refresh_region = refresh.region:copy()
      --]]
      refresh_methods[mode](
        Screen,
        refresh.region.x,
        refresh.region.y,
        refresh.region.w,
        refresh.region.h,
        refresh.dither
      )
    end

    -- Don't trigger afterPaint if we did not, in fact, paint anything
    Screen:afterPaint()

    -- Record how many partial refreshes happened.
    self.refresh_count = (self.refresh_count + 1) % self.FULL_REFRESH_COUNT
  end

  -- In comparison, no matter if anything was painted, at this time point, the
  -- screen should be updated into the latest status.
  self._last_repaint_time = time.realtime_coarse()

  self._refresh_stack = {}
end

function UIManager:waitForScreenRefresh()
  if Device:isEmulator() then
    -- 100ms to make the animations more visible.
    ffiUtil.usleep(100000)
    return
  end
  if not Device:hasEinkScreen() then
    return
  end
  if G_reader_settings:nilOrTrue("avoid_flashing_ui") then
    ffiUtil.usleep(1000)
  else
    Screen:refreshWaitForLast()
  end
end

--[[--
Schedule a widget to be repainted, it or its show_parent must be in the
_window_stack.
--]]
function UIManager:scheduleWidgetRepaint(widget)
  -- TODO: Should assert.
  if not widget then
    return false
  end

  -- TODO: Should assert.
  for i = 1, #self._window_stack do
    if self._window_stack[i].widget == widget then
      self._dirty[widget] = true
      return true
    end
  end

  if widget.show_parent and widget.show_parent ~= widget then
    if self:scheduleWidgetRepaint(widget.show_parent) then
      return true
    end
  end

  logger.warn(
    "Unknown widget ",
    self:_widgetDebugStr(widget),
    " to repaint, it may not be shown yet, or you may want to send in the ",
    "show(widget) instead."
  )
  return false
end

--[[--
Immediately repaint the widget, relying on the widget.dimen. The widget doesn't
need to be in the _window_stack, i.e. not a show(widget).

Use this function is dangerous, it doesn't respect the _window_stack and may
break anything above the widget, and should only be used to show feedbacks for
user interactions.
--]]
function UIManager:repaintWidget(widget)
  assert(widget ~= nil)
  assert(widget.dimen ~= nil)
  widget:paintTo(Screen.bb, widget.dimen.x, widget.dimen.y)
  self:scheduleRefresh(widget:refreshMode(), widget.dimen, widget.dithered)
end

--[[--
Same idea as `widgetRepaint`, but does a simple `bb:invertRect` on the Screen
buffer, without actually going through the widget's `paintTo` method.

It allows inverting a subset of the widget unlike :repaintWidget with optional
geometry parameters.

Use this function is dangerous, it doesn't respect the _window_stack and may
break anything above the widget, and should only be used to show feedbacks for
user interactions.

@param widget a @{ui.widget.widget|widget} object
@int x left origin of the rectangle to invert (in the Screen buffer, optional, will use `widget.dimen.x`)
@int y top origin of the rectangle (in the Screen buffer, optional, will use `widget.dimen.y`)
@int w width of the rectangle (optional, will use `widget.dimen.w` like `paintTo` would if omitted)
@int h height of the rectangle (optional, will use `widget.dimen.h` like `paintTo` would if omitted)
--]]
function UIManager:invertWidget(widget, x, y, w, h)
  -- TODO: Should assert.
  if not widget then
    return
  end

  -- It's possible that the function is called before the paintTo call.
  if widget.dimen then
    x = x or widget.dimen.x
    y = y or widget.dimen.y
    w = w or widget.dimen.w
    h = h or widget.dimen.h
  end
  if not x or not y or not w or not h then
    logger.warn(
      "Cannot invert widget ",
      self:_widgetDebugStr(widget),
      " without its dimen."
    )
    return
  end

  logger.dbg("Explicit widgetInvert:", self:_widgetDebugStr(widget), "@", x, y)
  if widget.show_parent and widget.show_parent.cropping_widget then
    -- The main widget parent of this subwidget has a cropping container: see if
    -- this widget is a child of this cropping container
    local cropping_widget = widget.show_parent.cropping_widget
    if util.arrayReferences(cropping_widget, widget) then
      -- Invert only what intersects with the cropping container
      local invert_region = cropping_widget:getCropRegion():intersect(Geom:new({
        x = x,
        y = y,
        w = w,
        h = h,
      }))
      Screen.bb:invertRect(
        invert_region.x,
        invert_region.y,
        invert_region.w,
        invert_region.h
      )
      self:scheduleRefresh("fast", invert_region)
      return
    end
  end
  Screen.bb:invertRect(x, y, w, h)
  self:scheduleRefresh("fast", Geom:new({ x = x, y = y, w = w, h = h }), widget.dithered)
end

function UIManager:setInputTimeout(timeout)
  self.INPUT_TIMEOUT = timeout or (200 * 1000)
end

function UIManager:resetInputTimeout()
  self.INPUT_TIMEOUT = nil
end

-- NOTE: The Event hook mechanism used to dispatch for *every* event, and would actually pass the event along.
--     We've simplified that to once per input frame, and without passing anything (as we, in fact, have never made use of it).
function UIManager:handleInputEvent(input_event)
  if
    type(input_event) == "table"
    and input_event.args
    and #input_event.args > 0
    and input_event.args[1].ges == "tap"
    and input_event.args[1].time
    and G_reader_settings:nilOrTrue("disable_out_of_order_taps")
  then
    if self._last_repaint_time > input_event.args[1].time then
      logger.dbg("Ignore out of order event ", input_event.handler)
      return
    end
  end
  -- Compare input_event.args[1].time / 1000 / 1000 with os.time()
  local handler = self.event_handlers[input_event]
  if handler then
    handler(input_event)
  else
    self:userInput(input_event)
  end
end

-- Process all pending events on all registered ZMQs.
function UIManager:_processZMQs()
  local sent_InputEvent = false
  for _, zeromq in ipairs(self._zeromqs) do
    for input_event in zeromq.waitEvent, zeromq do
      if not sent_InputEvent then
        self:updateLastUserActionTime()
        sent_InputEvent = true
      end
      self:handleInputEvent(input_event)
    end
  end
end

function UIManager:handleInput()
  local wait_until, now
  -- run this in a loop, so that paints can trigger events
  -- that will be honored when calculating the time to wait
  -- for input events:
  repeat
    wait_until, now = self:_checkTasks()
    --[[
    dbg("---------------------------------------------------")
    dbg("wait_until", wait_until)
    dbg("now     ", now)
    dbg("#exec stack  ", #self._task_queue)
    dbg("#window stack", #self._window_stack)
    dbg("#dirty stack ", util.tableSize(self._dirty))
    dbg("dirty?", self._task_queue_dirty)
    dbg("---------------------------------------------------")
    --]]

    -- stop when we have no window to show
    if not self._window_stack[1] then
      logger.info("UIManager: No dialogs left to show")
      if self:_gated_quit() ~= false then
        return
      end
    end

    self:forceRepaint()
  until not self._task_queue_dirty

  -- NOTE: Compute deadline *before* processing ZMQs, in order to be able to catch tasks scheduled *during*
  --     the final ZMQ callback.
  --     This ensures that we get to honor a single ZMQ_TIMEOUT *after* the final ZMQ callback,
  --     which gives us a chance for another iteration, meaning going through _checkTasks to catch said scheduled tasks.
  -- Figure out how long to wait.
  -- Ultimately, that'll be the earliest of INPUT_TIMEOUT, ZMQ_TIMEOUT or the next earliest scheduled task.
  local deadline
  -- Default to INPUT_TIMEOUT (which may be nil, i.e. block until an event happens).
  local wait_us = self.INPUT_TIMEOUT

  -- If we have any ZMQs registered, ZMQ_TIMEOUT is another upper bound.
  if self._zeromqs[1] then
    wait_us = math.min(wait_us or math.huge, self.ZMQ_TIMEOUT)
  end

  -- We pass that on as an absolute deadline, not a relative wait time.
  if wait_us then
    deadline = now + time.us(wait_us)
  end

  -- If there's a scheduled task pending, that puts an upper bound on how long to wait.
  if wait_until and (not deadline or wait_until < deadline) then
    --       ^ We don't have a TIMEOUT induced deadline, making the choice easy.
    --               ^ We have a task scheduled for *before* our TIMEOUT induced deadline.
    deadline = wait_until
  end

  -- Run ZMQs if any
  self:_processZMQs()

  -- If allowed, entering standby (from which we can wake by input) must trigger in response to event
  -- this function emits (plugin), or within waitEvent() right after (hardware).
  -- Anywhere else breaks preventStandby/allowStandby invariants used by background jobs while UI is left running.
  self:_standbyTransition()
  if self._pm_consume_input_early then
    -- If the PM state transition requires an early return from input polling, honor that.
    -- c.f., UIManager:setPMInputTimeout (and AutoSuspend:AllowStandbyHandler).
    deadline = now
    self._pm_consume_input_early = false
  end

  -- wait for next batch of events
  local input_events = Input:waitEvent(now, deadline)

  -- delegate each input event to handler
  if input_events then
    self:updateLastUserActionTime()
    -- Handle the full batch of events
    for __, ev in ipairs(input_events) do
      self:handleInputEvent(ev)
    end
  end

  if self.looper then
    logger.info("handle input in turbo I/O looper")
    self.looper:add_callback(function()
      --- @fixme Force close looper when there is unhandled error,
      -- otherwise the looper will hang. Any better solution?
      xpcall(function()
        self:handleInput()
      end, function(err)
        io.stderr:write(err .. "\n")
        io.stderr:write(debug.traceback() .. "\n")
        self.looper:close()
        os.exit(1, true)
      end)
    end)
  end
end

-- If a function works with widget, it should use widget:refreshMode(). But this
-- function is special, cause it goes through all the widgets. If their
-- refreshMode()s are considered, it would almost always end up with "full".
function UIManager:scheduleRepaintAll(refreshMode)
  local dithered = false
  for _, window in ipairs(self._window_stack) do
    self._dirty[window.widget] = true
    if window.widget.dithered then
      -- NOTE: That works when refreshtype is NOT a function,
      --     which is why _repaint does another pass of this check ;).
      logger.dbg(
        "setDirty on all widgets: found a dithered widget, infecting the refresh queue"
      )
      refreshdither = true
    end
  end
  self:scheduleRefresh(refreshMode or "full", nil, dithered)
end

function UIManager:onRotation()
  self:scheduleRepaintAll()
  self:forceRepaint()
end

function UIManager:initLooper()
  if G_defaults:read("DUSE_TURBO_LIB") and not self.looper then
    TURBO_SSL = true -- luacheck: ignore
    __TURBO_USE_LUASOCKET__ = true -- luacheck: ignore
    local turbo = require("turbo")
    self.looper = turbo.ioloop.instance()
  end
end

--[[--
This is the main loop of the UI controller.

It is intended to manage input events and delegate them to dialogs.
--]]
function UIManager:run()
  self:initLooper()
  -- currently there is no Turbo support for Windows
  -- use our own main loop
  if not self.looper then
    repeat
      self:handleInput()
    until self._exit_code
  else
    self.looper:add_callback(function()
      self:handleInput()
    end)
    self.looper:start()
  end

  logger.info("Tearing down UIManager with exit code:", self._exit_code)
  return self._exit_code
end

--[[--
Executes all the operations of a suspension (i.e., sleep) request.

This function usually puts the device into suspension.
]]
function UIManager:suspend()
  -- Should always exist, as defined in `generic/device` or overwritten with `setEventHandlers`
  if self.event_handlers.Suspend then
    -- Give the other event handlers a chance to be executed.
    -- `Suspend` and `Resume` events will be sent by the handler
    UIManager:nextTick(self.event_handlers.Suspend)
  end
end

function UIManager:askForReboot(message_text)
  if not Device:canReboot() then
    return
  end
  -- Give the other event handlers a chance to be executed.
  -- 'Reboot' event will be sent by the handler
  self:nextTick(function()
    local ConfirmBox = require("ui/widget/confirmbox")
    self:show(ConfirmBox:new({
      text = message_text or _("Are you sure you want to reboot the device?"),
      ok_text = _("Reboot"),
      ok_callback = function()
        self:nextTick(self.reboot_action)
      end,
    }))
  end)
end

function UIManager:askForPowerOff(message_text)
  if not Device:canPowerOff() then
    return
  end
  -- Give the other event handlers a chance to be executed.
  -- 'PowerOff' event will be sent by the handler
  self:nextTick(function()
    local ConfirmBox = require("ui/widget/confirmbox")
    self:show(ConfirmBox:new({
      text = message_text
        or _("Are you sure you want to power off the device?"),
      ok_text = _("Power off"),
      ok_callback = function()
        self:nextTick(self.poweroff_action)
      end,
    }))
  end)
end

function UIManager:askForRestart(message_text)
  -- Give the other event handlers a chance to be executed.
  -- 'Restart' event will be sent by the handler
  self:nextTick(function()
    if Device:canRestart() then
      local ConfirmBox = require("ui/widget/confirmbox")
      self:show(ConfirmBox:new({
        text = message_text or _("This will take effect on next restart."),
        ok_text = _("Restart now"),
        ok_callback = function()
          self:broadcastEvent(Event:new("Restart"))
        end,
        cancel_text = _("Restart later"),
      }))
    else
      self:show(require("ui/widget/infomessage"):new({
        text = message_text or _("This will take effect on next restart."),
      }))
    end
  end)
end

--[[--
Release standby lock.

Called once we're done with whatever we were doing in the background.
Standby is re-enabled only after all issued prevents are paired with allowStandby for each one.
]]
function UIManager:allowStandby()
  assert(
    self._prevent_standby_count > 0,
    "allowing standby that isn't prevented; you have an allow/prevent mismatch somewhere"
  )
  self._prevent_standby_count = self._prevent_standby_count - 1
  logger.dbg(
    "UIManager:allowStandby, counter decreased to",
    self._prevent_standby_count
  )
end

--[[--
Prevent standby.

i.e., something is happening in background, yet UI may tick.
]]
function UIManager:preventStandby()
  self._prevent_standby_count = self._prevent_standby_count + 1
  logger.dbg(
    "UIManager:preventStandby, counter increased to",
    self._prevent_standby_count
  )
end

-- The allow/prevent calls above can interminently allow standbys, but we're not interested until
-- the state change crosses UI tick boundary, which is what self._prev_prevent_standby_count is tracking.
function UIManager:_standbyTransition()
  if
    self._prevent_standby_count == 0 and self._prev_prevent_standby_count > 0
  then
    -- edge prevent->allow
    logger.dbg("UIManager:_standbyTransition -> AllowStandby")
    Device:setAutoStandby(true)
    self:broadcastEvent(Event:new("AllowStandby"))
  elseif
    self._prevent_standby_count > 0 and self._prev_prevent_standby_count == 0
  then
    -- edge allow->prevent
    logger.dbg("UIManager:_standbyTransition -> PreventStandby")
    Device:setAutoStandby(false)
    self:broadcastEvent(Event:new("PreventStandby"))
  end
  self._prev_prevent_standby_count = self._prevent_standby_count
end

-- Used by a PM transition event handler to request an early return from input polling.
-- NOTE: We can't reuse setInputTimeout to avoid interactions with ZMQ...
function UIManager:consumeInputEarlyAfterPM(toggle)
  self._pm_consume_input_early = toggle
end

--- Broadcasts a `FlushSettings` Event to *all* widgets.
function UIManager:flushSettings()
  self:broadcastEvent(Event:new("FlushSettings"))
end

--- Sanely restart KOReader (on supported platforms).
function UIManager:restartKOReader()
  -- This is just a magic number to indicate the restart request for shell scripts.
  self:quit(85)
end

--- Sanely abort KOReader (e.g., exit sanely, but with a non-zero return code).
function UIManager:abort()
  self:quit(1)
end

--- Goes through all the widgets and collects the key_events. If any key_event is conflict, the
--- one on the first / top-most widget will be preserved.
function UIManager:keyEvents()
  local key_events = {}

  local function check_widget(w)
    if not w then
      return
    end
    local function check(w)
      local c = w.key_events
      if not c then
        return
      end
      for k, v in pairs(c) do
        if
          not v.is_inactive
          and k ~= "AnyKeyPressed"
          and k ~= "SelectByShortCut"
        then
          key_events[k] = v
        end
      end
    end
    check(w)
    for _, widget in ipairs(w) do
      check_widget(widget)
    end
  end

  for i = 1, #self._window_stack do
    check_widget(self._window_stack[i].widget)
  end
  return require("ffi/SortedIteration")(key_events)
end

-- Executes the function during the showing of the widget, usually InfoMessage.
function UIManager:runWith(func, widget)
  assert(widget ~= nil)
  assert(func ~= nil)
  if type(widget) == "string" then
    widget = require("ui/widget/infomessage"):new({
      text = widget,
      icon = "hourglass",
    })
  end
  self:show(widget)
  self:forceRepaint()
  local wait_time = time.monotonic()
  func()
  wait_time = time.ms(200) - (time.monotonic() - wait_time)
  if wait_time > 0 then
    ffiUtil.usleep(wait_time)
  end
  self:close(widget)
end

UIManager:init()
return UIManager
