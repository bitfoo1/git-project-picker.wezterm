-- test_finder.lua - discovery, tool resolution, ordering, and regressions.
--
-- finder.lua shells out to zoxide/fd and globs the filesystem. The wezterm mock
-- injects deterministic replacements for both, so these tests are reproducible
-- and never touch the real disk or spawn a process.
--
-- Tip: pass ABSOLUTE tool paths (fd_path/zoxide_path) so resolve_tool trusts
-- them verbatim and makes no shell `command -v` calls - that keeps argv[0]
-- predictable and the recorded call list focused on the real commands.

local lu = require("luaunit")
local H = require("helpers")

-- glob(pattern):
--   * a "<dir>/.git" pattern matches when <dir> is in `git_dirs`;
--   * any other pattern (a root existence check) matches when it is in `roots`.
local function make_glob(roots, git_dirs)
  local rootset, gitset = {}, {}
  for _, r in ipairs(roots) do rootset[r] = true end
  for _, d in ipairs(git_dirs) do gitset[d .. "/.git"] = true end
  return function(pattern)
    if pattern:match("/%.git$") then
      return gitset[pattern] and { pattern } or {}
    end
    return rootset[pattern] and { pattern } or {}
  end
end

local function base_opts(over)
  local o = {
    search_paths = { "/projects" },
    max_depth = 4,
    use_zoxide = true,
    update_zoxide_on_open = true,
    zoxide_path = "/bin/zoxide", -- absolute -> resolve_tool trusts as-is
    fd_path = "/bin/fd",
    shell = "/bin/sh",
  }
  for k, v in pairs(over or {}) do o[k] = v end
  return o
end

TestExpandHome = {}

function TestExpandHome:test_tilde_and_var_expand()
  local f = H.load("git-project-picker.finder", H.make_wezterm({ home_dir = "/home/tester" }))
  lu.assertEquals(f.expand_home("~/git"), "/home/tester/git")
  lu.assertEquals(f.expand_home("$HOME/code"), "/home/tester/code")
  lu.assertEquals(f.expand_home("/abs/path"), "/abs/path")
end

TestIsGitRepo = {}

function TestIsGitRepo:test_matches_when_dotgit_present()
  local wez = H.make_wezterm({ glob = make_glob({}, { "/a/repo" }) })
  local f = H.load("git-project-picker.finder", wez)
  lu.assertIsTrue(f.is_git_repo("/a/repo"))
  lu.assertIsFalse(f.is_git_repo("/a/not-a-repo"))
end

TestFromFd = {}

-- Regression for bug #1: the fd argv must NOT contain a stray "." search path.
-- With it, fd treated "." (wezterm's CWD, typically "/" or $HOME under a GUI)
-- as a second root and leaked unrelated repos. The pattern ".git" must be
-- present, but "." alone must not, and the configured root must be the path arg.
function TestFromFd:test_fd_argv_has_no_stray_dot()
  local wez = H.make_wezterm({
    glob = make_glob({ "/projects" }, {}),
    run = H.router({ { match = "/bin/fd", out = "" } }),
  })
  local f = H.load("git-project-picker.finder", wez)
  f.projects(base_opts({ use_zoxide = false }))

  local fd_argv = H.find_call(wez._calls, "/bin/fd")
  lu.assertNotNil(fd_argv)
  lu.assertIsFalse(H.argv_has(fd_argv, "."), "fd argv must not contain a stray '.'")
  lu.assertIsTrue(H.argv_has(fd_argv, ".git"), "fd must still search for the .git glob")
  lu.assertIsTrue(H.argv_has(fd_argv, "/projects"), "fd must search the configured root")
  -- the configured root must be the final argument (the search path)
  lu.assertEquals(fd_argv[#fd_argv], "/projects")
end

function TestFromFd:test_fd_includes_prune_and_glob_flags()
  local wez = H.make_wezterm({
    glob = make_glob({ "/projects" }, {}),
    run = H.router({ { match = "/bin/fd", out = "" } }),
  })
  local f = H.load("git-project-picker.finder", wez)
  f.projects(base_opts({ use_zoxide = false }))
  local fd_argv = H.find_call(wez._calls, "/bin/fd")
  lu.assertIsTrue(H.argv_has(fd_argv, "--prune"))
  lu.assertIsTrue(H.argv_has(fd_argv, "--glob"))
  lu.assertIsTrue(H.argv_has(fd_argv, "--hidden"))
  lu.assertIsTrue(H.argv_has(fd_argv, "4")) -- max_depth value
end

function TestFromFd:test_nonexistent_root_is_skipped()
  -- /projects is NOT in the glob root set, so it "does not exist" and fd is
  -- never invoked - finder must degrade quietly, not error.
  local wez = H.make_wezterm({
    glob = make_glob({}, {}),
    run = H.router({ { match = "/bin/fd", out = "" } }),
  })
  local f = H.load("git-project-picker.finder", wez)
  local entries = f.projects(base_opts({ use_zoxide = false }))
  lu.assertEquals(entries, {})
  lu.assertNil(H.find_call(wez._calls, "/bin/fd"))
end

function TestFromFd:test_fd_parses_repos_and_strips_dotgit()
  local wez = H.make_wezterm({
    glob = make_glob({ "/projects" }, {}),
    run = H.router({
      { match = "/bin/fd", out = "/projects/org/repoA/.git\n/projects/org/repoB/.git/\n" },
    }),
  })
  local f = H.load("git-project-picker.finder", wez)
  local entries = f.projects(base_opts({ use_zoxide = false }))
  lu.assertEquals(#entries, 2)
  lu.assertEquals(entries[1].path, "/projects/org/repoA")
  lu.assertEquals(entries[1].source, "discovered")
  lu.assertEquals(entries[2].path, "/projects/org/repoB") -- trailing /.git/ stripped
end

TestProjects = {}

function TestProjects:test_zoxide_first_then_discovered_deduped()
  -- zoxide knows repoA (also on disk) + repoZ; fd finds repoA (dup) + repoB.
  -- Expected order: repoA, repoZ (zoxide/frecency), then repoB (discovered).
  local wez = H.make_wezterm({
    glob = make_glob(
      { "/projects" },
      { "/projects/org/repoA", "/home/other/repoZ", "/projects/org/repoB" }
    ),
    run = H.router({
      { match = "zoxide query", out = "/projects/org/repoA\n/home/other/repoZ\n/not/a/repo\n" },
      { match = "/bin/fd", out = "/projects/org/repoA/.git\n/projects/org/repoB/.git\n" },
    }),
  })
  local f = H.load("git-project-picker.finder", wez)
  local entries = f.projects(base_opts())

  lu.assertEquals(#entries, 3)
  lu.assertEquals(entries[1].path, "/projects/org/repoA")
  lu.assertEquals(entries[1].source, "zoxide")
  lu.assertEquals(entries[2].path, "/home/other/repoZ")
  lu.assertEquals(entries[2].source, "zoxide")
  lu.assertEquals(entries[3].path, "/projects/org/repoB")
  lu.assertEquals(entries[3].source, "discovered")
end

function TestProjects:test_zoxide_filters_non_git_dirs()
  -- /not/a/repo is returned by zoxide but is not a git repo -> excluded.
  local wez = H.make_wezterm({
    glob = make_glob({ "/projects" }, { "/projects/org/repoA" }),
    run = H.router({
      { match = "zoxide query", out = "/projects/org/repoA\n/not/a/repo\n" },
      { match = "/bin/fd", out = "" },
    }),
  })
  local f = H.load("git-project-picker.finder", wez)
  local entries = f.projects(base_opts())
  lu.assertEquals(#entries, 1)
  lu.assertEquals(entries[1].path, "/projects/org/repoA")
end

function TestProjects:test_use_zoxide_false_skips_zoxide_call()
  local wez = H.make_wezterm({
    glob = make_glob({ "/projects" }, {}),
    run = H.router({
      { match = "zoxide query", out = "/should/not/be/used\n" },
      { match = "/bin/fd", out = "" },
    }),
  })
  local f = H.load("git-project-picker.finder", wez)
  f.projects(base_opts({ use_zoxide = false }))
  lu.assertNil(H.find_call(wez._calls, "/bin/zoxide"))
end

function TestProjects:test_search_paths_empty_means_no_fd()
  -- Ties the config fix to behaviour: with no search paths, fd is never run.
  local wez = H.make_wezterm({
    glob = make_glob({}, { "/projects/org/repoA" }),
    run = H.router({
      { match = "zoxide query", out = "/projects/org/repoA\n" },
      { match = "/bin/fd", out = "should-not-run" },
    }),
  })
  local f = H.load("git-project-picker.finder", wez)
  local entries = f.projects(base_opts({ search_paths = {} }))
  lu.assertNil(H.find_call(wez._calls, "/bin/fd"))
  lu.assertEquals(#entries, 1) -- only the zoxide repo
  lu.assertEquals(entries[1].source, "zoxide")
end

TestTouch = {}

function TestTouch:test_touch_adds_to_zoxide_when_enabled()
  local wez = H.make_wezterm({ run = H.router({ { match = "zoxide add", out = "" } }) })
  local f = H.load("git-project-picker.finder", wez)
  f.touch(base_opts(), "/projects/org/repoA")
  local add = H.find_call(wez._calls, "/bin/zoxide")
  lu.assertNotNil(add)
  lu.assertIsTrue(H.argv_has(add, "add"))
  lu.assertIsTrue(H.argv_has(add, "/projects/org/repoA"))
end

function TestTouch:test_touch_noop_when_disabled()
  local wez = H.make_wezterm({ run = H.router({ { match = "zoxide add", out = "" } }) })
  local f = H.load("git-project-picker.finder", wez)
  f.touch(base_opts({ update_zoxide_on_open = false }), "/projects/org/repoA")
  lu.assertNil(H.find_call(wez._calls, "/bin/zoxide"))
end

TestResolveTool = {}

function TestResolveTool:test_bare_name_resolved_via_shell()
  -- A bare tool name triggers shell `command -v`; first absolute hit wins.
  local wez = H.make_wezterm({
    glob = make_glob({ "/projects" }, {}),
    run = H.router({
      { match = "command %-v fd", out = "/usr/local/bin/fd\n" },
      { match = "/usr/local/bin/fd", out = "" },
    }),
  })
  local f = H.load("git-project-picker.finder", wez)
  f.projects(base_opts({ fd_path = "fd", use_zoxide = false }))
  -- the resolved absolute path must have been used for the actual fd call
  lu.assertNotNil(H.find_call(wez._calls, "/usr/local/bin/fd"))
end
