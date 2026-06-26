-- style.lua - turns project entries into styled InputSelector choices.
--
-- Each choice has:
--   id    = the absolute project path (passed to the launch action)
--   label = colored text shown in the picker (wezterm.format output)
--
-- All visual aspects are driven by opts.style so users can recolor or change
-- the markers without touching this file.

local wezterm = require("wezterm")

local M = {}

--- Return the last `n` segments of a path joined by "/".
-- n <= 0 returns the full (home-shortened) path.
---@param path string
---@param n integer
---@return string prefix everything before the basename (may be "")
---@return string repo  the basename
local function split_label(path, n)
  -- Normalize separators to "/" for display.
  local norm = path:gsub("\\", "/"):gsub("/+$", "")

  local segments = {}
  for seg in norm:gmatch("[^/]+") do
    table.insert(segments, seg)
  end
  if #segments == 0 then
    return "", norm
  end

  local repo = segments[#segments]

  local start
  if n and n > 0 then
    start = math.max(1, #segments - n + 1)
  else
    start = 1
  end

  local prefix_parts = {}
  for i = start, #segments - 1 do
    table.insert(prefix_parts, segments[i])
  end

  local prefix = table.concat(prefix_parts, "/")
  if #prefix > 0 then
    prefix = prefix .. "/"
  end
  return prefix, repo
end

--- Format a single entry into an InputSelector choice.
---@param entry table { path = string, source = string }
---@param style table opts.style
---@return table choice { id = string, label = string }
function M.format_choice(entry, style)
  local prefix, repo = split_label(entry.path, style.label_segments)
  local marker = (entry.source == "zoxide") and style.zoxide_marker or style.discovered_marker

  local label = wezterm.format({
    { Foreground = { Color = style.marker_color } },
    { Text = marker },
    { Foreground = { Color = style.prefix_color } },
    { Text = prefix },
    { Foreground = { Color = style.repo_color } },
    { Attribute = { Intensity = "Bold" } },
    { Text = repo },
  })

  return { id = entry.path, label = label }
end

--- Map a list of entries to InputSelector choices.
---@param entries table[]
---@param style table opts.style
---@return table[] choices
function M.choices(entries, style)
  local out = {}
  for _, entry in ipairs(entries) do
    table.insert(out, M.format_choice(entry, style))
  end
  return out
end

-- Exposed for testing.
M.split_label = split_label

return M
