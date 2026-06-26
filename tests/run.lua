-- run.lua - deterministic test entry point.
--
-- Runs the whole suite in one Lua process with a single pass/fail summary and a
-- non-zero exit code on failure (so `mise run test` / CI can gate on it).
--
-- Zero install: uses the vendored tests/luaunit.lua and the system `lua`. No
-- luarocks, no network, no real filesystem access (the wezterm mock fakes it).
--
-- Run from the repo root:   lua tests/run.lua
-- or via mise:              mise run test

-- Make `require` find both the test helpers/luaunit (tests/) and the plugin
-- modules (plugin/?.lua), regardless of the caller's CWD, by deriving paths
-- from this file's own location.
local this = debug.getinfo(1, "S").source:sub(2) -- strip leading "@"
local tests_dir = this:match("^(.*[/\\])") or "./"
-- repo_root is tests_dir with the trailing "tests/" segment removed. For a
-- relative invocation ("lua tests/run.lua") tests_dir is "tests/", so repo_root
-- becomes "" (i.e. the CWD, which is the repo root); for an absolute path it is
-- the absolute repo root. We also add tests_dir .. "../plugin" so the suite
-- still resolves when run from inside tests/.
local repo_root = tests_dir:gsub("tests[/\\]$", "")

package.path = table.concat({
  tests_dir .. "?.lua",
  repo_root .. "plugin/?.lua",
  tests_dir .. "../plugin/?.lua",
  package.path,
}, ";")

local lu = require("luaunit")

-- Load each test module. Each defines global Test* tables that luaunit
-- discovers. Order is irrelevant: every test reloads its modules fresh.
require("test_config")
require("test_style")
require("test_finder")

-- -v = verbose (list each test). Exit code is non-zero if anything fails.
os.exit(lu.LuaUnit.run("-v"))
