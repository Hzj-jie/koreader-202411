--[[--
A simple serialization function which won't do uservalues, functions, or loops.

If you need a more full-featured variant, serpent is available in ffi/serpent ;).
]]

local insert = table.insert
local indent_prefix = "    "

local function _serialize(what, outt, indent, max_lv, history, pairs_func)
    if not max_lv then
        max_lv = math.huge
    end

    if indent > max_lv then
        return
    end

    local datatype = type(what)
    if datatype == "table" then
        history = history or {}
        for up, item in ipairs(history) do
            if item == what then
                insert(outt, "nil --[[ LOOP:\n")
                insert(outt, string.rep(indent_prefix, indent - up))
                insert(outt, "^------- ]]")
                return
            end
        end
        local new_history = { what, unpack(history) }
        local didrun = false
        insert(outt, "{")
        for k, v in pairs_func(what) do
            insert(outt, "\n")
            insert(outt, string.rep(indent_prefix, indent+1))
            insert(outt, "[")
            _serialize(k, outt, indent+1, max_lv, new_history, pairs_func)
            insert(outt, "] = ")
            _serialize(v, outt, indent+1, max_lv, new_history, pairs_func)
            insert(outt, ",")
            didrun = true
        end
        if didrun then
            insert(outt, "\n")
            insert(outt, string.rep(indent_prefix, indent))
        end
        insert(outt, "}")
    elseif datatype == "string" then
        insert(outt, string.format("%q", what))
    elseif datatype == "number" then
        insert(outt, tostring(what))
    elseif datatype == "boolean" then
        insert(outt, tostring(what))
    elseif datatype == "function" then
        insert(outt, tostring(what))
    elseif datatype == "nil" then
        insert(outt, "nil")
    end
end

local function dumpex(data, max_lv, pairs_func)
    local out = {}
    _serialize(data, out, 0, max_lv, nil, pairs_func)
    return table.concat(out)
end

return dumpex
