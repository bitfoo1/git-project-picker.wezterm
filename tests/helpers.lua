-- helpers.lua - deterministic test scaffolding for git-project-picker.wezterm.
--
-- The plugin's only external dependency is the global `wezterm` module plus the
-- child processes it spawns (zoxide/fd). To make tests fully deterministic and
-- zero-install we:
--   1. install a *controllable* fake `wezterm` into package.loaded, so every
--      `require("wezterm")` returns our mock (no real WezTerm needed); and
--   2. fake `run_child_process`/`glob` so finder.lua's discovery logic can be
--      exercised without touching the real filesystem or spawning processes.
--
-- Nothing here hits the network, the clock, or the real disk, so a given input
-- always produces the same output - change the plugin and re-run to verify.

local H = {}

--- Build a controllable fake `wezterm` module.
-- cfg fields (all optional):
--   home_dir : string                      (default "/home/tester")
--   glob     : function(pattern)->table    OR table{ [pattern]=list }
--   run      : function(argv)->ok,out,err  (run_child_process behaviour)
-- The returned mock also records:
--   w._calls       : list of argv tables passed to run_child_process
--   w._log.warn    : list of log_warn messages
--   w._log.error   : list of log_error messages
---@param cfg table|nil
---@return table wezterm-like mock
function H.make_wezterm(cfg)
  cfg = cfg or {}
  local w = {}

  w.home_dir = cfg.home_dir or "/home/tester"

  w._log = { warn = {}, error = {} }
  local function joiner(bucket)
    return function(...)
      local parts = {}
      for _, a in ipairs({ ... }) do
        parts[#parts + 1] = tostring(a)
      end
      table.insert(bucket, table.concat(parts, " "))
    end
  end
  w.log_warn = joiner(w._log.warn)
  w.log_error = joiner(w._log.error)
  w.log_info = function() end

  -- glob(pattern) -> list of matches.
  w.glob = function(pattern)
    local g = cfg.glob
    if type(g) == "function" then
      return g(pattern) or {}
    elseif type(g) == "table" then
      return g[pattern] or {}
    end
    return {}
  end

  -- run_child_process(argv) -> success(bool), stdout, stderr.
  -- Records every argv so tests can assert on the exact command line.
  w._calls = {}
  w.run_child_process = function(argv)
    table.insert(w._calls, argv)
    local r = cfg.run
    if type(r) == "function" then
      local ok, out, err = r(argv)
      if ok == nil then
        ok = true
      end
      return ok, out or "", err or ""
    end
    return true, "", ""
  end

  -- shell_quote_arg: deterministic single-quote (good enough for assertions).
  w.shell_quote_arg = function(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
  end

  -- format(items) -> string: concatenate just the Text segments so style output
  -- is assertable without caring about color escape sequences.
  w.format = function(items)
    local parts = {}
    for _, it in ipairs(items or {}) do
      if type(it) == "table" and it.Text then
        parts[#parts + 1] = it.Text
      end
    end
    return table.concat(parts)
  end

  return w
end

-- Plugin modules that must be reloaded fresh between tests so module-scoped
-- state (e.g. finder.lua's resolved_tool cache) does not leak across cases.
local PLUGIN_MODULES = {
  "git-project-picker.config",
  "git-project-picker.finder",
  "git-project-picker.style",
  "git-project-picker.picker",
}

--- Install `wez` as the `wezterm` module and require a plugin module fresh.
-- Clearing package.loaded for the plugin modules guarantees a clean module
-- state (no cached resolved tool paths, no stale options) for each test.
---@param mod_name string e.g. "git-project-picker.finder"
---@param wez table mock from H.make_wezterm
---@return table the freshly required module
function H.load(mod_name, wez)
  package.loaded["wezterm"] = wez
  for _, m in ipairs(PLUGIN_MODULES) do
    package.loaded[m] = nil
  end
  return require(mod_name)
end

--- Build a `run` handler from an ordered list of routes (first match wins).
-- Each route: { match = <lua pattern>, ok = <bool, default true>, out = <string> }.
-- `match` is tested against the argv joined by spaces. Unmatched commands
-- return ok=false (command failed) so callers degrade gracefully, mirroring a
-- missing/erroring tool.
---@param routes table[]
---@return function run handler for H.make_wezterm{ run = ... }
function H.router(routes)
  return function(argv)
    local line = table.concat(argv, " ")
    for _, r in ipairs(routes) do
      if line:find(r.match) then
        local ok = r.ok
        if ok == nil then
          ok = true
        end
        return ok, r.out or "", r.err or ""
      end
    end
    return false, "", "no route for: " .. line
  end
end

--- Find the first recorded argv whose first element matches `pattern`.
-- Useful for locating the fd/zoxide call among resolve_tool's shell calls.
---@param calls table[] w._calls
---@param pattern string lua pattern tested against argv[1]
---@return table|nil argv
function H.find_call(calls, pattern)
  for _, argv in ipairs(calls) do
    if argv[1] and argv[1]:find(pattern) then
      return argv
    end
  end
  return nil
end

--- True if any element of `argv` is exactly `value`.
---@param argv table
---@param value string
---@return boolean
function H.argv_has(argv, value)
  for _, a in ipairs(argv) do
    if a == value then
      return true
    end
  end
  return false
end

return H
