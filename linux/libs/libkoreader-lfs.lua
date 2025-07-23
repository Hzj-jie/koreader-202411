ok, koreader_lfs = pcall(package.loadlib, "libs/libkoreader-lfs.so", "luaopen_lfs")
if ok then
  print("libkoreader-lfs.so is used")
  return koreader_lfs()
end
print("lfs.so is used")
return require("libs/lfs")
