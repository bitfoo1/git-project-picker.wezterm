-- finder.lua - discovers git project directories and orders them by frecency.
--
-- Two sources are merged:
--   1. zoxide  -> directories you have actually visited, in frecency order
--                 (most frequent/recent first). Filtered to git repos.
--   2. fd scan -> a fresh scan of `search_paths` for ".git" entries, so brand
--                 new / never-visited repos still show up.
--
-- zoxide-known repos are placed first (that is the "frecency" the user asked
-- for); freshly discovered repos follow, sorted alphabetically. Duplicates are
-- removed so a repo known to both sources appears once, keeping its zoxide rank.

local wezterm = require("wezterm")

local M = {}

--- Expand a leading "~" or "$HOME" in a path to the absolute home directory.
---@param path string
---@return string
local function expand_home(path)
  local home = wezterm.home_dir
  path = path:gsub("^~", home)
  path = path:gsub("^%$HOME", home)
  return path
end

--- Strip a trailing path separator (but never reduce "/" to "").
---@param path string
---@return string
local function strip_trailing_sep(path)
  if #path > 1 then
    path = path:gsub("[/\\]+$", "")
  end
  return path
end

--- Run a child process, returning stdout on success or nil on failure.
-- Never raises: wezterm.run_child_process can throw if the binary is missing,
-- so it is wrapped in pcall and failures degrade gracefully (empty source).
---@param argv string[]
---@return string|nil stdout
local function run(argv)
  -- pcall's 2nd return is either the thrown error (when ok == false) or
  -- run_child_process's own success flag (when ok == true); name it for both.
  local ok, ok_or_err, stdout, stderr = pcall(wezterm.run_child_process, argv)
  if not ok then
    wezterm.log_warn("git-project-picker: failed to spawn " .. table.concat(argv, " ") .. ": " .. tostring(ok_or_err))
    return nil
  end
  if not ok_or_err then
    wezterm.log_warn("git-project-picker: command failed: " .. table.concat(argv, " ") .. " :: " .. tostring(stderr))
    return nil
  end
  return stdout
end

-- Cache of resolved absolute tool paths, keyed by the configured name.
local resolved_tool = {}

--- Resolve a tool name to an absolute path.
-- GUI WezTerm (launched from Finder/dock) often starts with a minimal PATH that
-- lacks version managers like mise/asdf, so a bare "zoxide"/"fd" fails to spawn.
-- If `name` is already an absolute/relative path that exists, it is used as-is.
-- Otherwise we ask a shell to resolve it (`<shell> <flags> 'command -v <name>'`),
-- which loads the user's normal PATH. Both a *login* shell (sources
-- .zprofile/.zlogin/.profile) and an *interactive* shell (sources .zshrc/.bashrc)
-- are tried, since version managers may be activated in either. Results are
-- cached. Falls back to the original name so behavior is unchanged when
-- resolution is unnecessary.
---@param name string
---@param shell string shell to use for PATH resolution
---@return string resolved path (or the original name as a fallback)
local function resolve_tool(name, shell)
  if not name or name == "" then
    return name
  end
  if resolved_tool[name] ~= nil then
    return resolved_tool[name]
  end

  -- Looks like a path already (contains a separator)? Trust it.
  if name:find("[/\\]") then
    resolved_tool[name] = name
    return name
  end

  shell = shell or "/bin/sh"

  -- Try, in order: login shell, interactive shell, interactive-login shell.
  -- The first invocation that returns an absolute path wins. This spawns up to
  -- three shells synchronously on the first picker open (one-time cost; the
  -- result is cached above), and short-circuits as soon as a path is found.
  local attempts = { "-lc", "-ic", "-ilc" }
  local resolved = name
  for _, flags in ipairs(attempts) do
    local out = run({ shell, flags, "command -v " .. name })
    if out then
      local path = out:gsub("%s+$", ""):match("([^\r\n]+)%s*$")
      if path and path:find("[/\\]") then
        resolved = path
        break
      end
    end
  end

  resolved_tool[name] = resolved
  return resolved
end

--- Does `dir` contain a ".git" entry (directory or file, to support worktrees
--- and submodules whose .git is a file)?
---@param dir string
---@return boolean
local function is_git_repo(dir)
  -- glob is cheap and does not raise; it matches both dirs and files.
  local matches = wezterm.glob(dir .. "/.git")
  return matches ~= nil and #matches > 0
end

--- Query zoxide for known directories in frecency order, filtered to git repos.
---@param opts table resolved options
---@return string[] absolute repo paths, highest frecency first
local function from_zoxide(opts)
  if not opts.use_zoxide then
    return {}
  end
  local zoxide = resolve_tool(opts.zoxide_path, opts.shell)
  local out = run({ zoxide, "query", "-l" })
  if not out then
    return {}
  end
  local repos = {}
  -- Note: is_git_repo globs the filesystem once per zoxide entry, on the UI
  -- thread. Fine for typical databases; could lag with very large ones.
  for line in out:gmatch("[^\r\n]+") do
    local dir = strip_trailing_sep(line)
    if dir ~= "" and is_git_repo(dir) then
      table.insert(repos, dir)
    end
  end
  return repos
end

--- Scan each search path for git repositories using fd.
-- We search for the ".git" marker (hidden, both dirs and files) and derive the
-- repository directory as its parent. `--prune` stops fd from descending into a
-- repo once found, so nested .git dirs inside a repo are not reported.
---@param opts table resolved options
---@return string[] absolute repo paths, alphabetically sorted
local function from_fd(opts)
  local seen = {}
  local repos = {}
  local fd = resolve_tool(opts.fd_path, opts.shell)
  for _, raw in ipairs(opts.search_paths or {}) do
    local root = strip_trailing_sep(expand_home(raw))
    -- Only scan roots that exist to avoid noisy fd errors.
    if #wezterm.glob(root) > 0 then
      -- fd's argument form is `fd [OPTIONS] [pattern] [path...]`. ".git" is the
      -- pattern; `root` is the only search path. Do NOT add a "." here: it would
      -- be parsed as a second search path (wezterm's process CWD, typically "/"
      -- or $HOME under a GUI launch), leaking unrelated repos into the list and
      -- forcing a huge scan.
      local out = run({
        fd,
        "--hidden",
        "--no-ignore-vcs",
        "--prune",
        "--absolute-path",
        "--max-depth", tostring(opts.max_depth),
        "--glob", ".git",
        root,
      })
      if out then
        for line in out:gmatch("[^\r\n]+") do
          -- line is like /abs/path/repo/.git or /abs/path/repo/.git/
          local repo = line:gsub("[/\\]%.git[/\\]?$", "")
          repo = strip_trailing_sep(repo)
          if repo ~= "" and not seen[repo] then
            seen[repo] = true
            table.insert(repos, repo)
          end
        end
      end
    end
  end
  table.sort(repos)
  return repos
end

--- Build the ordered, de-duplicated list of project entries.
---@param opts table resolved options
---@return table[] entries: { path = string, source = "zoxide"|"discovered" }
function M.projects(opts)
  local entries = {}
  local seen = {}

  -- zoxide first (frecency order) ...
  for _, dir in ipairs(from_zoxide(opts)) do
    if not seen[dir] then
      seen[dir] = true
      table.insert(entries, { path = dir, source = "zoxide" })
    end
  end

  -- ... then freshly discovered repos not already seen.
  for _, dir in ipairs(from_fd(opts)) do
    if not seen[dir] then
      seen[dir] = true
      table.insert(entries, { path = dir, source = "discovered" })
    end
  end

  return entries
end

--- Record an opened project in zoxide so it gains frecency for next time.
---@param opts table resolved options
---@param path string
function M.touch(opts, path)
  if not opts.update_zoxide_on_open then
    return
  end
  run({ resolve_tool(opts.zoxide_path, opts.shell), "add", path })
end

-- Exposed for testing / reuse.
M.expand_home = expand_home
M.is_git_repo = is_git_repo

return M
