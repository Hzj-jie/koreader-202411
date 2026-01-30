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
-- TODO: Remove in favor of default 120, stylua doesn't work very well and
-- sometimes leaves the line longer than the 120
max_line_length = 1000
max_string_line_length = 1000
-- TODO: Should reduce, stylua doesn't format comment.
max_comment_line_length = 1000
-- TODO: Remove
unused = false
-- TODO: Remove
ignore = {
  "432/self", --shadowing upvalue argument self, allow self being reused.
}
