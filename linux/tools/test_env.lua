-- Shared test environment utility for KOReader tests
local M = {}

function M.detect_visual_output()
  -- Detect if a real active display screen is available
  local is_ssh = (os.getenv("SSH_CLIENT") ~= nil)
    or (os.getenv("SSH_TTY") ~= nil)
    or (os.getenv("SSH_CONNECTION") ~= nil)

  local has_screen = false
  if os.getenv("DISPLAY") and not is_ssh then
    local ok = os.execute("xset -q >/dev/null 2>&1")
    if ok == 0 or ok == true then
      has_screen = true
    end
  end

  return has_screen
end

return M
