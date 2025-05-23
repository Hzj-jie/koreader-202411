--[[--
This module is responsible for converting files.
]]

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local FileConverter = {
  formats_from = {
    md = {
      -- @translators See <https://en.wikipedia.org/wiki/Markdown>. In languages written in the Latin alphabet this is unlikely to change.
      name = _("Markdown"),
      from = "markdown",
    },
  },
  formats_to = {
    epub = {
      to = "epub",
    },
    html = {
      to = "html",
    },
    pdf = {
      to = "pdf",
    },
  },
  --curl --form input_files[]=@README.md --form from=markdown  --form to=pdf http://c.docverter.com/convert
  docverter_url = "http://c.docverter.com/convert",
}

--- Converts a markdown fragment to a full HTML document.
---- @string markdown the markdown fragment
---- @string title an optional title for the HTML document
---- @treturn string an HTML document
function FileConverter:mdToHtml(markdown, title, stylesheet)
  local MD = require("apps/filemanager/lib/md")
  stylesheet = stylesheet
      and string.format("<style>\n%s\n</style>\n", stylesheet)
    or ""
  local md_options = {
    prependHead = "<!DOCTYPE html>\n<html>\n<head>\n",
    insertHead = string.format(
      "<title>%s</title>\n%s</head>\n<body>\n",
      title,
      stylesheet
    ),
    appendTail = "\n</body>\n</html>",
  }
  local html, err = MD(markdown, md_options)
  if err then
    logger.warn("FileManagerConverter: could not generate HTML", err)
  end
  return html
end

function FileConverter:_mdFileToHtml(file, title)
  local f = io.open(file, "rb")
  if f == nil then
    return
  end
  local content = f:read("*all")
  f:close()
  local html = self:mdToHtml(content, title)
  return html
end

function FileConverter:isSupported(file)
  return self.formats_from[util.getFileNameSuffix(file)] and true or false
end

function FileConverter:showConvertButtons(file, ui)
  local __, filename_pure = util.splitFilePathName(file)
  local filename_suffix = util.getFileNameSuffix(file)
  local filetype_name = self.formats_from[filename_suffix].name
  self.convert_dialog = ButtonDialog:new({
    title = T(_("Convert %1 to:"), filetype_name),
    buttons = {
      {
        {
          text = _("HTML"),
          callback = function()
            local html = self:_mdFileToHtml(file, filename_pure)
            if not html then
              return
            end
            local filename_html = file .. ".html"
            if lfs.attributes(filename_html, "mode") == "file" then
              UIManager:show(ConfirmBox:new({
                text = _("Overwrite existing HTML file?"),
                ok_text = _("Overwrite"),
                ok_callback = function()
                  util.writeToFile(html, filename_html)
                  UIManager:close(self.convert_dialog)
                end,
              }))
            else
              util.writeToFile(html, filename_html)
              ui:refreshPath()
              UIManager:close(self.convert_dialog)
            end
          end,
        },
      },
    },
  })
  self.convert_dialog.onClose = function(this)
    local super = getmetatable(this)
    if super.onClose then
      -- Call our super's method, if any
      super.onClose(this)
    end
    -- And then do our own cleanup
    self:cleanup()
  end
  UIManager:show(self.convert_dialog)
end

function FileConverter:cleanup()
  self.convert_dialog = nil
end

return FileConverter
