local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local json = require("json")

local M = {}

function M.read_json(path)
  if not path or type(path) ~= "string" then
    return nil
  end
  local f = io.open(path, "r")
  if not f then
    -- No file, likely 404
    return nil
  end
  local content = f:read("*a")
  f:close()
  if not content or content == "" then
    -- Unexpected file, any json should at least have {} or [].
    return nil
  end

  -- json.decode can cause a panic and crash KOReader on some platforms if it
  -- tries to parse HTML, even in a `pcall()`
  if not M.isPossiblyJson(content) then
    return nil
  end
  local ok, data = pcall(json.decode, content)
  if ok and type(data) == "table" then
    if data.error_summary or (data.error and type(data.error) == "table") then
      return nil
    end
    return data
  end
  return nil
end

function M.isPossiblyJson(content)
  local first_char = content:sub(1, 1)
  return first_char == "{" or first_char == "["
end

function M.show_msg(msg)
  UIManager:show(InfoMessage:new({
    text = msg,
    timeout = 3,
  }))
end

-- A setting id is "<domain>:<path>", the path joining the setting's keys with
-- ".". "%" and "." inside a key are percent-encoded, so a key that holds a dot,
-- such as a book shortcut to a file, stays one key.
function M.join_setting_path(keys)
  local parts = {}
  for i, key in ipairs(keys) do
    parts[i] = tostring(key):gsub("[%%.]", function(c)
      return string.format("%%%02X", c:byte())
    end)
  end
  return table.concat(parts, ".")
end

function M.split_setting_path(path)
  local keys = {}
  for part in path:gmatch("[^.]+") do
    table.insert(keys, (part:gsub("%%(%x%x)", function(hex)
      return string.char(tonumber(hex, 16))
    end)))
  end
  return keys
end

function M.get_nested_value(tbl, path_str)
  if not tbl then
    return nil
  end
  local current = tbl
  for __, part in ipairs(M.split_setting_path(path_str)) do
    if type(current) ~= "table" then
      return nil
    end
    current = current[part]
  end
  return current
end

return M
