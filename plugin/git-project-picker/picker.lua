-- picker.lua — shows the fuzzy picker and launches the chosen project.
--
-- Launch matrix (target x mode):
--   target: "tab" | "split_v" | "split_h" | "here"
--     split_v -> vertical split  = left/right (new pane on the Right)
--     split_h -> horizontal split = top/bottom (new pane on the Bottom)
--     here    -> reuse the current pane (no new tab/pane)
--   mode:   "shell"  -> spawn the default shell in the project directory
--           "editor" -> open $EDITOR at the project, leaving a shell behind on exit

local wezterm = require("wezterm")
local act = wezterm.action

local finder = require("git-project-picker.finder")
local style = require("git-project-picker.style")

local M = {}

--- Shell-quote a path for safe interpolation into a command string.
---@param s string
---@return string
local function q(s)
  -- shell_quote_arg is provided by wezterm; fall back to naive single-quoting.
  if wezterm.shell_quote_arg then
    return wezterm.shell_quote_arg(s)
  end
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

--- Build the argv used for "editor" launch mode.
-- Runs: cd <path> && <editor>; exec <shell>
-- so the editor opens at the project and, when it exits, an interactive shell
-- remains in the project directory instead of the pane/tab closing.
---@param path string
---@param opts table
---@return string[] argv
local function editor_argv(path, opts)
  local cmd = string.format("cd %s && %s; exec %s", q(path), opts.editor, opts.shell)
  return { opts.shell, "-lc", cmd }
end

--- Launch the selected project.
---@param window any GuiWindow from the InputSelector callback
---@param pane any Pane from the InputSelector callback
---@param path string absolute project directory
---@param target string "tab"|"split_v"|"split_h"|"here"
---@param mode string "shell"|"editor"
---@param opts table resolved options
function M.open(window, pane, path, target, mode, opts)
  -- Record the open in zoxide so frecency improves for next time.
  finder.touch(opts, path)

  local spawn = { cwd = path }
  if mode == "editor" then
    spawn.args = editor_argv(path, opts)
  end

  if target == "tab" then
    local mux_window = window:mux_window()
    mux_window:spawn_tab(spawn)
  elseif target == "split_v" or target == "split_h" then
    spawn.direction = (target == "split_v") and "Right" or "Bottom"
    pane:split(spawn)
  elseif target == "here" then
    -- Reuse the current pane: we cannot change its cwd directly, so drive the
    -- already-running shell by sending a command line.
    if mode == "editor" then
      pane:send_text(string.format("cd %s && %s\n", q(path), opts.editor))
    else
      pane:send_text(string.format("cd %s\n", q(path)))
    end
  else
    wezterm.log_error("git-project-picker: unknown target '" .. tostring(target) .. "'")
  end
end

--- Show the fuzzy project picker, then launch the chosen project.
-- Intended to be wrapped in wezterm.action_callback.
---@param window any GuiWindow
---@param pane any Pane
---@param target string "tab"|"split_v"|"split_h"|"here"
---@param mode string "shell"|"editor"
---@param opts table resolved options
function M.show(window, pane, target, mode, opts)
  local entries = finder.projects(opts)

  if #entries == 0 then
    window:toast_notification(
      "git-project-picker",
      "No git projects found in: " .. table.concat(opts.search_paths, ", "),
      nil,
      4000
    )
    return
  end

  local choices = style.choices(entries, opts.style)

  window:perform_action(
    act.InputSelector({
      title = opts.title,
      choices = choices,
      fuzzy = opts.fuzzy,
      fuzzy_description = "Find git project: ",
      action = wezterm.action_callback(function(inner_window, inner_pane, id, label)
        if not id then
          return -- cancelled
        end
        M.open(inner_window, inner_pane, id, target, mode, opts)
      end),
    }),
    pane
  )
end

return M
