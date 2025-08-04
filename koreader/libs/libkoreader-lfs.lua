local ok, koreader_lfs = pcall(package.loadlib, "libs/libkoreader-lfs.so", "luaopen_lfs")
if ok and koreader_lfs ~= nil then
  return koreader_lfs()
end
return package.loadlib("libs/lfs.so", "luaopen_lfs")()
