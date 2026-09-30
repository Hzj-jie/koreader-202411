local WidgetContainer = require("ui/widget/container/widgetcontainer")
local gettext = require("gettext")
local logger = require("logger")
local T = require("ffi/util").template

local ReaderAnnotation = WidgetContainer:extend({
  annotations = nil, -- array sorted by annotation position order, ascending
})

-- build, read, save

local function getPageRef(ui, pn_or_xp, pn)
  -- same as ReaderBookmark:getBookmarkPageString(page)
  -- but gets pn (page number already calculated in the caller)
  -- and returns nil if there are no reference pages and hidden flows
  if not ui then
    return
  end
  if ui.pagemap and ui.pagemap:wantsPageLabels() then
    return ui.pagemap:getXPointerPageLabel(pn_or_xp, true)
  end
  local document = ui.document
  if document and document:hasHiddenFlows() then
    local page = document:getPageNumberInFlow(pn)
    local flow = document:getPageFlow(pn)
    if flow > 0 then
      return T("[%1]%2", page, flow)
    end
    return tostring(page)
  end
end

local function getHighlightForBookmark(highlights, bookmark)
  if not bookmark.highlighted then
    return
  end -- page bookmark
  -- Legacy entries: the bookmark marks a highlight with `highlighted`
  -- instead of `drawer`, and the highlight's page is its key in `highlights`.
  local bm = {
    datetime = bookmark.datetime,
    drawer = true,
    page = bookmark.page,
    pos0 = bookmark.pos0,
    pos1 = bookmark.pos1,
  }
  for pageno, page_highlights in pairs(highlights) do
    for _, highlight in ipairs(page_highlights) do
      local hl = {
        datetime = highlight.datetime,
        drawer = true,
        page = type(highlight.pos0) == "string" and highlight.pos0
          or tonumber(pageno)
          or pageno,
        pos0 = highlight.pos0,
        pos1 = highlight.pos1,
      }
      if ReaderAnnotation.doesMatch(hl, bm) then
        return highlight, pageno
      end
    end
  end
end

local function buildAnnotation(bm, highlights, ui)
  -- bm: associated single bookmark ; highlights: tables with all highlights
  local note = bm.text
  if note == "" then
    note = nil
  end
  local chapter = bm.chapter
  local hl, pageno = getHighlightForBookmark(highlights, bm)
  local pageref
  if ui then
    if note and ui.bookmark and ui.bookmark:isBookmarkAutoText(bm) then
      note = nil
    end
    if chapter == nil and ui.toc then
      chapter = ui.toc:getTocTitleByPage(bm.page)
    end
    if ui.document then
      pageno = ui.rolling and ui.document:getPageFromXPointer(bm.page)
        or bm.page
      pageref = getPageRef(ui, bm.page, pageno)
    end
  end
  if type(bm.pos0) == "table" and not bm.pos0.page then
    -- old single-page reflow highlights do not have page in position
    bm.pos0.page = bm.page
    bm.pos1.page = bm.page
  end
  if hl == nil then -- page bookmark or orphaned bookmark
    hl = {}
    if bm.highlighted then -- orphaned bookmark
      hl.drawer = ui
          and ui.view
          and ui.view.highlight
          and ui.view.highlight.saved_drawer
        or "lighten"
      hl.color = ui
          and ui.view
          and ui.view.highlight
          and ui.view.highlight.saved_color
        or "yellow"
      if ui and ui.paging and ui.document and type(bm.pos0) == "table" then
        if bm.pos0.page == bm.pos1.page then
          hl.pboxes =
            ui.document:getPageBoxesFromPositions(bm.page, bm.pos0, bm.pos1)
        else -- multi-page highlight, restore the first box only
          hl.pboxes =
            ui.document:getPageBoxesFromPositions(bm.page, bm.pos0, bm.pos0)
        end
      end
    end
  end
  return { -- annotation
    datetime = bm.datetime, -- creation time, not changeable
    datetime_updated = bm.datetime_updated, -- modification time, nil if not modified
    drawer = hl.drawer, -- highlight drawer
    color = hl.color, -- highlight color
    text = bm.notes, -- highlighted text, editable
    text_edited = hl.edited, -- true if highlighted text has been edited
    note = note, -- user's note, editable
    chapter = chapter, -- book chapter title
    pageno = pageno, -- book page number (continuous numbering, used by KOHighlights)
    pageref = pageref, -- book page number (iff: reference pages or hidden flows)
    page = bm.page, -- highlight location, xPointer or number (pdf)
    pos0 = bm.pos0, -- highlight start position, xPointer (== page) or table (pdf)
    pos1 = bm.pos1, -- highlight end position, xPointer or table (pdf)
    pboxes = hl.pboxes, -- pdf pboxes, used only and changeable by addMarkupAnnotation
    ext = hl.ext, -- pdf multi-page highlight
  }
end

local function getAnnotationsFromBookmarksHighlights(bookmarks, highlights, ui)
  local annotations = {}
  for i = #bookmarks, 1, -1 do
    table.insert(annotations, buildAnnotation(bookmarks[i], highlights, ui))
  end
  return annotations
end

local function isRolling(config, ui, items)
  if type(ui) == "table" then
    if ui.rolling then
      return true
    elseif ui.paging then
      return false
    end
  end
  if config and config.doc_path then
    local DocumentRegistry = require("document/documentregistry")
    local provider = DocumentRegistry:getProvider(config.doc_path)
    if provider then
      return provider.provider == "crengine"
    end
  end
  if items then
    for _, item in ipairs(items) do
      if type(item) == "table" then
        if type(item.page) == "string" then
          return true
        elseif type(item.page) == "number" then
          return false
        end
      end
    end
  end
  return false
end

local function migrateToAnnotations(config, ui)
  local bookmarks = config:readTable("bookmarks") or {}
  local highlights = config:readTable("highlight") or {}

  local rolling = isRolling(config, ui, bookmarks)

  if config:hasNot("highlights_imported") then
    -- before 2014, saved highlights were not added to bookmarks when they were created.
    for page, hls in pairs(highlights) do
      for _, hl in ipairs(hls) do
        local hl_page = (rolling == false) and page or hl.pos0
        -- highlights saved by some old versions don't have pos0 field
        -- we just ignore those highlights
        if hl_page then
          local item = {
            datetime = hl.datetime,
            highlighted = true,
            notes = hl.text,
            page = hl_page,
            pos0 = hl.pos0,
            pos1 = hl.pos1,
          }
          if rolling == false and type(item.pos0) == "table" then
            item.pos0.page = page
            item.pos1.page = page
          end
          table.insert(bookmarks, item)
        end
      end
    end
    config:save("highlights_imported", true)
  end

  -- Bookmarks/highlights formats in crengine and mupdf are incompatible.
  local has_bookmarks = #bookmarks > 0
  local bookmarks_rolling = isRolling(nil, nil, bookmarks)

  if rolling then
    if has_bookmarks and bookmarks_rolling then -- compatible format loaded, check for incompatible old backup
      if config:has("bookmarks_paging") then -- save incompatible old backup
        local bookmarks_paging = config:readTable("bookmarks_paging") or {}
        local highlights_paging = config:readTable("highlight_paging") or {}
        local annotations_paging = getAnnotationsFromBookmarksHighlights(
          bookmarks_paging,
          highlights_paging
        )
        config:save("annotations_paging", annotations_paging)
        config:delete("bookmarks_paging")
        config:delete("highlight_paging")
      end
    else -- incompatible format loaded, or empty
      if has_bookmarks then -- save incompatible format if not empty
        local annotations_paging =
          getAnnotationsFromBookmarksHighlights(bookmarks, highlights)
        config:save("annotations_paging", annotations_paging)
      end
      -- load compatible format
      bookmarks = config:readTableRef("bookmarks_rolling")
      highlights = config:readTableRef("highlight_rolling")
      config:delete("bookmarks_rolling")
      config:delete("highlight_rolling")
    end
  else -- paging (rolling == false)
    if has_bookmarks and not bookmarks_rolling then
      if config:has("bookmarks_rolling") then
        local saved_bookmarks_rolling = config:readTable("bookmarks_rolling") or {}
        local highlights_rolling = config:readTable("highlight_rolling") or {}
        local annotations_rolling = getAnnotationsFromBookmarksHighlights(
          saved_bookmarks_rolling,
          highlights_rolling
        )
        config:save("annotations_rolling", annotations_rolling)
        config:delete("bookmarks_rolling")
        config:delete("highlight_rolling")
      end
    else
      if has_bookmarks then
        local annotations_rolling =
          getAnnotationsFromBookmarksHighlights(bookmarks, highlights)
        config:save("annotations_rolling", annotations_rolling)
      end
      bookmarks = config:readTableRef("bookmarks_paging")
      highlights = config:readTableRef("highlight_paging")
      config:delete("bookmarks_paging")
      config:delete("highlight_paging")
    end
  end

  local annotations =
    getAnnotationsFromBookmarksHighlights(bookmarks, highlights, ui)
  -- has("annotations") is meaningful to indicate the finish of migration.
  config:save("annotations", annotations)
  config:save("annotations_externally_modified", true)
  return annotations
end

function ReaderAnnotation:onReadSettings(config)
  if self.ui.rolling and config:hasNot("annotations") then
    self.annotations = {}
    -- During ReaderUI initialization, ReadSettings is broadcast before
    -- loadDocument renders pages and builds ui.toc. For rolling documents
    -- (crengine), legacy migration needs ui.document:getPageFromXPointer
    -- and ui.toc to resolve pages and chapters; querying an unrendered
    -- document causes crengine to crash/segfault. Defer migration until
    -- onReaderInited when document and TOC are fully ready.
    self.onReaderInited = function()
      self.annotations = ReaderAnnotation.loadFromSettings(config, self.ui)
    end
  else
    self.annotations = ReaderAnnotation.loadFromSettings(config, self.ui)
  end
  self.onPostReaderReady = function()
    if config:isTrue("annotations_externally_modified") then
      self:updateAnnotations(true, true)
      config:delete("annotations_externally_modified")
    end
  end
end

function ReaderAnnotation:setNeedsUpdateFlag()
  self.needs_update = true
end

ReaderAnnotation.onDocumentRerendered = ReaderAnnotation.setNeedsUpdateFlag

function ReaderAnnotation:onCloseDocument()
  self:updatePageNumbers()
end

function ReaderAnnotation:onSaveSettings()
  self:updatePageNumbers()
end

-- items handling

function ReaderAnnotation:updatePageNumbers(force_update)
  if force_update or self.needs_update then
    for _, item in ipairs(self.annotations) do
      item.pageno = self.ui.rolling
          and self.document:getPageFromXPointer(item.page)
        or item.page
      item.pageref = self:getPageRef(item.page, item.pageno)
    end
  end
  self.needs_update = nil
end

function ReaderAnnotation:sortItems(items)
  if #items > 1 then
    local sort_func = self.ui.rolling
        and function(a, b)
          return self:isItemInPositionOrderRolling(a, b)
        end
      or function(a, b)
        return self:isItemInPositionOrderPaging(a, b)
      end
    table.sort(items, sort_func)
  end
end

function ReaderAnnotation:updateAnnotations(needs_update, needs_sort)
  if needs_update then
    self.needs_update = true
    self:updatePageNumbers()
    needs_sort = true
  end
  if needs_sort then
    self:sortItems(self.annotations)
  end
end

function ReaderAnnotation:updateItemByXPointer(item)
  -- called by ReaderRolling:checkXPointersAndProposeDOMVersionUpgrade()
  local chapter = self.ui.toc:getTocTitleByPage(item.page)
  if chapter == "" then
    chapter = nil
  end
  if not item.drawer then -- page bookmark
    item.text = chapter and T(gettext("in %1"), chapter) or nil
  end
  item.chapter = chapter
  item.pageno = self.document:getPageFromXPointer(item.page)
  item.pageref = self:getPageRef(item.page, item.pageno)
end

function ReaderAnnotation:isItemInPositionOrderRolling(a, b)
  local a_page = self.document:getPageFromXPointer(a.page)
  local b_page = self.document:getPageFromXPointer(b.page)
  if a_page ~= b_page then
    return a_page < b_page
  end
  -- both items in the same page
  if a.drawer ~= b.drawer then -- comparing a page bookmark and a highlight
    return not a.drawer -- have page bookmarks before highlights
  end
  local compare_xp = self.document:compareXPointers(a.page, b.page)
  if not compare_xp then
    -- if compare_xp is nil, some xpointer is invalid. Fallback to compare
    -- xpointer raw strings to avoid crashing table.sort.
    logger.warn("Invalid start xpointer in highlight:", a.page, b.page)
    return a.page < b.page
  end
  if not a.drawer or compare_xp ~= 0 then
    -- Note, compareXPointers compares b.page to a.page, so the result
    -- needs to be reversed.
    return compare_xp > 0
  end
  -- both highlights with the same start, compare ends
  compare_xp = self.document:compareXPointers(a.pos1, b.pos1)
  if compare_xp then
    return compare_xp > 0
  end
  logger.warn("Invalid end xpointer in highlight:", a.pos1, b.pos1)
  return a.pos1 < b.pos1
end

function ReaderAnnotation:isItemInPositionOrderPaging(a, b)
  if a.page == b.page then -- both items in the same page
    if a.drawer and b.drawer then -- both items are highlights, compare positions
      local is_reflow = self.document.configurable.text_wrap -- save reflow mode
      self.document.configurable.text_wrap = 0 -- native positions
      -- sort start and end positions of each highlight
      local a_start, a_end, b_start, b_end, result
      if self.document:comparePositions(a.pos0, a.pos1) > 0 then
        a_start, a_end = a.pos0, a.pos1
      else
        a_start, a_end = a.pos1, a.pos0
      end
      if self.document:comparePositions(b.pos0, b.pos1) > 0 then
        b_start, b_end = b.pos0, b.pos1
      else
        b_start, b_end = b.pos1, b.pos0
      end
      -- compare start positions
      local compare_pos = self.document:comparePositions(a_start, b_start)
      if compare_pos == 0 then -- both highlights with the same start, compare ends
        result = self.document:comparePositions(a_end, b_end) > 0
      else
        result = compare_pos > 0
      end
      self.document.configurable.text_wrap = is_reflow -- restore reflow mode
      return result
    end
    return not a.drawer -- have page bookmarks before highlights
  end
  return a.page < b.page
end

function ReaderAnnotation.doesMatch(a, b)
  if
    (a.datetime ~= nil and b.datetime ~= nil and a.datetime ~= b.datetime)
    or (not a.drawer) ~= not b.drawer
    or a.page ~= b.page
  then
    return false
  end
  if type(a.pos0) == "table" then
    return a.pos0.x == b.pos0.x
      and a.pos0.y == b.pos0.y
      and a.pos1.x == b.pos1.x
      and a.pos1.y == b.pos1.y
  end
  return a.pos1 == b.pos1
end

function ReaderAnnotation.isValidItem(item)
  if type(item) ~= "table" then
    return false
  end
  local page_type = type(item.page)
  if page_type ~= "number" and (page_type ~= "string" or item.page == "") then
    return false
  end
  if
    item.datetime ~= nil
    and (type(item.datetime) ~= "string" or item.datetime == "")
  then
    return false
  end
  if
    item.datetime_updated ~= nil
    and (type(item.datetime_updated) ~= "string" or item.datetime_updated == "")
  then
    return false
  end
  if not item.drawer then
    return item.pos0 == nil and item.pos1 == nil
  end
  if not item.pos0 or not item.pos1 then
    return false
  end
  if page_type == "number" then
    return type(item.pos0) == "table"
      and type(item.pos1) == "table"
      and type(item.pos0.x) == "number"
      and type(item.pos0.y) == "number"
      and type(item.pos1.x) == "number"
      and type(item.pos1.y) == "number"
  else
    return type(item.pos0) == "string"
      and item.pos0 ~= ""
      and type(item.pos1) == "string"
      and item.pos1 ~= ""
  end
end

function ReaderAnnotation.markUpdated(annotation)
  annotation.datetime_updated = os.date("%Y-%m-%d %H:%M:%S")
  return annotation
end

function ReaderAnnotation.loadFromSettings(config, ui)
  local is_rolling
  local annotations
  if config:has("annotations") then
    annotations = config:readTable("annotations") or {}
    local has_annotations = #annotations > 0
    local annotations_rolling = isRolling(nil, nil, annotations)
    is_rolling = isRolling(config, ui, annotations)

    if is_rolling then
      if
        (has_annotations and not annotations_rolling)
        or (not has_annotations and config:has("annotations_rolling"))
      then
        if has_annotations then
          config:save("annotations_paging", annotations)
        end
        annotations = config:readTable("annotations_rolling") or {}
        config:delete("annotations_rolling")
        config:save("annotations", annotations)
        config:save("annotations_externally_modified", true)
      end
    else
      if
        (has_annotations and annotations_rolling)
        or (not has_annotations and config:has("annotations_paging"))
      then
        if has_annotations then
          config:save("annotations_rolling", annotations)
        end
        annotations = config:readTable("annotations_paging") or {}
        config:delete("annotations_paging")
        config:save("annotations", annotations)
        config:save("annotations_externally_modified", true)
      end
    end
  else
    annotations = migrateToAnnotations(config, ui)
    is_rolling = isRolling(config, ui, annotations)
  end

  local valid_annotations = {}
  local invalid_annotations = nil
  for _, item in ipairs(annotations) do
    local is_valid = ReaderAnnotation.isValidItem(item)
    if is_valid then
      if is_rolling and type(item.page) ~= "string" then
        is_valid = false
      elseif not is_rolling and type(item.page) ~= "number" then
        is_valid = false
      end
    end
    if is_valid then
      table.insert(valid_annotations, item)
    else
      if not invalid_annotations then
        invalid_annotations = config:readTable("annotations_invalid") or {}
      end
      table.insert(invalid_annotations, item)
    end
  end

  if invalid_annotations then
    logger.warn(
      "ReaderAnnotation.loadFromSettings: quarantined invalid annotations:",
      #invalid_annotations
    )
    config:save("annotations_invalid", invalid_annotations)
    config:save("annotations", valid_annotations)
    config:save("annotations_externally_modified", true)
    annotations = valid_annotations
  end

  return annotations
end

function ReaderAnnotation:getItemIndex(item, no_binary)
  if not no_binary then
    local isInOrder = self.ui.rolling and self.isItemInPositionOrderRolling
      or self.isItemInPositionOrderPaging
    local _start, _end, _middle = 1, #self.annotations
    while _start <= _end do
      _middle = bit.rshift(_start + _end, 1)
      local v = self.annotations[_middle]
      if ReaderAnnotation.doesMatch(item, v) then
        return _middle
      elseif isInOrder(self, item, v) then
        _end = _middle - 1
      else
        _start = _middle + 1
      end
    end
  end

  for i, v in ipairs(self.annotations) do
    if ReaderAnnotation.doesMatch(item, v) then
      return i
    end
  end
end

function ReaderAnnotation:getInsertionIndex(item)
  local isInOrder = self.ui.rolling and self.isItemInPositionOrderRolling
    or self.isItemInPositionOrderPaging
  local _start, _end, _middle, direction = 1, #self.annotations, 1, 0
  while _start <= _end do
    _middle = bit.rshift(_start + _end, 1)
    if isInOrder(self, item, self.annotations[_middle]) then
      _end, direction = _middle - 1, 0
    else
      _start, direction = _middle + 1, 1
    end
  end
  return _middle + direction
end

function ReaderAnnotation:addItem(item)
  item.datetime = os.date("%Y-%m-%d %H:%M:%S")
  item.datetime_updated = nil
  item.pageno = self.ui.rolling and self.document:getPageFromXPointer(item.page)
    or item.page
  item.pageref = self:getPageRef(item.page, item.pageno)
  local index = self:getInsertionIndex(item)
  table.insert(self.annotations, index, item)
  return index
end

-- info

function ReaderAnnotation:getPageRef(pn_or_xp, pn)
  return getPageRef(self.ui, pn_or_xp, pn)
end

function ReaderAnnotation:hasAnnotations()
  return #self.annotations > 0
end

function ReaderAnnotation:getNumberOfAnnotations()
  return #self.annotations
end

function ReaderAnnotation:getNumberOfHighlightsAndNotes() -- for Statistics plugin
  local highlights = 0
  local notes = 0
  for _, item in ipairs(self.annotations) do
    if item.drawer then
      if item.note then
        notes = notes + 1
      else
        highlights = highlights + 1
      end
    end
  end
  return highlights, notes
end

return ReaderAnnotation
