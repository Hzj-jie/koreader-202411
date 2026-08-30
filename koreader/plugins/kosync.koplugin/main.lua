local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local Math = require("optmath")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local Notification = require("ui/widget/notification")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local md5 = require("ffi/sha2").md5
local random = require("random")
local time = require("ui/time")
local util = require("util")
local T = require("ffi/util").template
local gettext = require("gettext")

if G_reader_settings:hasNot("device_id") then
  G_reader_settings:save("device_id", random.uuid())
end

local KOSync = WidgetContainer:extend({
  name = "kosync",
  is_doc_only = true,
  title = gettext("Register/login to KOReader server"),

  push_timestamp = nil,
  pull_timestamp = nil,
  last_page_turn_timestamp = nil,

  settings = nil,
})

local SYNC_STRATEGY = {
  PROMPT = 1,
  SILENT = 2,
  DISABLE = 3,
}

local CHECKSUM_METHOD = {
  BINARY = 0,
  FILENAME = 1,
}

-- Debounce push/pull attempts
local API_CALL_DEBOUNCE_DELAY = time.s(25)

function KOSync:init()
  self.push_timestamp = 0
  self.pull_timestamp = 0
  self.last_page_turn_timestamp = 0

  self.settings = G_reader_settings:readTableRef("kosync", {
    custom_server = nil,
    username = nil,
    userkey = nil,
    -- Do *not* default to auto-sync, as wifi may not be on at all times, and the nagging enabling this may cause requires careful consideration.
    auto_sync = false,
    sync_forward = SYNC_STRATEGY.PROMPT,
    sync_backward = SYNC_STRATEGY.DISABLE,
    checksum_method = CHECKSUM_METHOD.BINARY,
  })
  self.device_id = G_reader_settings:read("device_id")

  -- Disable auto-sync if beforeWifiAction was reset to "prompt" behind our back...
  if
    self.settings.auto_sync
    and Device:hasSeamlessWifiToggle()
    and G_reader_settings:read("wifi_enable_action") ~= "turn_on"
  then
    self.settings.auto_sync = false
    logger.warn(
      "KOSync: Automatic sync has been disabled because wifi_enable_action is *not* turn_on"
    )
  end

  self.ui.menu:registerToMainMenu(self)

  if
    self.ui.doc_settings and self.ui.doc_settings:read("partial_md5_checksum")
  then
    self:initDocumentState()
  end
end

function KOSync:initDocumentState()
  if self.data_initialized then
    return
  end
  self.data_initialized = true

  if self.settings.auto_sync then
    UIManager:scheduleIn(0.1, function()
      self.last_page_turn_timestamp = 0
      self:_getProgress(false)
    end)
  end
  self:onDispatcherRegisterActions()
end

local function getNameStrategy(type)
  if type == 1 then
    return gettext("Prompt")
  elseif type == 2 then
    return gettext("Auto")
  else
    return gettext("Disable")
  end
end

local function showSyncedMessage()
  -- Unlike push, pulling progress is
  -- 1. noticeable, since the page was turned automatically.
  -- 2. usually following with reading experience.
  -- So instead of using an InfoMessage, shows a notification to avoid blocking
  -- most of the screen would provide a better user experience. Similar to the
  -- notifications used to change the font size.
  Notification:notify(gettext("Progress has been synchronized."))
end

local function promptLogin()
  UIManager:show(InfoMessage:new({
    text = gettext(
      "Please register or login before using the progress synchronization feature."
    ),
    timeout = 3,
  }))
end

local function showSyncError()
  UIManager:show(InfoMessage:new({
    text = gettext(
      "Something went wrong when syncing progress, please check your network connection and try again later."
    ),
    timeout = 3,
  }))
end

local function validate(entry)
  if not entry then
    return false
  end
  if type(entry) == "string" then
    if entry == "" or not entry:match("%S") then
      return false
    end
  end
  return true
end

local function validateUser(user, pass)
  local error_message = nil
  local user_ok = validate(user)
  local pass_ok = validate(pass)
  if not user_ok and not pass_ok then
    error_message = gettext("invalid username and password")
  elseif not user_ok then
    error_message = gettext("invalid username")
  elseif not pass_ok then
    error_message = gettext("invalid password")
  end

  if not error_message then
    return user_ok and pass_ok
  else
    return user_ok and pass_ok, error_message
  end
end

function KOSync:_createClient()
  return require("plugins/kosync.koplugin/KOSyncClient"):new({
    custom_url = self.settings.custom_server,
    service_spec = self.path .. "/api.json",
  })
end

function KOSync:onDispatcherRegisterActions()
  Dispatcher:registerAction("kosync_push_progress", {
    category = "none",
    event = "KOSyncPushProgress",
    title = gettext("Push progress from this device"),
    reader = true,
  })
  Dispatcher:registerAction("kosync_pull_progress", {
    category = "none",
    event = "KOSyncPullProgress",
    title = gettext("Pull progress from other devices"),
    reader = true,
    separator = true,
  })
end

function KOSync:onReaderReady()
  self:initDocumentState()
end

function KOSync:addToMainMenu(menu_items)
  menu_items.progress_sync = {
    text = gettext("Progress sync"),
    sub_item_table = {
      {
        text = gettext("Custom sync server"),
        keep_menu_open = true,
        tap_input_func = function()
          return {
            -- @translators Server address defined by user for progress sync.
            title = gettext("Custom progress sync server address"),
            input = self.settings.custom_server
              or self.last_custom_server_attempt
              or "https://",
            allow_blank_input = true,
            callback = function(input)
              self:setCustomServer(input)
            end,
          }
        end,
      },
      {
        text_func = function()
          return self.settings.userkey and (gettext("Logout"))
            or gettext("Register") .. " / " .. gettext("Login")
        end,
        keep_menu_open = true,
        callback_func = function()
          if self.settings.userkey then
            return function(menu)
              self:_logout(menu)
            end
          else
            return function(menu)
              self:_login(menu)
            end
          end
        end,
        separator = true,
      },
      {
        text = gettext("Automatically keep documents in sync"),
        checked_func = function()
          return self.settings.auto_sync
        end,
        help_text = gettext(
          "Enable the feature will automatically pull and push progress when necessary."
        )
          .. "\n\n"
          .. gettext(
            [[This may lead to nagging about toggling WiFi on document close and suspend/resume, depending on the device's connectivity.]]
          ),
        callback = function()
          -- Actively recommend switching the before wifi action to "turn_on" instead of prompt, as prompt will just not be practical (or even plain usable) here.
          if
            Device:hasSeamlessWifiToggle()
            and G_reader_settings:read("wifi_enable_action") ~= "turn_on"
            and not self.settings.auto_sync
          then
            UIManager:show(InfoMessage:new({
              text = gettext(
                "You will have to switch the 'Action when Wi-Fi is off' Network setting to 'turn on' to be able to enable this feature!"
              ),
            }))
            return
          end

          self.settings.auto_sync = not self.settings.auto_sync
          if self.settings.auto_sync then
            -- Since we will update the progress when closing the document,
            -- pull the current progress now so as not to silently overwrite it.
            self:_getProgress(true)
          else
            -- Since we won't update the progress when closing the document,
            -- push the current progress now so as not to lose it.
            self:_updateProgress(true)
          end
        end,
      },
      {
        text_func = function()
          -- NOTE: With an up-to-date Sync server, "forward" means *newer*, not necessarily ahead in the document.
          return T(
            gettext("Sync to a newer state (%1)"),
            getNameStrategy(self.settings.sync_forward)
          )
        end,
        sub_item_table = {
          {
            text = gettext("Silently"),
            checked_func = function()
              return self.settings.sync_forward == SYNC_STRATEGY.SILENT
            end,
            callback = function()
              self:setSyncForward(SYNC_STRATEGY.SILENT)
            end,
          },
          {
            text = gettext("Prompt"),
            checked_func = function()
              return self.settings.sync_forward == SYNC_STRATEGY.PROMPT
            end,
            callback = function()
              self:setSyncForward(SYNC_STRATEGY.PROMPT)
            end,
          },
          {
            text = gettext("Never"),
            checked_func = function()
              return self.settings.sync_forward == SYNC_STRATEGY.DISABLE
            end,
            callback = function()
              self:setSyncForward(SYNC_STRATEGY.DISABLE)
            end,
          },
        },
      },
      {
        text_func = function()
          return T(
            gettext("Sync to an older state (%1)"),
            getNameStrategy(self.settings.sync_backward)
          )
        end,
        sub_item_table = {
          {
            text = gettext("Silently"),
            checked_func = function()
              return self.settings.sync_backward == SYNC_STRATEGY.SILENT
            end,
            callback = function()
              self:setSyncBackward(SYNC_STRATEGY.SILENT)
            end,
          },
          {
            text = gettext("Prompt"),
            checked_func = function()
              return self.settings.sync_backward == SYNC_STRATEGY.PROMPT
            end,
            callback = function()
              self:setSyncBackward(SYNC_STRATEGY.PROMPT)
            end,
          },
          {
            text = gettext("Never"),
            checked_func = function()
              return self.settings.sync_backward == SYNC_STRATEGY.DISABLE
            end,
            callback = function()
              self:setSyncBackward(SYNC_STRATEGY.DISABLE)
            end,
          },
        },
        separator = true,
      },
      {
        text = gettext("Push progress from this device now"),
        enabled_func = function()
          return self.settings.userkey ~= nil
        end,
        callback = function()
          self:_updateProgress(true)
        end,
      },
      {
        text = gettext("Pull progress from other devices now"),
        enabled_func = function()
          return self.settings.userkey ~= nil
        end,
        callback = function()
          self:_getProgress(true)
        end,
        separator = true,
      },
      {
        text = gettext("Document matching method"),
        sub_item_table = {
          {
            text = gettext(
              "Binary. Only identical files will be kept in sync."
            ),
            checked_func = function()
              return self.settings.checksum_method == CHECKSUM_METHOD.BINARY
            end,
            callback = function()
              self:setChecksumMethod(CHECKSUM_METHOD.BINARY)
            end,
          },
          {
            text = gettext(
              "Filename. Files with matching names will be kept in sync."
            ),
            checked_func = function()
              return self.settings.checksum_method == CHECKSUM_METHOD.FILENAME
            end,
            callback = function()
              self:setChecksumMethod(CHECKSUM_METHOD.FILENAME)
            end,
          },
        },
      },
    },
  }
end

function KOSync:setCustomServer(server)
  logger.dbg("KOSync: Setting custom server to:", server)
  local prev_server = self.settings.custom_server
  self.settings.custom_server = server ~= "" and server or nil
  local ok, err = pcall(KOSync._createClient, self)
  if ok then
    return
  end
  self.settings.custom_server = prev_server
  -- Keep a reference to retry.
  self.last_custom_server_attempt = server
  UIManager:show(InfoMessage:new({
    text = T(
      gettext(
        "The new server address %1 is invalid, revert back to %2.\nError: %3"
      ),
      server,
      prev_server or "default server",
      err
    ),
    timeout = 3,
  }))
end

function KOSync:setSyncForward(strategy)
  self.settings.sync_forward = strategy
end

function KOSync:setSyncBackward(strategy)
  self.settings.sync_backward = strategy
end

function KOSync:setChecksumMethod(method)
  self.settings.checksum_method = method
end

function KOSync:_login(menu)
  NetworkMgr:runWhenOnline(function()
    -- For closure capture.
    local dialog
    dialog = MultiInputDialog:new({
      title = self.title,
      fields = {
        {
          text = self.settings.username,
          hint = "username",
        },
        {
          hint = "password",
          text_type = "password",
        },
      },
      buttons = {
        {
          {
            text = gettext("Cancel"),
            id = "close",
            callback = function()
              UIManager:close(dialog)
            end,
          },
          {
            text = gettext("Login"),
            callback = function()
              local username, password = unpack(dialog:getFields())
              local ok, err = validateUser(username, password)
              if not ok then
                UIManager:show(InfoMessage:new({
                  text = T(gettext("Cannot login: %1"), err),
                  timeout = 2,
                }))
              else
                UIManager:close(dialog)
                UIManager:runWith(function()
                  self:_doLogin(username, password, menu)
                end, gettext("Logging in. Please wait…"))
              end
            end,
          },
          {
            text = gettext("Register"),
            callback = function()
              local username, password = unpack(dialog:getFields())
              local ok, err = validateUser(username, password)
              if not ok then
                UIManager:show(InfoMessage:new({
                  text = T(gettext("Cannot register: %1"), err),
                  timeout = 2,
                }))
              else
                UIManager:close(dialog)
                UIManager:scheduleIn(0.5, function()
                  self:_doRegister(username, password, menu)
                end)
                UIManager:show(InfoMessage:new({
                  text = gettext("Registering. Please wait…"),
                  timeout = 1,
                }))
              end
            end,
          },
        },
      },
    })
    UIManager:show(dialog)
  end)
end

function KOSync:_doRegister(username, password, menu)
  local client = self:_createClient()
  -- on Android to avoid ANR (no-op on other platforms)
  Device:setIgnoreInput(true)
  local userkey = md5(password)
  local ok, status, body = pcall(client.register, client, username, userkey)
  if not ok then
    if status then
      UIManager:show(InfoMessage:new({
        text = gettext("An error occurred while registering:")
          .. "\n"
          .. status,
      }))
    else
      UIManager:show(InfoMessage:new({
        text = gettext("An unknown error occurred while registering."),
      }))
    end
  elseif status then
    self.settings.username = username
    self.settings.userkey = userkey
    if menu then
      menu:updateItems()
    end
    UIManager:show(InfoMessage:new({
      text = gettext("Registered to KOReader server."),
    }))
  else
    UIManager:show(InfoMessage:new({
      text = body and body.message or gettext("Unknown server error"),
    }))
  end
  Device:setIgnoreInput(false)
end

function KOSync:_doLogin(username, password, menu)
  local client = self:_createClient()
  Device:setIgnoreInput(true)
  local userkey = md5(password)
  local ok, status, body = pcall(client.authorize, client, username, userkey)
  if not ok then
    if status then
      UIManager:show(InfoMessage:new({
        text = gettext("An error occurred while logging in:") .. "\n" .. status,
      }))
    else
      UIManager:show(InfoMessage:new({
        text = gettext("An unknown error occurred while logging in."),
      }))
    end
    Device:setIgnoreInput(false)
    return
  elseif status then
    self.settings.username = username
    self.settings.userkey = userkey
    if menu then
      menu:updateItems()
    end
    UIManager:show(InfoMessage:new({
      text = gettext("Logged in to KOReader server."),
    }))
  else
    UIManager:show(InfoMessage:new({
      text = body and body.message or gettext("Unknown server error"),
    }))
  end
  Device:setIgnoreInput(false)
end

function KOSync:_logout(menu)
  self.settings.userkey = nil
  self.settings.auto_sync = true
  if menu then
    menu:updateItems()
  end
end

function KOSync:_getLastPercent()
  if self.ui.document.info.has_pages then
    return Math.roundPercent(self.ui.paging:getLastPercent())
  else
    return Math.roundPercent(self.ui.rolling:getLastPercent())
  end
end

function KOSync:_getLastProgress()
  if self.ui.document.info.has_pages then
    return self.ui.paging:getLastProgress()
  else
    return self.ui.rolling:getLastProgress()
  end
end

function KOSync:_getDocumentDigest()
  if not self.ui or not self.ui.document then
    return nil
  end
  if self.settings.checksum_method ~= CHECKSUM_METHOD.FILENAME then
    return self.ui.doc_settings and self.ui.doc_settings:read("partial_md5_checksum")
  end
  local file = self.ui.document.file
  if not file then
    return nil
  end

  local _, file_name = util.splitFilePathName(file)
  return md5(file_name)
end

function KOSync:_syncToProgress(progress)
  logger.dbg("KOSync: [Sync] progress to", progress)
  if self.ui.document == nil then
    return
  end

  if self.ui.document.info.has_pages then
    UIManager:broadcastEvent(Event:new("GotoPage", tonumber(progress)))
  else
    UIManager:broadcastEvent(Event:new("GotoXPointer", progress))
  end
end

local function sendPushRequest(
  client,
  username,
  userkey,
  doc_digest,
  progress,
  percentage,
  device_model,
  device_id
)
  if not NetworkMgr:isOnline() then
    return false, "offline"
  end
  local push_ok, push_body
  local ok, err = pcall(
    client.update_progress,
    client,
    username,
    userkey,
    doc_digest,
    progress,
    percentage,
    device_model,
    device_id,
    function(res_ok, body)
      push_ok = res_ok
      push_body = body
    end
  )
  if not ok then
    return false, err
  end
  return push_ok, push_body
end

local function applyPushUI(ok, doc_digest, interactive)
  logger.dbg("KOSync: [Push] ok:", ok, "doc_digest:", doc_digest)
  if interactive then
    if ok then
      UIManager:show(InfoMessage:new({
        text = gettext("Progress has been pushed."),
        timeout = 3,
      }))
    else
      showSyncError()
    end
  end
end

local function sendPullRequest(client, username, userkey, doc_digest)
  if not NetworkMgr:isOnline() then
    return false, "offline"
  end
  local pull_ok, pull_body
  local ok, err = pcall(
    client.get_progress,
    client,
    username,
    userkey,
    doc_digest,
    function(res_ok, body)
      pull_ok = res_ok
      pull_body = body
    end
  )
  if not ok then
    return false, err
  end
  return pull_ok, pull_body
end

function KOSync:_applyPullUI(
  ok,
  body,
  doc_digest,
  interactive,
  local_progress,
  local_percentage
)
  if self.ui ~= ReaderUI.instance then
    return
  end
  if self:_getDocumentDigest() ~= doc_digest then
    return
  end

  logger.dbg("KOSync: [Pull] progress for", self.ui.document.file)
  if not ok or not body then
    logger.dbg("KOSync: error body:", body)
    if interactive then
      showSyncError()
    end
    return
  end

  local showInfo = function(msg)
    if interactive then
      UIManager:show(InfoMessage:new({
        text = msg,
        timeout = 3,
      }))
    end
  end

  if not body.percentage then
    showInfo(gettext("No progress found for this document."))
    return
  end

  if body.device == Device.model and body.device_id == self.device_id then
    showInfo(gettext("Latest progress is coming from this device."))
    return
  end

  local remote_percentage = Math.roundPercent(body.percentage)
  if local_percentage == remote_percentage or body.progress == local_progress then
    showInfo(gettext("The progress has already been synchronized."))
    return
  end

  if interactive then
    self:_syncToProgress(body.progress)
    showSyncedMessage()
    return
  end

  local is_newer
  if body.timestamp ~= nil then
    is_newer = (body.timestamp > self.last_page_turn_timestamp)
  else
    -- If we are working with an old sync server, we can only use the percentage field.
    is_newer = (body.percentage > local_percentage)
  end

  local strategy = is_newer and self.settings.sync_forward or self.settings.sync_backward

  if strategy == SYNC_STRATEGY.SILENT then
    self:_syncToProgress(body.progress)
    showSyncedMessage()
  elseif strategy == SYNC_STRATEGY.PROMPT then
    local prompt_text
    if is_newer then
      prompt_text = T(
        gettext("Sync to latest location %1% from device '%2'?"),
        Math.round(remote_percentage * 100),
        body.device
      )
    else
      prompt_text = T(
        gettext("Sync to previous location %1% from device '%2'?"),
        Math.round(remote_percentage * 100),
        body.device
      )
    end
    UIManager:show(ConfirmBox:new({
      text = prompt_text,
      ok_callback = function()
        if self.ui ~= ReaderUI.instance or self:_getDocumentDigest() ~= doc_digest then
          return
        end
        self:_syncToProgress(body.progress)
      end,
    }))
  end
end

function KOSync:_updateProgress(interactive)
  if self.ui.document == nil then
    return
  end

  if not self.settings.username or not self.settings.userkey then
    if interactive then
      promptLogin()
    end
    return
  end

  local now = UIManager:getElapsedTimeSinceBoot()
  if
    not interactive and now - self.push_timestamp <= API_CALL_DEBOUNCE_DELAY
  then
    logger.dbg("KOSync: We've already pushed progress less than 25s ago!")
    return
  end
  self.push_timestamp = now

  local client = self:_createClient()
  local doc_digest = self:_getDocumentDigest()
  local progress = self:_getLastProgress()
  local percentage = self:_getLastPercent()
  local username = self.settings.username
  local userkey = self.settings.userkey
  local device_id = self.device_id

  -- No self in this function, the execution may be delayed.
  local function exec()
    local ok, body = sendPushRequest(
      client,
      username,
      userkey,
      doc_digest,
      progress,
      percentage,
      Device.model,
      device_id
    )
    applyPushUI(
      ok,
      doc_digest,
      interactive
    )
  end

  if interactive then
    UIManager:runWith(function()
      NetworkMgr:runWhenOnline(exec)
    end, gettext("Pushing progress…"))
  else
    NetworkMgr:willRerunWhenOnline(exec)
  end
end

function KOSync:_getProgress(interactive)
  if self.ui.document == nil then
    return
  end

  if not self.settings.username or not self.settings.userkey then
    if interactive then
      promptLogin()
    end
    return
  end

  local now = UIManager:getElapsedTimeSinceBoot()
  if
    not interactive and now - self.pull_timestamp <= API_CALL_DEBOUNCE_DELAY
  then
    logger.dbg("KOSync: We've already pulled progress less than 25s ago!")
    return
  end
  self.pull_timestamp = now

  local client = self:_createClient()
  local doc_digest = self:_getDocumentDigest()
  local username = self.settings.username
  local userkey = self.settings.userkey
  local progress = self:_getLastProgress()
  local percentage = self:_getLastPercent()

  local function exec()
    -- Unlike pushProgress, it's unreasonable to get the progress as a pending
    -- job after user closing the document. In the case, ignore the request.
    if self.ui ~= ReaderUI.instance or self:_getDocumentDigest() ~= doc_digest then
      return
    end

    local ok, body = sendPullRequest(
      client,
      username,
      userkey,
      doc_digest
    )
    self:_applyPullUI(
      ok,
      body,
      doc_digest,
      interactive,
      progress,
      percentage
    )
  end

  if interactive then
    UIManager:runWith(function()
      NetworkMgr:runWhenOnline(exec)
    end, gettext("Pulling progress…"))
  else
    NetworkMgr:willRerunWhenOnline(exec)
  end
end

function KOSync:onPageUpdate(page)
  if not self.settings.auto_sync then
    return
  end
  if page == nil then
    return
  end
  self.last_page_turn_timestamp = os.time()
end

function KOSync:onSaveSettings()
  if not self.settings.auto_sync then
    return
  end
  -- Do not block the current event, also give sufficient time to respond the
  -- user activity.
  UIManager:scheduleIn(0.1, function()
    -- Force triggering a push.
    self.push_timestamp = 0
    self:_updateProgress(false)
  end)
end

function KOSync:onResume()
  if not self.settings.auto_sync then
    return
  end
  -- If we have auto_restore_wifi enabled, skip this to prevent both the "Connecting..." UI to pop-up,
  -- *and* a duplicate NetworkConnected event from firing...
  if NetworkMgr:shouldRestoreWifi() then
    return
  end

  -- And if we don't, this *will* (attempt to) trigger a connection and as such a NetworkConnected event,
  -- but only a single pull will happen, since _getProgress debounces itself.
  UIManager:scheduleIn(0.1, function()
    self:_getProgress(false)
  end)
end

function KOSync:onSuspend()
  if not self.settings.auto_sync then
    return
  end
  -- We request an extra flashing refresh on success, to deal with potential ghosting left by the NetworkMgr UI
  self:_updateProgress(false)
end

function KOSync:onNetworkOnline()
  if not self.settings.auto_sync then
    return
  end
  self:_getProgress(false)
end

function KOSync:onNetworkDisconnecting()
  if not self.settings.auto_sync then
    return
  end
  self:_updateProgress(false)
end

function KOSync:onKOSyncPushProgress()
  self:_updateProgress(true)
end

function KOSync:onKOSyncPullProgress()
  self:_getProgress(true)
end

return KOSync
