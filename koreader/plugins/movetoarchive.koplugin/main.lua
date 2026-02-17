local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local DocSettings = require("docsettings")
local Event = require("ui/event")
local FileManager = require("apps/filemanager/filemanager")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("frontend/luasettings")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("frontend/util")
local BaseUtil = require("ffi/util")
local gettext = require("gettext")

local MoveToArchive = WidgetContainer:extend({
  name = "movetoarchive",
  title = gettext("Move current book to archive"),
})

function MoveToArchive:onDispatcherRegisterActions()
  Dispatcher:registerAction(self.name, {
    category = "none",
    event = "MoveToArchive",
    title = self.title,
    reader = true,
  })
end

function MoveToArchive:init()
  self:onDispatcherRegisterActions()
  self.ui.menu:registerToMainMenu(self)
  self.settings = LuaSettings:open(
    ("%s/%s"):format(
      DataStorage:getSettingsDir(),
      "move_to_archive_settings.lua"
    )
  )
  self.archive_dir_path = self.settings:read("archive_dir")
  self.last_copied_from_dir = self.settings:read("last_copied_from_dir")
end

function MoveToArchive:addToMainMenu(menu_items)
  menu_items.move_to_archive = {
    text = gettext("Move to archive"),
    sub_item_table = {
      {
        text = self.title,
        callback = function()
          self:onMoveToArchive()
        end,
        enabled_func = function()
          return self:isActionEnabled()
        end,
      },
      {
        text = gettext("Copy current book to archive"),
        callback = function()
          self:onMoveToArchive(true)
        end,
        enabled_func = function()
          return self:isActionEnabled()
        end,
      },
      {
        text = gettext("Go to archive folder"),
        callback = function()
          if
            self.archive_dir_path
            and util.directoryExists(self.archive_dir_path)
          then
            self:openFileBrowser(self.archive_dir_path)
          else
            self:showNoArchiveConfirmBox()
          end
        end,
      },
      {
        text = gettext("Go to last copied/moved from folder"),
        callback = function()
          if self.last_copied_from_dir then
            self:openFileBrowser(self.last_copied_from_dir)
          else
            UIManager:show(InfoMessage:new({
              text = gettext("No previous folder found."),
            }))
          end
        end,
      },
      {
        text = gettext("Set archive folder"),
        keep_menu_open = true,
        callback = function()
          self:setArchiveDirectory()
        end,
      },
    },
  }
end

function MoveToArchive:onMoveToArchive(do_copy)
  if not self.archive_dir_path then
    self:showNoArchiveConfirmBox()
    return
  end
  local document_full_path = self.ui.document.file
  local filename
  self.last_copied_from_dir, filename =
    util.splitFilePathName(document_full_path)
  local dest_file = string.format("%s%s", self.archive_dir_path, filename)

  self.settings:save("last_copied_from_dir", self.last_copied_from_dir)
  self.settings:flush()

  UIManager:broadcastEvent(Event:new("SetupShowReader"))

  self.ui:onExit()
  local text
  if do_copy then
    text = gettext("Book copied.\nDo you want to open it from the archive folder?")
    FileManager:copyFileFromTo(document_full_path, self.archive_dir_path)
  else
    text = gettext("Book moved.\nDo you want to open it from the archive folder?")
    FileManager:moveFile(document_full_path, self.archive_dir_path)
    require("readhistory"):updateItem(document_full_path, dest_file) -- (will update "lastfile" if needed)
    require("readcollection"):updateItem(document_full_path, dest_file)
  end
  DocSettings.updateLocation(document_full_path, dest_file, do_copy)
  UIManager:show(ConfirmBox:new({
    text = text,
    ok_callback = function()
      local ReaderUI = require("apps/reader/readerui")
      ReaderUI:showReader(dest_file)
    end,
    cancel_callback = function()
      self:openFileBrowser(self.last_copied_from_dir)
    end,
  }))
end

function MoveToArchive:setArchiveDirectory()
  require("ui/downloadmgr")
    :new({
      onConfirm = function(path)
        self.archive_dir_path = ("%s/"):format(path)
        self.settings:save("archive_dir", self.archive_dir_path)
        self.settings:flush()
      end,
    })
    :chooseDir()
end

function MoveToArchive:showNoArchiveConfirmBox()
  UIManager:show(ConfirmBox:new({
    text = gettext("No archive directory.\nDo you want to set it now?"),
    ok_text = gettext("Set archive folder"),
    ok_callback = function()
      self:setArchiveDirectory()
    end,
  }))
end

function MoveToArchive:isActionEnabled()
  return self.ui.document ~= nil
    and (
      (BaseUtil.dirname(self.ui.document.file) .. "/") ~= self.archive_dir_path
    )
end

function MoveToArchive:openFileBrowser(path)
  if self.ui.document then
    self.ui:onExit()
  end
  if FileManager.instance then
    FileManager.instance:reinit(path)
  else
    FileManager:showFiles(path)
  end
end

return MoveToArchive
