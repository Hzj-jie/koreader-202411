local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local gettext = require("gettext")
local json = require("json")
local logger = require("logger")
local sort = require("sort")
local util = require("util")
local utils = require("plugins/AnnotationSync.koplugin/utils")

local natsort = sort.natsort_cmp()

local M = {}

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

  local local_map = utils.read_json(local_file)
  local last_sync_map = utils.read_json(last_sync_file)
  local income_map = utils.read_json(income_file)

  local is_likely_404 = false
  if not local_map or not last_sync_map then
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

  if income_map then
    -- Validate it's an annotation map (heuristic: values must be tables)
    -- AND for non-empty maps, at least one entry must have annotation-like keys.
    local is_valid_schema = true
    for k, v in pairs(income_map) do
      if type(v) ~= "table" then
        logger.warn(
          "AnnotationSync: income_map contains non-table value for key",
          tostring(k),
          ". Aborting."
        )
        is_valid_schema = false
        break
      end
      -- Schema check: values should have at least one of these keys
      if not (v.datetime_updated or v.datetime or v.page or v.text) then
        logger.warn(
          "AnnotationSync: income_map value for key",
          tostring(k),
          "lacks annotation metadata. Aborting."
        )
        is_valid_schema = false
        break
      end
    end
    if not is_valid_schema then
      income_map = nil
    end
  end

  if not income_map then
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
      income_map = {}
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

  -- Mark deleted annotations in local_map
  M.get_deleted_annotations(local_map, last_sync_map, document, force)
  local merged = {}

  local local_keys = M.sort_keys_by_position(local_map)
  local income_keys = M.sort_keys_by_position(income_map)
  local l = 1
  local i = 1

  logger.dbg("AnnotationSync:sync_callback: comparing income and local")
  while i <= #income_keys and l <= #local_keys do
    local income_k = income_keys[i]
    local local_k = local_keys[l]
    local income_v = income_map[income_k]
    local local_v = local_map[local_k]

    if M.positions_intersect(income_v, local_v, document) then
      if M.is_before(income_v, local_v) then
        merged[local_k] = local_v
      else
        merged[income_k] = income_v
      end
      i = i + 1
      l = l + 1
    else
      local cmp = M.compare_positions(local_v, income_v)
      if (cmp or 0) > 0 then
        merged[local_k] = local_v
        l = l + 1
      else
        merged[income_k] = income_v
        i = i + 1
      end
    end
  end

  while l <= #local_keys do
    local local_k = local_keys[l]
    local local_v = local_map[local_k]
    merged[local_k] = local_v
    l = l + 1
  end

  while i <= #income_keys do
    local income_k = income_keys[i]
    local income_v = income_map[income_k]
    merged[income_k] = income_v
    i = i + 1
  end

  logger.dbg("AnnotationSync:sync_callback: handling merged list")
  local merged_list = M.map_to_list(merged)

  if is_likely_404 and next(local_map) == nil then
    logger.dbg(
      "AnnotationSync: remote file does not exist and local file is empty, skipping push to server"
    )
    return false, merged_list
  end

  util.writeToFile(json.encode(merged), local_file)
  return true, merged_list
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

-- Detects deletions by comparing local state with last known synced state
function M.get_deleted_annotations(
  local_map,
  last_uploaded_map,
  document,
  force
)
  if type(last_uploaded_map) == "table" and type(local_map) == "table" then
    local local_keys = M.sort_keys_by_position(local_map)
    local uploaded_keys = M.sort_keys_by_position(last_uploaded_map)

    -- SAFETY (Issue 23): If local is empty but last sync was not,
    -- it's likely a docsettings failure or fresh device state.
    -- We skip deletion propagation to avoid wiping remote data.
    -- We bypass this safety if 'force' is true (manual sync).
    if not force and #local_keys == 0 and #uploaded_keys > 0 then
      logger.warn(
        "AnnotationSync: Local annotations empty but last sync had",
        #uploaded_keys,
        ". Skipping deletions to protect data."
      )
      return
    end

    for __, uploaded_k in ipairs(uploaded_keys) do
      local uploaded_v = last_uploaded_map[uploaded_k]
      local local_and_uploaded = false
      for __, local_k in ipairs(local_keys) do
        local local_v = local_map[local_k]
        if M.positions_intersect(uploaded_v, local_v, document) then
          local_and_uploaded = true
          break
        end
        if M.compare_positions(local_v, uploaded_v) < 0 then
          break
        end
      end
      if not local_and_uploaded then
        uploaded_v.deleted = true
        uploaded_v.datetime_updated = os.date("%Y-%m-%d %H:%M:%S")
        local_map[uploaded_k] = uploaded_v
      end
    end
  end
end

-- Universal comparison logic for annotation position tables
function M.compare_positions(a, b)
  assert(
    type(a) == "table" and type(b) == "table",
    "compare_positions requires table arguments"
  )

  -- Check if both are rolling XPointers (either in pos0 or page)
  local xp_a = (type(a.pos0) == "string" and a.pos0)
    or (type(a.page) == "string" and a.page)
  local xp_b = (type(b.pos0) == "string" and b.pos0)
    or (type(b.page) == "string" and b.page)

  if xp_a and xp_b then
    if xp_a == xp_b then
      return 0
    end
    if natsort(xp_a, xp_b) then
      return 1
    elseif natsort(xp_b, xp_a) then
      return -1
    else
      return 0
    end
  end

  local page_a = a.page or (type(a.pos0) == "table" and a.pos0.page)
  local page_b = b.page or (type(b.pos0) == "table" and b.pos0.page)

  assert(
    page_a ~= nil and page_b ~= nil,
    "compare_positions requires page or pos0 in arguments"
  )

  if page_a ~= page_b then
    if type(page_a) == "number" and type(page_b) == "number" then
      return page_b - page_a
    end

    local str_a = tostring(page_a)
    local str_b = tostring(page_b)
    if natsort(str_a, str_b) then
      return 1
    elseif natsort(str_b, str_a) then
      return -1
    else
      return 0
    end
  end

  -- Same page: compare sub-page position / coordinates
  local pos_a = type(a.pos0) == "table" and a.pos0 or a
  local pos_b = type(b.pos0) == "table" and b.pos0 or b

  local has_coords_a = (pos_a.x ~= nil or pos_a.y ~= nil)
  local has_coords_b = (pos_b.x ~= nil or pos_b.y ~= nil)

  if not has_coords_a and has_coords_b then
    -- Bookmark on same page is strictly ordered before highlight
    return 1
  elseif has_coords_a and not has_coords_b then
    return -1
  elseif has_coords_a and has_coords_b then
    if pos_a.y and pos_b.y and pos_a.y ~= pos_b.y then
      return pos_b.y - pos_a.y
    end
    if pos_a.x and pos_b.x and pos_a.x ~= pos_b.x then
      return pos_b.x - pos_a.x
    end
    return 0
  end

  return 0
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

function M.is_annotation(candidate)
  return candidate and candidate.pos0 and candidate.pos1
end

function M.is_bookmark(candidate)
  return candidate and candidate.page and not M.is_annotation(candidate)
end

function M.is_before(a, b)
  local a_time = a.datetime_updated or a.datetime or 0
  local b_time = b.datetime_updated or b.datetime or 0
  return a_time <= b_time
end

function M.sort_keys_by_position(t)
  local keys = {}
  for k in pairs(t) do
    table.insert(keys, k)
  end
  table.sort(keys, function(a, b)
    return M.compare_positions(t[a], t[b]) > 0
  end)
  return keys
end

function M.positions_intersect(a, b, document)
  if not a or not b then
    return false
  end

  if M.annotation_key(a) == M.annotation_key(b) then
    return true
  end

  if not a.pos0 or not a.pos1 or not b.pos0 or not b.pos1 then
    return false
  end

  -- If document comparison functions aren't available, avoid false spatial overlap detection
  local has_cmp = document
    and (
      type(document.comparePositions) == "function"
      or type(document.compareXPointers) == "function"
    )
  if not has_cmp then
    return false
  end

  local a_end = {
    page = (type(a.pos1) == "table" and (a.pos1.page or a.page))
      or (type(a.pos1) == "string" and a.pos1)
      or a.page,
    pos0 = a.pos1,
  }
  local b_end = {
    page = (type(b.pos1) == "table" and (b.pos1.page or b.page))
      or (type(b.pos1) == "string" and b.pos1)
      or b.page,
    pos0 = b.pos1,
  }

  -- A_Start <= B_Start <= A_End
  if
    M.compare_positions(a, b) >= 0
    and M.compare_positions(b, a_end) >= 0
  then
    return true
  end

  -- B_Start <= A_Start <= B_End
  if
    M.compare_positions(b, a) >= 0
    and M.compare_positions(a, b_end) >= 0
  then
    return true
  end

  return false
end

return M
