local ReaderAnnotation = require("apps/reader/modules/readerannotation")
local SyncService = require("apps/cloudstorage/syncservice")
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

local M = {}

local function read_to_array(file)
  local raw = utils.read_json(file)
  if type(raw) ~= "table" then
    return nil
  end
  local c = 0
  local valid = {}
  for _, v in pairs(raw) do
    c = c + 1
    if ReaderAnnotation.isValidItem(v) then
      table.insert(valid, v)
    end
  end
  if c > 0 and #valid == 0 then
    -- No single valid bookmark, though the file is json, it's still unexpected,
    -- trigger it as an invalid file.
    return nil
  end
  return M.sort(valid)
end

function M.merge(local_list, base_list, income_list)
  assert(type(local_list) == "table", "local_list must be a table")

  -- The book never holds tombstones, so a base tombstone missing from it is not
  -- a local deletion; a live income copy of it is a restore made elsewhere.
  local live_base = {}
  for _, v in ipairs(base_list) do
    if not v.deleted then
      table.insert(live_base, v)
    end
  end
  base_list = live_base

  -- SAFETY (Issue 23): If local is empty but last sync was not,
  -- it's likely a docsettings failure or fresh device state.
  -- We skip deletion propagation to avoid wiping remote data.
  -- The manager asks the user before such a restore reaches the book.
  if #local_list == 0 and #base_list > 0 then
    logger.warn(
      "AnnotationSync: Local annotations empty but last sync had",
      #base_list,
      ". Skipping deletions to protect data."
    )
    base_list = {}
  end

  local merged = {}
  local active = {}

  local function index_by_page(list)
    assert(type(list) == "table")
    local by_page = {}
    for _, item in ipairs(list) do
      local p = item.page
      local bucket = by_page[p]
      if not bucket then
        bucket = {}
        by_page[p] = bucket
      end
      table.insert(bucket, item)
    end
    return by_page
  end

  local function find_match(by_page, v)
    local bucket = by_page[v.page]
    if not bucket then
      return nil
    end
    for _, r in ipairs(bucket) do
      if ReaderAnnotation.doesMatch(v, r) then
        return r
      end
    end
    return nil
  end

  local local_by_page = index_by_page(local_list)
  local income_by_page = index_by_page(income_list)
  local base_by_page = index_by_page(base_list)

  for _, v in ipairs(local_list) do
    table.insert(merged, v)
  end
  for _, v in ipairs(income_list) do
    local r = find_match(local_by_page, v)
    if r then
      -- In both local and income, update any fields to the later one.
      -- Note, if timestamp equals, local (r) is preferred.
      if not M.is_before(v, r) then
        for key, _ in pairs(r) do
          r[key] = nil
        end
        for key, value in pairs(v) do
          r[key] = value
        end
      end
    else
      -- Explicitly make a copy so that we can tell if remote deleted it.
      table.insert(merged, v)
    end
  end
  -- Since we loop through multiple lists, the order isn't guaranteed.
  M.sort(merged)

  for _, v in ipairs(merged) do
    local is_income = find_match(income_by_page, v)
    local is_local = find_match(local_by_page, v)
    assert(is_income or is_local)
    if not v.deleted then
      if is_income and is_local then
        -- No matter if it's in base_list, it's active.
        table.insert(active, v)
      else
        local is_last_sync = find_match(base_by_page, v)
        if is_income then
          if is_last_sync then
            -- local deleted
            v.deleted = true
            v.datetime_updated = os.date("%Y-%m-%d %H:%M:%S")
          else
            -- remote add
            table.insert(active, v)
          end
        else -- is_local then
          -- Item exists locally, but is omitted from remote (no tombstone).
          -- Deletions across devices require explicit tombstones (deleted = true),
          -- so mere absence from the remote file does not delete local data.
          table.insert(active, v)
        end
      end
    end
  end

  return merged, active
end

-- Main orchestration for merging local and remote annotations
function M.sync_callback(
  local_file,
  last_sync_file,
  income_file,
  code_response
)
  logger.dbg("AnnotationSync:sync_callback: local_file:", local_file)
  logger.dbg("AnnotationSync:sync_callback: last_sync_file:", last_sync_file)
  logger.dbg("AnnotationSync:sync_callback: income_file:", income_file)

  local local_list = read_to_array(local_file)
  -- Callers write local_file right before every sync, and
  -- write_annotations_json always writes at least "{}". A missing or
  -- unreadable file is a lifecycle bug, not "no local annotations":
  -- treating it as {} turns every synced entry into a local deletion.
  assert(
    local_list,
    "AnnotationSync: missing or unreadable local sync file: " .. local_file
  )
  local last_sync_list = read_to_array(last_sync_file) or {}

  if SyncService.notFound(code_response) then
    -- No remote file found, early return to prefer anything locally.
    if #local_list == 0 then
      return nil, {}
    end
    return true, local_list
  end

  local income_list = read_to_array(income_file)
  if not income_list then
    logger.warn(
      "AnnotationSync: Failed to parse remote annotations from server. Aborting sync."
    )
    return false
  end

  local merged, active =
    M.merge(local_list, last_sync_list, income_list)

  logger.dbg("AnnotationSync:sync_callback: handling merged list")

  if #merged == 0 then
    logger.dbg(
      "AnnotationSync: remote file does not exist and local file is empty, skipping push to server"
    )
    return nil, active
  end

  assert(util.writeToFile(json.encode(merged), local_file))
  return true, active
end

-- Prepares the local sidecar data for syncing
function M.write_annotations_json(
  stored_annotations,
  sdr_dir,
  annotation_filename
)
  if not sdr_dir then
    return false
  end
  local json_path = sdr_dir .. "/" .. annotation_filename
  if util.writeToFile(json.encode(stored_annotations), json_path) then
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

    return false
  end)

  return array
end


function M.is_before(a, b)
  local a_time = a.datetime_updated or a.datetime or ""
  local b_time = b.datetime_updated or b.datetime or ""
  return a_time <= b_time
end

function M.normalize(list)
  for _, item in ipairs(list) do
    if type(item.ext) == "table" then
      local normalized_ext = {}
      for k, v in pairs(item.ext) do
        if type(v) ~= "function" then
          local num_k = tonumber(k)
          if num_k then
            normalized_ext[num_k] = v
          else
            normalized_ext[k] = v
          end
        end
      end
      item.ext = normalized_ext
    end
  end
end

return M
