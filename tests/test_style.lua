-- test_style.lua - label splitting and choice formatting (pure functions).

local lu = require("luaunit")
local H = require("helpers")

local function load_style()
  return H.load("git-project-picker.style", H.make_wezterm({}))
end

TestSplitLabel = {}

function TestSplitLabel:test_two_segments()
  local s = load_style()
  local prefix, repo = s.split_label("/home/u/git/host/org/repo", 2)
  lu.assertEquals(prefix, "org/")
  lu.assertEquals(repo, "repo")
end

function TestSplitLabel:test_three_segments()
  local s = load_style()
  local prefix, repo = s.split_label("/home/u/git/host/org/repo", 3)
  lu.assertEquals(prefix, "host/org/")
  lu.assertEquals(repo, "repo")
end

function TestSplitLabel:test_zero_means_full_path()
  local s = load_style()
  local prefix, repo = s.split_label("/home/u/git/org/repo", 0)
  lu.assertEquals(prefix, "home/u/git/org/")
  lu.assertEquals(repo, "repo")
end

function TestSplitLabel:test_n_larger_than_depth_uses_all()
  local s = load_style()
  local prefix, repo = s.split_label("/org/repo", 10)
  lu.assertEquals(prefix, "org/")
  lu.assertEquals(repo, "repo")
end

function TestSplitLabel:test_trailing_slash_stripped()
  local s = load_style()
  local prefix, repo = s.split_label("/a/b/repo/", 2)
  lu.assertEquals(prefix, "b/")
  lu.assertEquals(repo, "repo")
end

function TestSplitLabel:test_backslashes_normalized()
  local s = load_style()
  local prefix, repo = s.split_label("C:\\src\\org\\repo", 2)
  lu.assertEquals(prefix, "org/")
  lu.assertEquals(repo, "repo")
end

function TestSplitLabel:test_single_segment_has_no_prefix()
  local s = load_style()
  local prefix, repo = s.split_label("repo", 2)
  lu.assertEquals(prefix, "")
  lu.assertEquals(repo, "repo")
end

TestFormatChoice = {}

local STYLE = {
  prefix_color = "#1", repo_color = "#2", marker_color = "#3",
  zoxide_marker = "Z ", discovered_marker = "D ", label_segments = 2,
}

function TestFormatChoice:test_zoxide_marker_and_id()
  local s = load_style()
  -- mock wezterm.format concatenates Text segments, so we can assert the text.
  local choice = s.format_choice({ path = "/a/org/repo", source = "zoxide" }, STYLE)
  lu.assertEquals(choice.id, "/a/org/repo") -- id is the absolute path
  lu.assertEquals(choice.label, "Z org/repo")
end

function TestFormatChoice:test_discovered_marker()
  local s = load_style()
  local choice = s.format_choice({ path = "/a/org/repo", source = "discovered" }, STYLE)
  lu.assertEquals(choice.label, "D org/repo")
end

function TestFormatChoice:test_choices_maps_all_entries()
  local s = load_style()
  local out = s.choices({
    { path = "/a/o/r1", source = "zoxide" },
    { path = "/a/o/r2", source = "discovered" },
  }, STYLE)
  lu.assertEquals(#out, 2)
  lu.assertEquals(out[1].id, "/a/o/r1")
  lu.assertEquals(out[2].id, "/a/o/r2")
end
