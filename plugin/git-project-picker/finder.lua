-- finder.lua — discovers git project directories and orders them by frecency.
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
  local ok, success, stdout, stderr = pcall(wezterm.run_child_process, argv)
  if not ok then
    wezterm.log_warn("git-project-picker: failed to spawn " .. table.concat(argv, " ") .. ": " .. tostring(success))
    return nil
  end
  if not success then
    wezterm.log_warn("git-project-picker: command failed: " .. table.concat(argv, " ") .. " :: " .. tostring(stderr))
    return nil
  end
  return stdout
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
  local out = run({ opts.zoxide_path, "query", "-l" })
  if not out then
    return {}
  end
  local repos = {}
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
  for _, raw in ipairs(opts.search_paths or {}) do
    local root = strip_trailing_sep(expand_home(raw))
    -- Only scan roots that exist to avoid noisy fd errors.
    if #wezterm.glob(root) > 0 then
      local out = run({
        opts.fd_path,
        "--hidden",
        "--no-ignore-vcs",
        "--prune",
        "--absolute-path",
        "--max-depth", tostring(opts.max_depth),
        "--glob", ".git",
        ".",
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
  run({ opts.zoxide_path, "add", path })
end

-- Exposed for testing / reuse.
M.expand_home = expand_home
M.is_git_repo = is_git_repo

return M
