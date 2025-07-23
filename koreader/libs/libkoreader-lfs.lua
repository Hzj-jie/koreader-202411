local ok, koreader_lfs = pcall(package.loadlib, "libs/libkoreader-lfs.so", "luaopen_lfs")
if ok and koreader_lfs ~= nil then
  print("libkoreader-lfs.so is used")
  return koreader_lfs()
end
print("lfs.so is used")
return package.loadlib("libs/lfs.so", "luaopen_lfs")()
