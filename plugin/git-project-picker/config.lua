-- config.lua — default options and merge logic for git-project-picker.wezterm
--
-- The public option table is documented in the README. Every field here has a
-- sane default so that `apply_to_config(config)` works with zero configuration.

local wezterm = require("wezterm")

local M = {}

--- Build the default option table.
-- Done lazily in a function so that env-dependent values (HOME, EDITOR, SHELL)
-- are resolved at the time the plugin is configured, not at module load.
---@return table
local function defaults()
  local home = wezterm.home_dir
  return {
    -- List of root directories to scan for git repositories.
    -- Each entry may contain a leading "~" or "$HOME" which is expanded.
    search_paths = { home .. "/git" },

    -- How deep to search *below* each search_path for a ".git" entry.
    -- A value of 4 matches layouts like ~/git/<host>/<org>/<repo>/.git .
    max_depth = 4,

    -- Also include directories already known to zoxide (frecency source),
    -- filtered to those that are git repositories. Set to false to rely
    -- purely on the fd scan.
    use_zoxide = true,

    -- When true, the selected project is added to the zoxide database
    -- (`zoxide add <path>`) so frequently/recently opened projects float
    -- to the top of the list on subsequent invocations.
    update_zoxide_on_open = true,

    -- External tool paths/names. Bare names are resolved via PATH.
    zoxide_path = "zoxide",
    fd_path = "fd",

    -- Program used for the "editor" launch mode. This is an explicit option:
    -- set it to whatever editor you want (e.g. "nvim", "hx", "code -w", "vim").
    -- It is run through an interactive shell so your normal PATH and shell
    -- aliases apply. It is intentionally NOT read from $EDITOR, because GUI
    -- terminals frequently launch without $EDITOR set.
    editor = "vi",

    -- Shell used to run "cd <dir> && exec <editor>" so that, on editor exit,
    -- an interactive shell remains in the project directory.
    shell = os.getenv("SHELL") or "/bin/sh",

    -- Process (basenames) considered "a shell" for the purposes of "here" mode.
    -- "here" mode works by typing a `cd` command into the current pane, which
    -- only makes sense if the foreground process is an interactive shell. If
    -- the foreground process is something else (an editor, REPL, pager, ...),
    -- typing into it does weird things. Add any other shells you use.
    here_shell_processes = {
      "sh", "bash", "zsh", "fish", "dash", "ksh", "tcsh", "csh", "nu", "xonsh", "elvish",
    },

    -- What to do when "here" mode is triggered but the current pane is NOT a
    -- shell (see here_shell_processes):
    --   false (default) -> show an explanatory message and do nothing.
    --   true            -> silently open the project in a new tab instead.
    here_fallback_to_tab = false,

    -- Title shown at the top of the fuzzy picker overlay.
    title = "  Git Projects",

    -- Start the picker directly in fuzzy-find mode.
    fuzzy = true,

    -- Styling - see style.lua for the meaning of each field.
    style = {
      -- Foreground color of the "org/" path prefix in each label.
      prefix_color = "#7aa2f7",
      -- Foreground color of the repository (basename) portion of the label.
      repo_color = "#c0caf5",
      -- Color of the small frecency/source marker shown before each entry.
      marker_color = "#565f89",
      -- Marker text shown for entries sourced from zoxide (already visited).
      zoxide_marker = "󰁤 ",
      -- Marker text shown for entries discovered only via the fd scan.
      discovered_marker = "󰊢 ",
      -- Number of trailing path segments to show as the label
      -- (e.g. 2 -> "org/repo", 3 -> "host/org/repo"). 0 shows the full path.
      label_segments = 2,
    },

    -- Keymap configuration consumed by apply_to_config().
    -- Set keys = false to skip registering any key bindings (you can still
    -- call the exposed action helpers manually).
    keys = {
      -- Optional leader/prefix. When set, every action below is registered
      -- as `prefix` followed by the action key (a wezterm key table).
      -- Set prefix = false to register each action as a flat binding using
      -- its own `mods`/`key` (define them in the action entries).
      prefix = { mods = "LEADER", key = "f", timeout_milliseconds = 2000 },

      -- Action -> key (within the prefix table) OR full binding spec
      -- ({ mods = ..., key = ... }) when prefix = false.
      -- lowercase = shell mode, uppercase = editor mode (by convention).
      tab_shell      = "t", -- new tab
      split_v_shell  = "v", -- vertical tile = left/right (new pane on the right)
      split_h_shell  = "h", -- horizontal split = top/bottom (new pane on bottom)
      here_shell     = "f", -- reuse current pane, just cd
      tab_editor     = "T",
      split_v_editor = "V",
      split_h_editor = "H",
      here_editor    = "e",
    },
  }
end

--- Recursively merge `override` into `base`, returning a new table.
-- Arrays (search_paths etc.) in `override` replace the base array entirely;
-- plain key/value sub-tables are merged key-by-key.
---@param base table
---@param override table|nil
---@return table
local function deep_merge(base, override)
  if type(override) ~= "table" then
    return base
  end
  local out = {}
  for k, v in pairs(base) do
    out[k] = v
  end
  for k, v in pairs(override) do
    -- Only deep-merge when BOTH sides are plain key/value tables. If either the
    -- override or the base is an array (e.g. search_paths), replace wholesale -
    -- otherwise an empty override array ({}) has no [1] and would be treated as
    -- a map, silently keeping the default array instead of clearing it.
    if type(v) == "table" and type(out[k]) == "table"
      and not M.is_array(v) and not M.is_array(out[k]) then
      out[k] = deep_merge(out[k], v)
    else
      out[k] = v
    end
  end
  return out
end

--- Heuristic: treat a table with a [1] element as an array (replace, not merge).
---@param t table
---@return boolean
function M.is_array(t)
  return type(t) == "table" and t[1] ~= nil
end

--- Produce a resolved option table from user-supplied options.
---@param opts table|nil
---@return table
function M.resolve(opts)
  return deep_merge(defaults(), opts)
end

M.defaults = defaults

return M
