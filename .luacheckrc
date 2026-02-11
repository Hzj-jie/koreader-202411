std = "luajit"
codes = true
cache = false
quiet = 1
globals = {
  "G_defaults",
  "G_named_settings",
  "G_reader_settings",
  "math.e",
  "math.finite",
  "table.pack",
  "table.unpack",
}
-- TODO: Remove in favor of default 80, stylua doesn't work very well and
-- sometimes leaves the line longer than the 80.
max_line_length = 1000
max_string_line_length = 1000
-- TODO: Should reduce, stylua doesn't format comment.
max_comment_line_length = 1000
ignore = {
  "211/__", -- unused variable __: avoid conflicting with _
  "212/arg", -- unused argument arg: commonly used by event handlers.
  "212/self", -- unused argument self
  "212/__", -- unused argument __: avoid conflicting with _
  "213", -- unused loop variable
  "231/__", -- variable __ is never accessed: avoid conflicting with _
  "411/__", -- variable __ was previously defined: avoid conflicting with _
  "412/__", -- variable __ was previously defined as an argument: avoid conflicting with _
  "413/__", -- variable __ was previously defined as a loop variable: avoid conflicting with _
  "421/__", -- shadowing definition of variable __: avoid conflicting with _
  "423/__", -- shadowing definition of loop variable __: avoid conflicting with _
  "431/__", -- shadowing upvalue __: avoid conflicting with _
  "432/self", -- shadowing upvalue argument self: allow self being reused.
  -- TODO: Remove
  "212", -- unused argument
}
