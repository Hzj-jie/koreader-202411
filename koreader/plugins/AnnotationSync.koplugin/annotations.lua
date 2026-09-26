local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local gettext = require("gettext")
local json = require("json")
local logger = require("logger")
local sort = require("sort")
local util = require("util")
local utils = require("plugins/AnnotationSync.koplugin/utils")

local natsort = sort.natsort_cmp()

local function natcmp(a, b)
  if a == b then
    return 0
  end
  local is_before = natsort(a, b)
  return is_before and 1 or -1
end

local function has_valid_coords(pos)
  return type(pos) == "table"
    and type(pos.x) == "number"
    and type(pos.y) == "number"
end

local function has_valid_page(ann)
  local page = ann.page
    or (type(ann.pos0) == "table" and ann.pos0.page)
    or (type(ann.pos0) == "string" and ann.pos0)
  return type(page) == "number" or (type(page) == "string" and page ~= "")
end

local M = {}

local function to_annotations_array(raw_data)
  if type(raw_data) ~= "table" then
    return {}
  end
  local valid = {}
  for _, v in pairs(raw_data) do
    if M.is_valid(v) then
      table.insert(valid, v)
    end
  end
  return M.sort(valid)
end

-- Main orchestration for merging local and remote annotations
function M.sync_callback(
  document,
  local_file,
  last_sync_file,
  income_file,
  force
)
  logger.dbg("AnnotationSync:sync_callback: local_file:", local_file)
  logger.dbg("AnnotationSync:sync_callback: last_sync_file:", last_sync_file)
  logger.dbg("AnnotationSync:sync_callback: income_file:", income_file)

  local local_raw = utils.read_json(local_file)
  local last_sync_raw = utils.read_json(last_sync_file)
  local income_raw = utils.read_json(income_file)

  local is_likely_404 = false
  if not local_raw or not last_sync_raw then
    logger.warn(
      "AnnotationSync: Failed to load local sync files. Aborting to prevent data loss."
    )
    if force then
      UIManager:show(InfoMessage:new({
        text = gettext(
          "AnnotationSync: Failed to load local sync files. Sync aborted."
        ),
        timeout = 3,
      }))
    end
    return false
  end

  local local_list = to_annotations_array(local_raw)
  local last_sync_list = to_annotations_array(last_sync_raw)
  local income_list = nil

  if income_raw then
    local had_entries = next(income_raw) ~= nil
    local filtered = to_annotations_array(income_raw)
    if had_entries and #filtered == 0 then
      logger.warn(
        "AnnotationSync: income_file contains no valid annotations. Aborting."
      )
      income_raw = nil
    else
      income_list = filtered
    end
  end

  if not income_raw then
    -- If income_file is not a valid JSON table, it might be a 404 error page from WebDAV (first sync)
    -- We only assume empty state if it's NOT valid JSON at all and looks like a 404 error body.
    local content_snippet = ""
    local f = income_file and io.open(income_file, "r")
    if f then
      local content = f:read(1024)
      f:close()
      content_snippet = content and content:sub(1, 100):gsub("%s+", " ") or ""
      local ok_json, data = pcall(json.decode, content)
      if not ok_json then
        -- Not valid JSON. Check for explicit 404/Not Found markers.
        if content then
          local lower_content = content:lower()
          if
            lower_content:find("404")
            or lower_content:find("not found")
            or lower_content:find("notfound")
            or lower_content:find("could not be located")
          then
            is_likely_404 = true
          end
        end
      elseif
        type(data) == "table"
        and data.error_summary
        and data.error_summary:find("path/not_found")
      then
        -- Dropbox error: path not found (new book)
        is_likely_404 = true
      end
    else
      -- File doesn't exist at all (SyncService handles this, but just in case)
      is_likely_404 = true
    end

    if is_likely_404 then
      logger.info(
        "AnnotationSync: income_file invalid/text, assuming empty remote state (likely 404)."
      )
      income_list = {}
    else
      logger.warn(
        "AnnotationSync: income_file appears corrupted or server error. Aborting. Snippet:",
        content_snippet
      )
      if force then
        UIManager:show(InfoMessage:new({
          text = gettext(
            "AnnotationSync: Remote file appears corrupted or server error. Sync aborted."
          ),
          timeout = 3,
        }))
      end
      return false
    end
  end

  local merged = {}

  for _, income_v in ipairs(income_list) do
    local matched_local = nil
    for _, local_v in ipairs(local_list) do
      if M.is_same_annotation(income_v, local_v) then
        matched_local = local_v
        break
      end
    end
    if matched_local then
      if M.is_before(income_v, matched_local) then
        table.insert(merged, matched_local)
      else
        table.insert(merged, income_v)
      end
    else
      local was_in_last_sync = false
      if not (not force and #local_list == 0 and #last_sync_list > 0) then
        for _, last_v in ipairs(last_sync_list) do
          if M.is_same_annotation(income_v, last_v) then
            was_in_last_sync = true
            break
          end
        end
      end
      if was_in_last_sync then
        income_v.deleted = true
        income_v.datetime_updated = os.date("%Y-%m-%d %H:%M:%S")
        table.insert(merged, income_v)
      else
        table.insert(merged, income_v)
      end
    end
  end

  for _, local_v in ipairs(local_list) do
    local found = false
    for _, income_v in ipairs(income_list) do
      if M.is_same_annotation(local_v, income_v) then
        found = true
        break
      end
    end
    if not found then
      table.insert(merged, local_v)
    end
  end

  M.sort(merged)

  logger.dbg("AnnotationSync:sync_callback: handling merged list")
  local active_list = {}
  for _, ann in ipairs(merged) do
    if not ann.deleted then
      table.insert(active_list, ann)
    end
  end

  if is_likely_404 and #local_list == 0 then
    logger.dbg(
      "AnnotationSync: remote file does not exist and local file is empty, skipping push to server"
    )
    return false, active_list
  end

  util.writeToFile(json.encode(M.list_to_map(merged)), local_file)
  return true, active_list
end

-- Prepares the local sidecar data for syncing
function M.write_annotations_json(
  document,
  stored_annotations,
  sdr_dir,
  annotation_filename
)
  if not document or not sdr_dir then
    return false
  end
  local annotation_map = M.list_to_map(stored_annotations)
  local json_path = sdr_dir .. "/" .. annotation_filename
  if util.writeToFile(json.encode(annotation_map), json_path) then
    return json_path
  end
  return false
end

-- Sorts an array of annotations in place by position order
function M.sort(array)
  assert(type(array) == "table", "sort requires a table argument")

  local function get_page(item)
    return item.page
      or (type(item.pos0) == "table" and item.pos0.page)
      or (type(item.pos0) == "string" and item.pos0)
  end

  local function get_pos(item)
    return type(item.pos0) == "table" and item.pos0
  end

  table.sort(array, function(a, b)
    assert(
      type(a) == "table" and type(b) == "table",
      "sort requires table elements"
    )

    local page_a = get_page(a)
    local page_b = get_page(b)

    assert(
      page_a ~= nil and page_b ~= nil,
      "sort requires page or pos0 in elements"
    )

    if page_a ~= page_b then
      if type(page_a) == "number" and type(page_b) == "number" then
        return page_a < page_b
      end

      return natcmp(tostring(page_a), tostring(page_b)) > 0
    end

    -- Same page: compare sub-page position / coordinates
    local pos_a = get_pos(a)
    local pos_b = get_pos(b)

    local has_coords_a = has_valid_coords(pos_a)
    local has_coords_b = has_valid_coords(pos_b)

    if not has_coords_a and has_coords_b then
      -- Bookmark on same page is strictly ordered before highlight
      return true
    elseif has_coords_a and not has_coords_b then
      return false
    elseif has_coords_a and has_coords_b then
      if pos_a.y and pos_b.y and pos_a.y ~= pos_b.y then
        return pos_a.y < pos_b.y
      end
      if pos_a.x and pos_b.x and pos_a.x ~= pos_b.x then
        return pos_a.x < pos_b.x
      end
      return false
    end

    -- Same page: rolling XPointers within the page
    if type(a.pos0) == "string" and type(b.pos0) == "string" then
      return natcmp(a.pos0, b.pos0) > 0
    end

    return false
  end)

  return array
end

function M.list_to_map(annotations)
  local map = {}
  if type(annotations) == "table" then
    for __, ann in ipairs(annotations) do
      local key = M.annotation_key(ann)
      if type(key) == "string" then
        map[key] = ann
      end
    end
  end
  return map
end

function M.map_to_list(map)
  local list = {}
  if type(map) == "table" then
    for __, ann in pairs(map) do
      if ann and not ann.deleted then
        if M.is_annotation(ann) or M.is_bookmark(ann) then
          table.insert(list, ann)
        end
      end
    end
    return M.sort(list)
  end
  return list
end

-- Generates a unique key based on geometry or page
function M.annotation_key(annotation)
  if M.is_annotation(annotation) then
    local p0, p1
    if type(annotation.pos0) == "table" then
      local zoom = annotation.pos0.zoom or 1
      local page = annotation.page or annotation.pos0.page or 0
      p0 = string.format(
        "%d|%d|%d",
        page,
        math.floor(annotation.pos0.x / zoom),
        math.floor(annotation.pos0.y / zoom)
      )
      p1 = string.format(
        "%d|%d",
        math.floor(annotation.pos1.x / zoom),
        math.floor(annotation.pos1.y / zoom)
      )
    else
      p0 = annotation.pos0
      p1 = annotation.pos1
    end
    return p0 .. "||" .. p1
  elseif M.is_bookmark(annotation) then
    return "BOOKMARK|" .. tostring(annotation.page)
  end
end

function M.is_bookmark(candidate)
  if type(candidate) ~= "table" or not has_valid_page(candidate) then
    return false
  end
  return candidate.pos0 == nil and candidate.pos1 == nil
end

function M.is_annotation(candidate)
  if type(candidate) ~= "table" or not has_valid_page(candidate) then
    return false
  end
  if not candidate.pos0 or not candidate.pos1 then
    return false
  end

  if has_valid_coords(candidate.pos0) and has_valid_coords(candidate.pos1) then
    return true
  end

  if type(candidate.pos0) == "string" and type(candidate.pos1) == "string" then
    return candidate.pos0 ~= "" and candidate.pos1 ~= ""
  end

  return false
end

function M.is_valid(candidate)
  return M.is_annotation(candidate) or M.is_bookmark(candidate)
end

function M.filter_valid_annotations(map, map_name)
  if type(map) ~= "table" then
    return {}
  end
  local valid = {}
  for k, v in pairs(map) do
    if M.is_valid(v) then
      valid[k] = v
    else
      logger.warn(
        "AnnotationSync: dropping invalid entry in",
        map_name or "map",
        "key:",
        tostring(k)
      )
    end
  end
  return valid
end

function M.is_before(a, b)
  local a_time = a.datetime_updated or a.datetime or ""
  local b_time = b.datetime_updated or b.datetime or ""
  return a_time <= b_time
end

function M.sort_keys_by_position(t)
  local items = {}
  for k, v in pairs(t) do
    table.insert(items, { key = k, page = v.page, pos0 = v.pos0, pos1 = v.pos1 })
  end
  M.sort(items)
  local keys = {}
  for _, item in ipairs(items) do
    table.insert(keys, item.key)
  end
  return keys
end

function M.is_same_annotation(a, b)
  if not a or not b then
    return false
  end

  local function get_page(item)
    return item.page
      or (type(item.pos0) == "table" and item.pos0.page)
      or (type(item.pos0) == "string" and item.pos0)
  end

  local function is_bm(item)
    return item.pos0 == nil and item.pos1 == nil
  end

  local function norm_coord(pos, coord)
    local zoom = pos.zoom or 1
    return math.floor(pos[coord] / zoom)
  end

  local function same_coords(p1, p2)
    return norm_coord(p1, "x") == norm_coord(p2, "x")
      and norm_coord(p1, "y") == norm_coord(p2, "y")
  end

  if get_page(a) ~= get_page(b) then
    return false
  end

  local a_is_bm = is_bm(a)
  local b_is_bm = is_bm(b)
  if a_is_bm ~= b_is_bm then
    return false
  end
  if a_is_bm then
    return true
  end

  -- Rolling XPointers (EPUB)
  if type(a.pos0) == "string" and type(b.pos0) == "string" then
    return a.pos0 == b.pos0 and a.pos1 == b.pos1
  end

  -- Paging coordinates (PDF)
  if
    type(a.pos0) == "table"
    and type(b.pos0) == "table"
    and type(a.pos1) == "table"
    and type(b.pos1) == "table"
  then
    return same_coords(a.pos0, b.pos0) and same_coords(a.pos1, b.pos1)
  end

  return false
end

function M.positions_intersect(a, b, _document)
  return M.is_same_annotation(a, b)
end

return M
