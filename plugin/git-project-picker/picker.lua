-- picker.lua - shows the fuzzy picker and launches the chosen project.
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
-- Runs the configured editor inside an *interactive* login shell so that the
-- user's PATH (e.g. mise/asdf shims) and shell aliases are available - GUI
-- terminals often start without those in a plain non-interactive shell.
-- After the editor exits, an interactive shell remains in the project
-- directory instead of the pane/tab closing.
---@param path string
---@param opts table
---@return string[] argv
local function editor_argv(path, opts)
  local cmd = string.format("cd %s && %s; exec %s -i", q(path), opts.editor, opts.shell)
  return { opts.shell, "-ilc", cmd }
end

--- Basename of a path (handles / and \ separators).
---@param p string
---@return string
local function basename(p)
  return (p:gsub("[/\\]+$", ""):match("[^/\\]+$")) or p
end

--- Is the foreground process of `pane` an interactive shell, per opts?
-- When we cannot determine the process name we assume "yes" (best effort), to
-- avoid being overly disruptive on platforms where the name is unavailable.
---@param pane any
---@param opts table
---@return boolean is_shell
---@return string|nil proc_name detected foreground process basename (nil if unknown)
local function foreground_is_shell(pane, opts)
  local ok, name = pcall(function()
    return pane:get_foreground_process_name()
  end)
  if not ok or not name or name == "" then
    return true, nil
  end
  local base = basename(name):lower()
  -- Strip a leading "-" that login shells sometimes carry (e.g. "-zsh").
  base = base:gsub("^%-", "")
  for _, s in ipairs(opts.here_shell_processes or {}) do
    if base == s:lower() then
      return true, base
    end
  end
  return false, base
end

--- Show a message to the user reliably.
-- toast_notification depends on OS notification permissions (often denied for
-- GUI terminals on macOS), so it is not dependable. Instead we render the
-- message as a single-item InputSelector overlay, which always shows inside the
-- WezTerm window and is dismissed with Enter or Escape. A toast is also emitted
-- as a best-effort extra.
---@param window any GuiWindow
---@param pane any Pane
---@param title string short overlay title
---@param message string body text (may contain newlines)
local function notify(window, pane, title, message)
  pcall(function()
    window:toast_notification("git-project-picker", title .. ": " .. message, nil, 6000)
  end)
  -- Render each line of the message as its own row, plus a dismiss row, so the
  -- whole thing is readable in the overlay list.
  local choices = {}
  for line in (message .. "\n"):gmatch("(.-)\n") do
    table.insert(choices, { id = "dismiss", label = line })
  end
  table.insert(choices, { id = "dismiss", label = "[ Press Enter or Esc to dismiss ]" })
  window:perform_action(
    wezterm.action.InputSelector({
      title = title,
      choices = choices,
      action = wezterm.action_callback(function() end),
    }),
    pane
  )
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
  -- "here" mode types a `cd` line into the current pane, which only works if the
  -- foreground process is a shell. Decide this BEFORE opening the picker so the
  -- warning overlay isn't nested inside the picker overlay (which is fragile).
  if target == "here" then
    local is_shell, proc = foreground_is_shell(pane, opts)
    if not is_shell then
      if opts.here_fallback_to_tab then
        target = "tab"
      else
        notify(
          window,
          pane,
          "Cannot open in current pane",
          ("This pane is running '%s', not a shell.\n"):format(proc or "?")
            .. "Fix: return to your shell prompt (quit the program), then retry, "
            .. "or use a tab/split binding (e.g. leader f t / v / h).\n"
            .. "Tip: set here_fallback_to_tab = true to open a new tab automatically."
        )
        return
      end
    end
  end

  local entries = finder.projects(opts)

  if #entries == 0 then
    notify(
      window,
      pane,
      "No git projects found",
      "Searched: " .. table.concat(opts.search_paths, ", ") .. "\n"
        .. "Check that the paths exist and contain git repos, "
        .. "or that zoxide/fd are installed."
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
