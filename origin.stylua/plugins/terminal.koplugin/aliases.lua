local KeyValuePage = require("ui/widget/keyvaluepage")
local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local util = require("util")
local T = require("ffi/util").template

local Aliases = {
  filename = "",
  close_callback = nil,
  parent = nil,

  alias_kv = nil,
  kv_pairs = {},
}

function Aliases:show(filename, close_callback, parent)
  self.filename = filename
  self.close_callback = close_callback
  self.parent = parent
  self:load()

  self.alias_kv = KeyValuePage:new({
    title = "Aliases (Shortcuts)",
    kv_pairs = self.kv_pairs,
    close_callback = self.close_callback,
  })
  UIManager:show(self.alias_kv)
end

function Aliases:updateKeyValues()
  self.alias_kv.kv_pairs = self.kv_pairs
  UIManager:close(self.alias_kv)
  self.alias_kv = KeyValuePage:new({
    title = "Aliases (Shortcuts)",
    kv_pairs = self.kv_pairs,
    close_callback = self.close_callback,
  })
  UIManager:show(self.alias_kv)
end

function Aliases:load()
  local file = io.open(self.filename, "r")
  self.kv_pairs = {}
  if file then
    for line in file:lines() do
      line = line:gsub("^ *alias *", "") -- drop alias
      local dummy, separator = line:find("^[%a%d][%a%d-_]*%=") -- find separator
      if line ~= "" and line:sub(1, 1) ~= "#" and separator then
        local alias_name = line:sub(1, separator - 1)
        local alias_command = line:sub(separator + 1):gsub('"', "")
        table.insert(self.kv_pairs, {
          alias_name,
          alias_command,
          callback = function()
            self.editAlias(self, alias_name, alias_command)
          end,
        })
      end
    end
    file:close()
    table.sort(self.kv_pairs, function(a, b)
      return a[1] < b[1]
    end)
  end

  table.insert(self.kv_pairs, 1, {
    _("Create a new alias"),
    "",
    callback = function()
      self.editAlias(self, "", "")
    end,
  })
  table.insert(self.kv_pairs, 2, "---")
end

function Aliases:save()
  local file = io.open(self.filename .. ".new", "w")
  if not file then
    UIManager:show(InfoMessage:new({
      text = T(_("Terminal emulator: error saving: %1"), self.filename),
    }))
  end
  file:write("# Aliases generated by terminal emulator\n\n")
  for i = 3, #self.kv_pairs do
    file:write(
      "alias " .. self.kv_pairs[i][1] .. '="' .. self.kv_pairs[i][2] .. '"\n'
    )
  end
  file:close()
  os.remove(self.filename)
  os.rename(self.filename .. ".new", self.filename)
end

function Aliases:editAlias(alias_name, alias_command)
  local alias_input
  alias_input = MultiInputDialog:new({
    title = _("Edit alias"),
    fields = {
      {
        description = _("Alias name:"),
        text = alias_name,
      },
      {
        description = _("Alias command:"),
        text = alias_command,
      },
    },
    buttons = {
      {
        {
          text = _("Cancel"),
          callback = function()
            UIManager:close(alias_input)
          end,
        },
        {
          text = _("Delete"),
          callback = function()
            UIManager:close(alias_input)
            for i, v in pairs(self.kv_pairs) do
              if v[1] == alias_name then
                table.remove(self.kv_pairs, i)
                self.parent:transmit("unalias " .. alias_name .. "\n")
              end
            end
            self:save()
            self:updateKeyValues()
          end,
        },
        {
          text = _("Save"),
          callback = function()
            local fields = alias_input:getFields()
            local name = fields[1] and util.trim(fields[1])
            local value = fields[2] and util.trim(fields[2])
            if name ~= "" and value ~= "" then
              UIManager:close(alias_input)
              for i, v in pairs(self.kv_pairs) do
                if v[1] == alias_name then
                  table.remove(self.kv_pairs, i)
                  self.parent:transmit("unalias " .. alias_name .. "\n")
                end
              end
              self.parent:transmit("alias " .. name .. "='" .. value .. "'\n")
              table.insert(self.kv_pairs, {
                name,
                value,
                callback = function()
                  self.editAlias(self, name, value)
                end,
              })
              table.remove(self.kv_pairs, 2)
              table.remove(self.kv_pairs, 1)
              table.sort(self.kv_pairs, function(a, b)
                return a[1] < b[1]
              end)
              table.insert(self.kv_pairs, 1, {
                _("Create a new alias"),
                "",
                callback = function()
                  self:editAlias(self, "", "")
                end,
              })
              table.insert(self.kv_pairs, 2, "---")
              self:save()
              self:updateKeyValues()
            end
          end,
        },
        {
          text = _("Execute"),
          callback = function()
            local fields = alias_input:getFields()
            local value = fields[2] and util.trim(fields[2])
            if value ~= "" then
              UIManager:close(alias_input)
              self.alias_kv:onClose()
              self.parent:transmit(value .. "\n")
            end
          end,
        },
      },
    },
  })
  UIManager:show(alias_input)
  alias_input:onShowKeyboard()
end

return Aliases
