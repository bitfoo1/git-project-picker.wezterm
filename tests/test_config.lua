-- test_config.lua - merge semantics for config.resolve / deep_merge.
--
-- These are pure (no I/O): they only need wezterm.home_dir, which the mock
-- supplies deterministically, so the same options always resolve identically.

local lu = require("luaunit")
local H = require("helpers")

local HOME = "/home/tester"

local function load_config()
  return H.load("git-project-picker.config", H.make_wezterm({ home_dir = HOME }))
end

TestConfig = {}

function TestConfig:test_defaults_have_expected_shape()
  local c = load_config()
  local r = c.resolve(nil)
  lu.assertEquals(r.search_paths, { HOME .. "/git" })
  lu.assertEquals(r.max_depth, 4)
  lu.assertIsTrue(r.use_zoxide)
  lu.assertEquals(r.style.label_segments, 2)
  lu.assertEquals(r.style.prefix_color, "#7aa2f7")
end

-- Regression for bug #2: an empty array override must CLEAR the default array,
-- so `search_paths = {}` disables the fd scan (as the README promises) instead
-- of silently keeping ~/git.
function TestConfig:test_empty_search_paths_clears_default()
  local c = load_config()
  local r = c.resolve({ search_paths = {} })
  lu.assertEquals(r.search_paths, {})
  lu.assertEquals(#r.search_paths, 0)
end

function TestConfig:test_search_paths_replace_not_merge()
  local c = load_config()
  local r = c.resolve({ search_paths = { "/a", "/b" } })
  lu.assertEquals(r.search_paths, { "/a", "/b" })
end

function TestConfig:test_array_option_replaced_wholesale()
  local c = load_config()
  -- here_shell_processes default has many entries; override must not inherit them.
  local r = c.resolve({ here_shell_processes = { "fish" } })
  lu.assertEquals(r.here_shell_processes, { "fish" })
end

function TestConfig:test_style_map_deep_merges()
  local c = load_config()
  local r = c.resolve({ style = { repo_color = "#ffffff" } })
  lu.assertEquals(r.style.repo_color, "#ffffff") -- overridden
  lu.assertEquals(r.style.prefix_color, "#7aa2f7") -- default preserved
  lu.assertEquals(r.style.label_segments, 2) -- default preserved
end

function TestConfig:test_keys_map_deep_merges()
  local c = load_config()
  local r = c.resolve({ keys = { tab_shell = "p" } })
  lu.assertEquals(r.keys.tab_shell, "p") -- overridden
  lu.assertEquals(r.keys.here_editor, "e") -- default preserved
  lu.assertEquals(r.keys.prefix.key, "f") -- nested default preserved
end

function TestConfig:test_keys_false_passthrough()
  local c = load_config()
  local r = c.resolve({ keys = false })
  lu.assertEquals(r.keys, false)
end

function TestConfig:test_scalar_override()
  local c = load_config()
  local r = c.resolve({ max_depth = 7, editor = "nvim" })
  lu.assertEquals(r.max_depth, 7)
  lu.assertEquals(r.editor, "nvim")
end

function TestConfig:test_resolve_does_not_mutate_defaults()
  local c = load_config()
  c.resolve({ max_depth = 99, search_paths = { "/x" } })
  local fresh = c.resolve(nil)
  lu.assertEquals(fresh.max_depth, 4)
  lu.assertEquals(fresh.search_paths, { HOME .. "/git" })
end

TestIsArray = {}

function TestIsArray:test_is_array_detection()
  local c = load_config()
  lu.assertIsTrue(c.is_array({ "x" }))
  lu.assertIsTrue(c.is_array({ 1, 2, 3 }))
  lu.assertIsFalse(c.is_array({}))
  lu.assertIsFalse(c.is_array({ a = 1 }))
  lu.assertIsFalse(c.is_array("nope"))
end
