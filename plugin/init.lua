-- git-project-picker.wezterm — plugin entry point.
--
-- A fuzzy, frecency-ranked picker for your git repositories that can open the
-- chosen project as a new tab, a vertical/horizontal split, or in the current
-- pane — either as a plain shell or by launching $EDITOR.
--
-- Usage (see README.md for full options):
--
--   local picker = wezterm.plugin.require("https://git.bitfoo.de/dvonessen/git-project-picker.wezterm")
--   picker.apply_to_config(config, { search_paths = { wezterm.home_dir .. "/git" } })
--
-- The plugin spans multiple Lua modules, so we must add its own directory to
-- package.path before requiring them (per the wezterm plugin docs).

local wezterm = require("wezterm")

--- Locate this plugin's on-disk directory and add `plugin/?.lua` to package.path.
-- wezterm derives the plugin directory name from the repo URL, which differs
-- between https:// and file:// installs, so we match on the repo name suffix.
local function ensure_package_path()
  local sep = package.config:sub(1, 1) == "\\" and "\\" or "/"
  local repo_name = "git-project-picker.wezterm"

  for _, p in ipairs(wezterm.plugin.list()) do
    -- p.url ends with the repo name; p.component is a sanitized form of the URL
    -- where path separators are replaced, so the repo name appears with its
    -- punctuation mangled. Match against the url which preserves the name.
    if p.url and p.url:find(repo_name, 1, true) then
      local mod_dir = p.plugin_dir .. sep .. "plugin" .. sep .. "?.lua"
      if not package.path:find(mod_dir, 1, true) then
        package.path = package.path .. ";" .. mod_dir
      end
      return true
    end
  end

  wezterm.log_error(
    "git-project-picker: could not locate plugin directory via wezterm.plugin.list(); "
      .. "module requires may fail."
  )
  return false
end

ensure_package_path()

local config_mod = require("git-project-picker.config")
local picker = require("git-project-picker.picker")

local M = {}

-- Resolved options for the active configuration. Stored at module scope so the
-- action helpers (M.pick / M.action) can be used without re-passing options.
M.options = config_mod.resolve(nil)

--- Order of actions used when iterating the keys table.
-- Maps an action name to its (target, mode) pair.
local ACTIONS = {
  tab_shell      = { target = "tab",     mode = "shell" },
  split_v_shell  = { target = "split_v", mode = "shell" },
  split_h_shell  = { target = "split_h", mode = "shell" },
  here_shell     = { target = "here",    mode = "shell" },
  tab_editor     = { target = "tab",     mode = "editor" },
  split_v_editor = { target = "split_v", mode = "editor" },
  split_h_editor = { target = "split_h", mode = "editor" },
  here_editor    = { target = "here",    mode = "editor" },
}

--- Return a wezterm action_callback that opens the picker for a given
--- target/mode. Bind this to any key yourself if you don't use apply_to_config.
---@param target string "tab"|"split_v"|"split_h"|"here"
---@param mode string "shell"|"editor"
---@return any action wezterm action_callback
function M.action(target, mode)
  return wezterm.action_callback(function(window, pane)
    local ok, err = pcall(picker.show, window, pane, target, mode, M.options)
    if not ok then
      wezterm.log_error("git-project-picker: picker.show failed: " .. tostring(err))
    end
  end)
end

--- Programmatically open the picker.
---@param spec table|nil { target = ..., mode = ... } (defaults: tab/shell)
function M.pick(spec)
  spec = spec or {}
  local target = spec.target or "tab"
  local mode = spec.mode or "shell"
  return M.action(target, mode)
end

--- Register key bindings described by opts.keys onto a wezterm config builder.
---@param config table wezterm config builder
---@param keys table opts.keys (already resolved)
local function register_keys(config, keys)
  if keys == false or keys == nil then
    return
  end

  config.keys = config.keys or {}

  if keys.prefix then
    -- Prefix mode: LEADER+<prefix> enters a key table whose entries are the
    -- per-action keys. Each entry first pops the key table and *then* opens the
    -- picker, via act.Multiple. Opening an InputSelector overlay while a modal
    -- key table is still active is fragile (the overlay can be swallowed and the
    -- key-table indicator stays lit), so we always return to a clean state
    -- before showing the picker.
    local prefix = keys.prefix
    local table_name = "git_project_picker"

    config.key_tables = config.key_tables or {}
    local kt = {}
    for action_name, spec in pairs(ACTIONS) do
      local key = keys[action_name]
      if type(key) == "string" then
        table.insert(kt, {
          key = key,
          action = wezterm.action.Multiple({
            wezterm.action.PopKeyTable,
            M.action(spec.target, spec.mode),
          }),
        })
      end
    end
    table.insert(kt, { key = "Escape", action = "PopKeyTable" })
    config.key_tables[table_name] = kt

    table.insert(config.keys, {
      mods = prefix.mods,
      key = prefix.key,
      action = wezterm.action.ActivateKeyTable({
        name = table_name,
        one_shot = false,
        timeout_milliseconds = prefix.timeout_milliseconds or 2000,
      }),
    })
  else
    -- Flat mode: each action entry must itself be a binding spec
    -- { mods = ..., key = ... }.
    for action_name, spec in pairs(ACTIONS) do
      local binding = keys[action_name]
      if type(binding) == "table" and binding.key then
        table.insert(config.keys, {
          mods = binding.mods,
          key = binding.key,
          action = M.action(spec.target, spec.mode),
        })
      end
    end
  end
end

--- Apply the plugin to a wezterm config builder.
---@param config table wezterm config builder
---@param opts table|nil user options (see README.md)
function M.apply_to_config(config, opts)
  M.options = config_mod.resolve(opts)
  register_keys(config, M.options.keys)
  return config
end

-- Expose internals for advanced users / testing.
M.config = config_mod
M.picker = picker

return M
