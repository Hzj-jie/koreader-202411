local gettext = require("gettext")

local formatters = {
  none = {
    formatter = "%s",
    label = gettext("None"),
  },
  bold = {
    formatter = "**%s**",
    label = gettext("Bold"),
  },
  highlight = {
    formatter = "==%s==",
    label = gettext("Highlight"),
  },
  italic = {
    formatter = "*%s*",
    label = gettext("Italic"),
  },
  bold_italic = {
    formatter = "**_%s_**",
    label = gettext("Bold italic"),
  },
  underline_markdownit = {
    formatter = "++%s++",
    label = gettext("Underline (Markdownit style, with ++)"),
  },
  underline_u_tag = {
    formatter = "<u>%s</u>",
    label = gettext("Underline (with <u></u> tags)"),
  },
  strikethrough = {
    formatter = "~~%s~~",
    label = gettext("Strikethrough"),
  },
}

local function prepareBookContent(
  book,
  formatting_options,
  highlight_formatting
)
  local tbl = {}
  local current_chapter = nil
  table.insert(tbl, "# " .. book.title)
  local author = book.author or gettext("N/A")
  table.insert(tbl, "##### " .. author:gsub("\n", ", ") .. "\n")
  for _, note in ipairs(book) do
    local entry = note[1]
    if entry.chapter ~= current_chapter then
      current_chapter = entry.chapter
      table.insert(tbl, "## " .. current_chapter)
    end
    table.insert(
      tbl,
      "### Page "
        .. entry.page
        .. " @ "
        .. os.date("%d %B %Y %I:%M:%S %p", entry.time)
    )
    if highlight_formatting then
      table.insert(
        tbl,
        string.format(
          formatters[formatting_options[entry.drawer]].formatter,
          entry.text
        )
      )
    else
      table.insert(tbl, entry.text)
    end
    if entry.note then
      table.insert(tbl, "\n---\n" .. entry.note)
    end
  end
  return tbl
end

return {
  prepareBookContent = prepareBookContent,
  formatters = formatters,
}
