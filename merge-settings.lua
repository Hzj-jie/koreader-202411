local local_file = dofile("settings.reader.lua")
local device_file = dofile("/tmp/settings.reader.lua")

local_file["kosync"]["custom_server"] = device_file["kosync"]["custom_server"]
local_file["kosync"]["userkey"] = device_file["kosync"]["userkey"]
local_file["kosync"]["username"] = device_file["kosync"]["username"]
local_file["last_migration_date"] = device_file["last_migration_date"]
local_file["lastdir"] = device_file["lastdir"]
local_file["lastfile"] = device_file["lastfile"]
table.sort(local_file)

local file, _  = io.open("/tmp/settings.reader.new.lua", "wb")
assert(file)
package.path = "koreader/?.lua;" .. package.path
local dump = require("frontend/dump")
file:write(table.concat({"-- ./settings.reader.lua\nreturn ", dump(local_file, nil, true), "\n"}))
