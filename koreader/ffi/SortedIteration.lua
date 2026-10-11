-- Copied from http://lua-users.org/wiki/SortedIteration with local changes
-- originally in
-- https://github.com/Hzj-jie/koreader-202411/pull/24/commits/73f599d6245ac59ad3a8a43cd4ac3a7c90ee0660#diff-a39fa30a6e29a0ba309eb22400e11ec6dbef5897573e89d5537a42b7c73f0101
-- Other minor changes include format improvements and comments.

--[[
Ordered table iterator, allow to iterate on the natural order of the keys of a
table.

Example:
]]

local function __genOrderedIndex(t)
  local orderedIndex = {}
  for key in pairs(t) do
    table.insert(orderedIndex, key)
  end
  table.sort(orderedIndex, function(v1, v2)
    if type(v1) == type(v2) then
      -- Assumes said type supports the < comparison operator
      return v1 < v2
    end
    -- Handle type mismatches by squashing to string
    return tostring(v1) < tostring(v2)
  end)
  return orderedIndex
end

local function orderedPairs(t)
  local orderedIndex = __genOrderedIndex(t)
  local indices = {}
  for i = 1, #orderedIndex do
    indices[orderedIndex[i]] = i
  end

  local function orderedNext(_, state)
    local i = (state == nil and 0 or (indices[state] or 0)) + 1
    local key = orderedIndex[i]
    if key ~= nil then
      return key, t[key]
    end
  end

  return orderedNext, t, nil
end

return orderedPairs
