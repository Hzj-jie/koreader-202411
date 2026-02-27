--[[--
This module manages widgets.
]]

local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local dbg = require("dbg")
local dump = require("dump")
local ffiUtil = require("ffi/util")
local gettext = require("gettext")
local logger = require("logger")
local time = require("ui/time")
local util = require("util")
local Input = Device.input
local Screen = Device.screen

-- When a mode is not supported by the hardware, the next level will be
-- automatically used.

-- precedence of refresh modes:
local refresh_modes = {
  -- Break grayscale on kobo aura hd and kindles, very likely shouldn't be used
  -- at all. Supported by sunxi and mxcfb.
  a2 = 1,
  -- The dirtiest way of changing the display, but unlike a2, it at least keeps
  -- everything readable, but the grayscale may not be very accurate. Supported
  -- by pocketbook, sunxi, android and mxcfb.
  fast = 2,
  -- The default way of showing anything related to the ui. Supported by
  -- pocketbook, sunxi, android and mxcfb.
  ui = 3,
  -- Allow partially updating the screen without flashing the screen. Supported
  -- by pocketbook, sunxi, android, mxcfb and einkfb.
  partial = 4,
  -- Useless, supported only by sunxi.
  ["[ui]"] = 5,
  -- Useless, supported only by sunxi.
  ["[partial]"] = 6,
  -- UI + a screen flashing, cause flickering, clean the black areas.
  -- Supported by pocketbook, sunxi, android and mxcfb.
  flashui = 7,
  -- Partial + a screen flashing, cause flickering, clean the black areas.
  -- Supported by pocketbook, sunxi, android and mxcfb.
  flashpartial = 8,
  -- A full screen flashing, cause flickering, clean the black areas.
  -- Supported by pocketbook, sunxi, android, mxcfb and einkfb.
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

local function _isWidget(widget)
  if widget ~= nil and type(widget) == "table" then
    return true
  end
  logger.warn("FixMe: Attempted to check a nil widget or not a table. ",
              debug.traceback())
  return false
end

local function _widgetDebugStr(widget)
  assert(_isWidget(widget))
  return widget.name or widget.id or tostring(widget)
end

local function _widgetWindow(w)
  assert(_isWidget(w))
  local window = w:window()
  if window == nil then
    -- TODO: Should assert.
    logger.warn(
      "FixMe: Unknown widget ",
      _widgetDebugStr(w),
      " to repaint, it may not be shown yet, or you may want to send in the ",
      "show(widget) instead. ",
      debug.traceback()
    )
    return nil
  end
  return window
end

local function cropping_region(widget)
  assert(_isWidget(widget))
  local dimen = widget:getSize()
  assert(dimen ~= nil)
  -- It's possible that the function is called before the paintTo call, so x or
  -- y may not present.
  local x, y, w, h = dimen.x, dimen.y, dimen.w, dimen.h

  local window = _widgetWindow(widget)
  if (not x or not y) and window then
    -- Before the initial paintTo call, widget.dimen isn't available. In the
    -- case, it's expected to paintTo a showParent which starts from the top
    -- left of a window.
    if window.widget ~= widget then
      logger.warn(
        "FixMe: ",
        _widgetDebugStr(widget),
        " is painted directly into its window without its location.",
        " It should be painted by its parent widget first."
      )
    end
    x = x or window.x
    y = y or window.y
  end

  if not x or not y or not w or not h then
    logger.warn(
      "Cannot calculate cropping region of widget ",
      _widgetDebugStr(widget),
      " without its dimen."
    )
    return nil
  end

  if w == 0 and h == 0 then
    logger.warn(
      "FixMe: widget ",
      _widgetDebugStr(widget),
      " returns empty Geom."
    )
  end

  if window then
    -- window.x and window.y are never used, but keep the potential logic right.
    x = x + window.x
    y = y + window.y
    local parent = window.widget
    if parent and parent.cropping_widget then
      -- The main widget parent of this subwidget has a cropping container: see
      -- if this widget is a child of this cropping container
      local cropping_widget = parent.cropping_widget
      if util.arrayDfSearch(cropping_widget, widget) then
        -- Invert only what intersects with the cropping container
        return cropping_widget:getCropRegion():intersect(Geom:new({
          x = x,
          y = y,
          w = w,
          h = h,
        }))
      end
    end
  end
  return Geom:new({ x = x, y = y, w = w, h = h })
end

-- How long to wait between ZMQ wakeups: 50ms.
local ZMQ_TIMEOUT = 50 * 1000

-- This is a singleton
local UIManager = {
  event_handlers = nil,

  _full_refresh_count = G_named_settings.default.full_refresh_count(),
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
  _refresh_count = 0,
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
    Screensaver:setup("poweroff", gettext("Powered off"))
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
    Screensaver:setup("reboot", gettext("Rebooting…"))
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
  assert(not self:isTopLevelWidget(widget))

  logger.dbg("show widget:", _widgetDebugStr(widget))

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
function UIManager:_close(widget)
  assert(UIManager:isTopLevelWidget(widget))

  logger.dbg("close widget:", _widgetDebugStr(widget))
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
      -- Unfortunately, here the logic needs to mark the ones *below* dirty,
      -- so :forceRepaint() cannot help. Though indeed the :forceRepaint() would
      -- still redraw everything *above* the dirty one, the logic here should
      -- not break any potential improvements.
      -- TODO: Similar to the UIManager:show, an optimization can be calculating
      -- the covered area and not repainting all the invisible widgets, but it's
      -- hard to demonstrate the importance.
      for j = 1, i - 1 do
        self._dirty[self._window_stack[j].widget] = true
      end
    else
      if w.dithered then
        logger.dbg(
          "Lower widget",
          _widgetDebugStr(w),
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
  if widget._restored_input_gestures then
    logger.dbg("Widget is gone, disabling gesture handling again")
    self:setIgnoreTouchInput(true)
  end
end

function UIManager:close(widget)
  if not UIManager:isTopLevelWidget(widget) then
    logger.warn(
      "FixMe: widget "
        .. _widgetDebugStr(widget)
        .. " has been closed already. "
        .. debug.traceback()
    )
    return
  end
  self:_close(widget)
end

function UIManager:closeIfShown(widget)
  if not UIManager:isTopLevelWidget(widget) then
    return
  end
  self:_close(widget)
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

function UIManager:_scheduleWidgetRefresh(widget, mode, region, dithered)
  if type(widget) == "table" then
    mode = mode or widget:refreshMode()
    region = region or widget:dirtyRegion()
    -- Avoid treating false wrongly.
    if dithered == nil then
      dithered = widget.dithered
    end
  end
  self:scheduleRefresh(mode, region, dithered)
end

-- A workaround to handle most of the existing logic
function UIManager:setDirty(widget, refreshMode, region)
  if type(refreshMode) == "function" then
    -- Have to repaint the widget first; still use :setDirty to handle various
    -- conditions of the widget itself.
    if widget ~= nil then
      -- Indeed it shouldn't be necessary to provide extra function if a widget
      -- will be repainted, but anyway, it's how most of the logic is
      -- implemented now.
      if widget == "all" then
        self:scheduleRepaintAll()
      else
        widget.delay_refresh = true
        self:scheduleWidgetRepaint(widget)
      end
    end
    table.insert(self._refresh_func_stack, function()
      local m, r, d = refreshMode()
      self:_scheduleWidgetRefresh(widget, m, r, d)
    end)
    return
  end
  if widget == nil then
    self:scheduleRefresh(refreshMode, region)
    return
  end
  if widget == "all" then
    self:scheduleRepaintAll()
    return
  end
  widget.delay_refresh = true
  self:scheduleWidgetRepaint(widget)
  self:_scheduleWidgetRefresh(widget, refreshMode, region)
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

--- Returns the full refresh rate for e-ink screens (`_full_refresh_count`).
function UIManager:updateRefreshRate()
  local function refresh_count()
    local r = G_named_settings.full_refresh_count()
    -- Never fully refresh screen.
    if r <= 0 then
      return 0
    end
    -- Double the refresh rate in night_mode, black area would be way larger,
    -- and causes more blur.
    if G_reader_settings:isTrue("night_mode") then
      r = math.floor(r / 2)
    end
    if r < 1 then
      return 1
    end
    return r
  end
  self._full_refresh_count = refresh_count()
end

function UIManager:toggleNightMode()
  self:onRotation()
  self:updateRefreshRate()
end

--- Top-to-bottom widgets iterator
--- NOTE: VirtualKeyboard can be instantiated multiple times, and is a modal,
--    so don't be surprised if you find a couple of instances of it at the top ;).
function UIManager:topdown_windows_iter()
  local n = #self._window_stack
  local i = n + 1
  return function()
    i = i - 1
    if i > 0 then
      return self._window_stack[i]
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
function UIManager:isTopLevelWidget(widget)
  -- TODO: Should assert
  if not _isWidget(widget) then
    return false
  end

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

  -- if no region is specified, use the screen's dimensions
  region = region
    or Geom:new({ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() })

  -- if no dithering hint was specified, don't request dithering
  dither = dither or false

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

function UIManager:_scheduleRefreshWindowWidget(window, widget)
  assert(window ~= nil and type(window) == "table")
  widget = widget or window.widget
  assert(_isWidget(widget))
  if widget.invisible then
    return
  end
  -- A dirty hack to workaround the :setDirty calls.
  if widget.delay_refresh then
    widget.delay_refresh = nil
    return
  end

  -- A dirty hack to workaround the groups, they cover the entire screen but
  -- only draw a small portion.
  local dimen = widget:dirtyRegion()
  -- window.x and window.y are never used, but keept the potential logic right.
  if window.x > 0 or window.y > 0 then
    dimen = dimen:copy():offsetBy(window.x, window.y)
  end
  self:scheduleRefresh(widget:refreshMode(), dimen, widget.dithered)
end

function UIManager:findWindow(window)
  return util.arrayContains(self._window_stack, window)
end

function UIManager:_repaintDirtyWidgets()
  if util.tableSize(self._dirty) == 0 then
    return
  end

  -- TODO: A potential improvement is calculating the covered area from
  -- for i = #self._window_stack, 1, -1 do
  -- and ignore anything covered by other widget. But considering the number of
  -- widgets showing up in the stack, it's very hard to demonstrate if it's even
  -- necessary.

  local dirty_widgets = {}
  for _ = 1, #self._window_stack do
    table.insert(dirty_widgets, {})
  end

  for w in pairs(self._dirty) do
    local window = _widgetWindow(w)
    if window ~= nil then
      local index = self:findWindow(window)
      -- Otherwise the window should be nil.
      assert(index ~= false)
      assert(index > 0)
      assert(index <= #self._window_stack)
      table.insert(dirty_widgets[index], w)
    end
  end

  for i = 1, #self._window_stack do
    if #dirty_widgets[i] > 0 then
      -- Anything above this window needs to be repainted.
      for j = i + 1, #self._window_stack do
        dirty_widgets[j] = { self._window_stack[j].widget }
      end
      break
    end
  end

  for i = 1, #self._window_stack do
    table.sort(dirty_widgets[i], function(a, b)
      return a:window_z_index() < b:window_z_index()
    end)
  end

  for i = 1, #self._window_stack do
    for j = 1, #dirty_widgets[i] do
      if dirty_widgets[i][j] == nil then
        break
      end
      for k = j + 1, #dirty_widgets[i] do
        if dirty_widgets[i][k] == nil then
          break
        end
        if
          dirty_widgets[i][j]:window_z_index()
            < dirty_widgets[i][k]:window_z_index()
          and util.arrayDfSearch(dirty_widgets[i][j], dirty_widgets[i][k])
        then
          -- Still refresh its dirty region in case the ancestor doesn't think
          -- its content has been changed.
          -- TODO: This shouldn't be necessary, but some widget doesn't do the
          -- right thing. E.g. ReaderUI.
          self:_scheduleRefreshWindowWidget(
            self._window_stack[i],
            dirty_widgets[i][k]
          )
          table.remove(dirty_widgets[i], k)
        end
      end
    end
  end

  for i = 1, #self._window_stack do
    local window = self._window_stack[i]
    for _, widget in ipairs(dirty_widgets[i]) do
      logger.dbg("painting widget:", _widgetDebugStr(widget))
      local paint_region = cropping_region(widget)
      assert(paint_region ~= nil)
      widget:paintTo(Screen.bb, paint_region.x, paint_region.y)
      self:_scheduleRefreshWindowWidget(window, widget)
    end
  end

  self._dirty = {}
end

function UIManager:ignoreNextRefreshPromote()
  self._refresh_count = self._refresh_count - 1
end

function UIManager:fullRefreshPromoteEnabled()
  return self._full_refresh_count > 0
end

function UIManager:_decideRefreshMode(refresh)
  local mode = refresh.mode
  local region = refresh.region
  assert(refresh_modes[mode] ~= nil, "Unknown refresh mode " .. tostring(mode))
  assert(region ~= nil)
  if mode == "a2" then
    logger.dbg("_refreshScreen: explicitly disable a2 mode.")
    return "fast"
  end
  if self:duringForceFastRefresh() and G_named_settings.low_pan_rate() then
    -- Downgrade all refreshes to "fast" when ReaderPaging or ReaderScrolling have set this flag
    logger.dbg(
      "_refreshScreen: downgrading all refresh mode to fast during forceFastRefresh."
    )
    return "fast"
  end

  if
    self:fullRefreshPromoteEnabled()
    and self._refresh_count >= self._full_refresh_count
    and region:area() >= Screen:getArea() * 0.5
  then
    if region:area() >= Screen:getArea() * 0.8 then
      logger.dbg("_refreshScreen: promote ", mode, " refresh to full")
      return "full"
    else
      logger.dbg("_refresh: promote ", mode, " refresh to flashui")
      return "flashui"
    end
  end

  -- Handle downgrading flashing modes to non-flashing modes, according to user settings.
  -- NOTE: Do it before "full" promotion and collision checks/update_mode.
  if G_reader_settings:nilOrTrue("avoid_flashing_ui") then
    if mode == "flashui" then
      logger.dbg("_refresh: downgraded flashui refresh to ui")
      return "ui"
    elseif mode == "flashpartial" then
      logger.dbg("_refresh: downgraded flashpartial refresh to partial")
      return "partial"
    elseif mode == "partial" then
      logger.dbg("_refresh: downgraded partial refresh to ui")
      return "ui"
    elseif mode == "full" then
      logger.dbg("_refresh: downgraded full refresh to partial")
      return "partial"
    end
  else
    if mode == "fast" then
      logger.dbg("_refresh: promote fast refresh to ui")
      return "ui"
    end
  end

  -- No adjustments happened, return the original input.
  return mode
end

function UIManager:_mergeRefreshStack()
  assert(#self._refresh_stack > 0)
  local r = self._refresh_stack
  table.sort(r, function(a, b)
    if refresh_modes[a.mode] < refresh_modes[b.mode] then
      return true
    elseif refresh_modes[a.mode] > refresh_modes[b.mode] then
      return false
    end
    -- Same refresh mode, prefer not dither.
    if a.dither == false and b.dither == true then
      return true
    elseif a.dither == true and b.dither == false then
      return false
    end
    -- Same refresh mode and dither, prefer smaller area - note, they do not
    -- need to contain each other, but a smaller rect cannot include a larger
    -- one.
    return Geom.smallerThan(a.region, b.region)
  end)

  local i = 1
  -- r is changing.
  while i <= #r do
    for j = 1, i - 1 do
      if r[i].region:contains(r[j].region) then
        -- Remove j
        table.remove(r, j)
        -- Retry
        i = i - 2
        break
      end
    end
    i = i + 1
  end

  self._refresh_stack = {}
  return r
end

function UIManager:_refreshScreen()
  -- execute pending refresh functions
  for _, refreshfunc in ipairs(self._refresh_func_stack) do
    refreshfunc()
  end
  self._refresh_func_stack = {}

  if #self._refresh_stack == 0 then
    return
  end

  local refresh_stack = self:_mergeRefreshStack()
  -- execute refreshes:
  local large_refresh = false
  for _, refresh in ipairs(refresh_stack) do
    -- If HW dithering is disabled, unconditionally drop the dither flag
    if not Screen.hw_dithering then
      refresh.dither = nil
    end
    dbg:v("triggering refresh", refresh)

    local mode = self:_decideRefreshMode(refresh)
    assert(
      refresh_modes[mode] ~= nil,
      "Unknown refresh mode " .. tostring(mode)
    )
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
    -- This implementation sits on the safer side to only drop the upcoming
    -- refresh mode promotion when a "flash" type refresh affects over 1/2
    -- screen.
    -- In theory, multiple partial "flash" type refreshes may cover the entire
    -- screen already without needing another full "flash". But tracking it
    -- would be very painful.
    if refresh.region:area() >= Screen:getArea() * 0.5 then
      -- Record how many partial refreshes happened, but ignore any small areas
      -- like footer or clock.
      if refresh_modes[mode] >= refresh_modes["flashui"] then
        self._refresh_count = 0
        large_refresh = false
      else
        large_refresh = true
      end
    end
  end
  -- The behavior is not very consistent, and heavily relies on the order of all
  -- the refreshes. But it should be good enough.
  if large_refresh then
    self._refresh_count = self._refresh_count + 1
  end
end

--[[--
Repaints dirty widgets.

This will also drain the refresh queue, effectively refreshing the screen region(s) matching those freshly repainted widgets.

There may be refreshes enqueued without any widgets needing to be repainted (c.f., `setDirty`'s behavior when passed a `nil` widget),
in which case, nothing is repainted, but the refreshes are still drained and executed.

@local Not to be used outside of UIManager!
--]]
function UIManager:forceRepaint()
  Screen:beforePaint()
  self:_repaintDirtyWidgets()

  self:_refreshScreen()
  Screen:afterPaint()

  -- No matter if anything was painted, at this time point, the screen should be
  -- updated into the latest status.
  self._last_repaint_time = time.realtime_coarse()
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
Schedule a widget to be repainted, it or its Widget:showParent() must be in the
_window_stack eventually before the next repaint or it will be ignored.
--]]
function UIManager:scheduleWidgetRepaint(widget)
  -- TODO: Should assert.
  if not _isWidget(widget) then
    return false
  end

  -- Allows a widget being showed later.
  self._dirty[widget] = true
  return _widgetWindow(widget) ~= nil
end

--[[--
Ignore pending widget repaint if any.
--]]
function UIManager:ignoreWidgetRepaint(widget)
  assert(_isWidget(widget))
  if self._dirty[widget] then
    self._dirty[widget] = nil
    return true
  end
  return false
end

--[[--
Immediately repaint the widget, relying on the widget:getSize(). The widget doesn't
need to be in the _window_stack, i.e. not a show(widget).

Use this function is dangerous, it doesn't respect the _window_stack and may
break anything above the widget, and should only be used to show feedbacks for
user interactions.
--]]
function UIManager:repaintWidget(widget)
  assert(_isWidget(widget))
  assert(widget:getSize() ~= nil)
  local paint_region = cropping_region(widget)
  assert(paint_region ~= nil)
  widget:paintTo(Screen.bb, paint_region.x, paint_region.y)
  -- Explicitly using "fast" to reduce the cost of showing feedbacks.
  self:scheduleRefresh("fast", paint_region, widget.dithered)
end

--[[--
Same idea as `widgetRepaint`, but does a simple `bb:invertRect` on the Screen
buffer, without actually going through the widget's `paintTo` method.

Unlike :repaintWidget, it allows inverting a subset of the widget with optional
geometry parameters.

Use this function is dangerous, it doesn't respect the _window_stack and may
break anything above the widget, and should only be used to show feedbacks for
user interactions.

@param widget a @{ui.widget.widget|widget} object
--]]
function UIManager:invertWidget(widget)
  assert(_isWidget(widget))
  local invert_region = cropping_region(widget)
  if invert_region == nil then
    return
  end

  logger.dbg(
    "Explicit widgetInvert:",
    _widgetDebugStr(widget),
    "@",
    dump(invert_region)
  )
  Screen.bb:invertRect(
    invert_region.x,
    invert_region.y,
    invert_region.w,
    invert_region.h
  )
  self:scheduleRefresh("fast", invert_region, widget.dithered)
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
  local handler = self.event_handlers[input_event]
  if handler then
    handler(input_event)
  else
    -- Compare input_event.args[1].time / 1000 / 1000 with os.time()
    if
      G_reader_settings:nilOrTrue("disable_out_of_order_input")
      and type(input_event) == "table"
    then
      if
        input_event.handler == "onGesture"
        and input_event.args
        and #input_event.args > 0
        and type(input_event.args[1]) == "table"
        -- hold and pan use the initial time and cannot be compared with the
        -- repaint time.
        -- pan_release may use the logic, but it seems less ideal if pan was
        -- not ignored.
        and util.arrayContains(
          { "touch", "tap", "swipe", "two_finger_tap", "two_finger_swipe" },
          input_event.args[1].ges
        )
        and input_event.args[1].time
        and self._last_repaint_time > input_event.args[1].time
      then
        logger.dbg("Ignore out of order tap event ", input_event.handler)
        return
      end

      if
        input_event.handler == "onKeyPress"
        and input_event.time
        and self._last_repaint_time > input_event.time
      then
        logger.dbg("Ignore out of order key press event ", input_event.handler)
        return
      end
    end
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
    wait_us = math.min(wait_us or math.huge, ZMQ_TIMEOUT)
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

function UIManager:scheduleRepaintAll()
  for _, window in ipairs(self._window_stack) do
    self._dirty[window.widget] = true
  end
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
      text = message_text
        or gettext("Are you sure you want to reboot the device?"),
      ok_text = gettext("Reboot"),
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
        or gettext("Are you sure you want to power off the device?"),
      ok_text = gettext("Power off"),
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
        text = message_text
          or gettext("This will take effect on next restart."),
        ok_text = gettext("Restart now"),
        ok_callback = function()
          self:broadcastEvent(Event:new("Restart"))
        end,
        cancel_text = gettext("Restart later"),
      }))
    else
      self:show(require("ui/widget/infomessage"):new({
        text = message_text
          or gettext("This will take effect on next restart."),
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
    -- check w itself
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

    -- check w's sub-widgets.
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

function UIManager:forceRepaintIfFastRefreshEnabled()
  if G_named_settings.fast_screen_refresh() then
    self:forceRepaint()
  end
end

UIManager:init()
return UIManager
