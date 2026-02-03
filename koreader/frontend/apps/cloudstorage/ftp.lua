local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local DocumentRegistry = require("document/documentregistry")
local FtpApi = require("apps/cloudstorage/ftpapi")
local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local ltn12 = require("ltn12")
local logger = require("logger")
local util = require("util")
local gettext = require("gettext")
local T = require("ffi/util").template

local Ftp = {}

function Ftp:run(address, user, pass, path)
  local url = FtpApi:generateUrl(address, util.urlEncode(user), util.urlEncode(pass)) .. path
  return FtpApi:listFolder(url, path)
end

function Ftp:downloadFile(item, address, user, pass, path, callback_close)
  local url = FtpApi:generateUrl(address, util.urlEncode(user), util.urlEncode(pass)) .. item.url
  logger.dbg("downloadFile url", url)
  path = util.fixUtf8(path, "_")
  local file, err = io.open(path, "w")
  if not file then
    UIManager:show(InfoMessage:new({
      text = T(gettext("Could not save file to %1:\n%2"), BD.filepath(path), err),
    }))
    return
  end
  local response = FtpApi:ftpGet(url, "retr", ltn12.sink.file(file))
  if response ~= nil then
    local __, filename = util.splitFilePathName(path)
    if G_reader_settings:isTrue("show_unsupported") and not DocumentRegistry:hasProvider(filename) then
      UIManager:show(InfoMessage:new({
        text = T(gettext("File saved to:\n%1"), BD.filepath(path)),
      }))
    else
      UIManager:show(ConfirmBox:new({
        text = T(gettext("File saved to:\n%1\nWould you like to read the downloaded book now?"), BD.filepath(path)),
        ok_callback = function()
          local Event = require("ui/event")
          UIManager:broadcastEvent(Event:new("SetupShowReader"))

          if callback_close then
            callback_close()
          end

          ReaderUI:showReader(path)
        end,
      }))
    end
  else
    UIManager:show(InfoMessage:new({
      text = T(gettext("Could not save file to:\n%1"), BD.filepath(path)),
      timeout = 3,
    }))
  end
end

function Ftp:config(item, callback)
  local text_info = gettext([[
The FTP address must be in the following format:
ftp://example.domain.com
An IP address is also supported, for example:
ftp://10.10.10.1
Username and password are optional.]])
  local hint_name = gettext("Your FTP name")
  local text_name = ""
  local hint_address = gettext("FTP address eg ftp://example.com")
  local text_address = ""
  local hint_username = gettext("FTP username")
  local text_username = ""
  local hint_password = gettext("FTP password")
  local text_password = ""
  local hint_folder = gettext("FTP folder")
  local text_folder = "/"
  local title
  local text_button_right = gettext("Add")
  if item then
    title = gettext("Edit FTP account")
    text_button_right = gettext("Apply")
    text_name = item.text
    text_address = item.address
    text_username = item.username
    text_password = item.password
    text_folder = item.url
  else
    title = gettext("Add FTP account")
  end
  self.settings_dialog = MultiInputDialog:new({
    title = title,
    fields = {
      {
        text = text_name,
        input_type = "string",
        hint = hint_name,
      },
      {
        text = text_address,
        input_type = "string",
        hint = hint_address,
      },
      {
        text = text_username,
        input_type = "string",
        hint = hint_username,
      },
      {
        text = text_password,
        input_type = "string",
        text_type = "password",
        hint = hint_password,
      },
      {
        text = text_folder,
        input_type = "string",
        hint = hint_folder,
      },
    },
    buttons = {
      {
        {
          text = gettext("Cancel"),
          id = "close",
          callback = function()
            self.settings_dialog:onExit()
            UIManager:close(self.settings_dialog)
          end,
        },
        {
          text = gettext("Info"),
          callback = function()
            UIManager:show(InfoMessage:new({ text = text_info }))
          end,
        },
        {
          text = text_button_right,
          callback = function()
            local fields = self.settings_dialog:getFields()
            if fields[1] ~= "" and fields[2] ~= "" then
              if item then
                -- edit
                callback(item, fields)
              else
                -- add new
                callback(fields)
              end
              self.settings_dialog:onExit()
              UIManager:close(self.settings_dialog)
            else
              UIManager:show(InfoMessage:new({
                text = gettext("Please fill in all fields."),
              }))
            end
          end,
        },
      },
    },
    input_type = "text",
  })
  UIManager:show(self.settings_dialog)
end

function Ftp:info(item)
  local info_text = T(gettext("Type: %1\nName: %2\nAddress: %3"), "FTP", item.text, item.address)
  UIManager:show(InfoMessage:new({ text = info_text }))
end

return Ftp
