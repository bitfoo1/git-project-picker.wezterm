# git-project-picker.wezterm

A fuzzy, frecency-ranked **git project picker** for [WezTerm](https://wezterm.org).

Press a key, fuzzy-find any git repository on your machine, and open it as a
**new tab**, a **vertical/horizontal split**, or **in the current pane** - either
as a plain **shell** or by launching your **configured editor**. Every one of
those launch modes is its own configurable key binding.

```
  Git Projects
> Find git project: wez
󰁤 dvonessen/git-project-picker.wezterm
󰁤 .config/wezterm
󰊢 bitfoo/some-other-repo
```

(`󰁤` = known to zoxide / ranked by frecency, `󰊢` = freshly discovered on disk)

## Features

- **Git-only** - lists directories that contain a `.git` entry (dir *or* file,
  so worktrees and submodules work).
- **Frecency** - repositories you visit often/recently float to the top, powered
  by [`zoxide`](https://github.com/ajeetdsouza/zoxide). Opening a project records
  it in zoxide so the ranking keeps improving.
- **Fresh discovery** - a [`fd`](https://github.com/sharkdp/fd) scan of your
  configured `search_paths` surfaces brand-new repos you have never `cd`'d into.
- **Fuzzy search** - native WezTerm `InputSelector` fuzzy matching.
- **Eight launch modes** - `{ tab | vertical split | horizontal split | here } ×
  { shell | editor }`, each its own key.
- **Fully configurable** - search paths, scan depth, tool paths, editor, colors,
  markers, and every key binding.

## Requirements

| Tool | Why | Required |
|------|-----|----------|
| WezTerm (recent - `InputSelector` w/ `fuzzy`) | the picker UI | yes |
| [`fd`](https://github.com/sharkdp/fd) | discover repos under `search_paths` | yes (unless you set `search_paths = {}` and rely only on zoxide) |
| [`zoxide`](https://github.com/ajeetdsouza/zoxide) | frecency ranking | optional (`use_zoxide = false` to disable) |

## Installation

```lua
local wezterm = require("wezterm")
local config = wezterm.config_builder()

local project_picker =
  wezterm.plugin.require("https://git.bitfoo.de/dvonessen/git-project-picker.wezterm")

project_picker.apply_to_config(config)

return config
```

That registers the default key bindings (see below). With zero options it scans
`$HOME/git`.

## Configuration

Pass an options table as the second argument to `apply_to_config`. All fields
are optional; defaults are shown.

```lua
project_picker.apply_to_config(config, {
  -- Directories scanned for git repos. "~" and "$HOME" are expanded.
  search_paths = { wezterm.home_dir .. "/git" },

  -- How deep below each search path to look for a ".git" entry.
  -- 4 matches ~/git/<host>/<org>/<repo>/.git
  max_depth = 4,

  -- Merge zoxide's known directories (frecency order) into the list.
  use_zoxide = true,
  -- Record the chosen project in zoxide on open (improves future ranking).
  update_zoxide_on_open = true,

  -- External tool paths (bare names are looked up on PATH; resolved via your
  -- login/interactive shell so version managers like mise/asdf are found even
  -- when WezTerm is launched from the GUI with a minimal PATH).
  zoxide_path = "zoxide",
  fd_path     = "fd",

  -- "editor" launch mode runs (in an interactive login shell, so your PATH and
  -- shell aliases apply): cd <project> && <editor>; exec <shell>
  -- This is an explicit option - set it to whatever you use. It is intentionally
  -- NOT read from $EDITOR, because GUI terminals often start without it set.
  editor = "vi",          -- e.g. "nvim", "hx", "vim", "code -w"
  shell  = os.getenv("SHELL") or "/bin/sh",

  -- "here" mode types a `cd` into the current pane, which only works if a shell
  -- is in the foreground. These are the process names treated as shells.
  here_shell_processes = {
    "sh", "bash", "zsh", "fish", "dash", "ksh", "tcsh", "csh", "nu", "xonsh", "elvish",
  },
  -- When "here" mode is used but the pane is NOT a shell:
  --   false (default) -> show an explanatory message and do nothing
  --   true            -> open the project in a new tab instead
  here_fallback_to_tab = false,

  title = "  Git Projects",
  fuzzy = true,

  style = {
    prefix_color      = "#7aa2f7", -- the "org/" path prefix
    repo_color        = "#c0caf5", -- the repository basename (bold)
    marker_color      = "#565f89", -- the source marker
    zoxide_marker     = "󰁤 ",      -- shown for zoxide-known repos
    discovered_marker = "󰊢 ",      -- shown for fd-discovered repos
    label_segments    = 2,          -- trailing path segments to show (0 = full path)
  },

  keys = { ... }, -- see below
})
```

### Key bindings

Two binding styles are supported.

#### Prefix (key table) - default

A leader/prefix key enters a key table; the next key picks the launch mode.
By convention **lowercase = shell**, **uppercase = editor**.

```lua
keys = {
  prefix = { mods = "LEADER", key = "f", timeout_milliseconds = 2000 },

  tab_shell      = "t",  -- open in a new TAB,                       shell
  split_v_shell  = "v",  -- VERTICAL tile (new pane on the right),   shell
  split_h_shell  = "h",  -- HORIZONTAL split (new pane on bottom),   shell
  here_shell     = "f",  -- cd in the CURRENT pane,                  shell
  tab_editor     = "T",  -- open in a new TAB,                       editor
  split_v_editor = "V",  -- VERTICAL tile (new pane on the right),   editor
  split_h_editor = "H",  -- HORIZONTAL split (new pane on bottom),   editor
  here_editor    = "e",  -- cd in the CURRENT pane,                  editor
}
```

So with the defaults: `LEADER f` then `t` opens a shell tab; `LEADER f T` opens
the project in your editor in a new tab; `Escape` cancels the prefix.

#### Flat bindings

Set `prefix = false` and give each action its own full binding spec:

```lua
keys = {
  prefix = false,
  tab_shell  = { mods = "LEADER",     key = "p" },
  here_editor = { mods = "LEADER|SHIFT", key = "e" },
  -- omit any action you don't want bound
}
```

#### No automatic bindings

Set `keys = false` to register nothing and bind the actions yourself:

```lua
project_picker.apply_to_config(config, { keys = false })

config.keys = {
  {
    mods = "LEADER", key = "p",
    action = project_picker.action("tab", "shell"),
  },
  {
    mods = "LEADER", key = "P",
    action = project_picker.action("split_v", "editor"),
  },
}
```

`action(target, mode)` accepts `target ∈ {"tab","split_v","split_h","here"}`
and `mode ∈ {"shell","editor"}` and returns a WezTerm key action (an
`EmitEvent` for a stable named event, so bindings survive config reloads).

## How it works

1. **Collect** - `zoxide query -l` (frecency order) filtered to git repos, then
   a `fd` scan of `search_paths` for `.git`. Results are merged and de-duplicated;
   zoxide-ranked repos come first. (`zoxide`/`fd` are resolved through your shell
   so they're found even under a GUI's minimal PATH.)
2. **Pick** - entries are shown in a fuzzy `InputSelector`; the label is
   `org/repo`, the hidden `id` is the absolute path.
3. **Open** - the chosen path is launched per the (target, mode) of the key you
   pressed. In `editor` mode the pane runs `cd <path> && <editor>; exec <shell>`
   in an interactive login shell, so an interactive shell remains in the project
   directory when the editor exits. `here` mode types a `cd` into the current
   pane; if that pane isn't running a shell it shows a message (or opens a new
   tab if `here_fallback_to_tab = true`).
4. **Learn** - the path is added to zoxide (`zoxide add`) so it ranks higher next
   time.

## Local development

```lua
local project_picker =
  wezterm.plugin.require("file:///Users/you/git/.../git-project-picker.wezterm")
```

After editing the plugin, run `wezterm.plugin.update_all()` in the Debug Overlay
(`Ctrl+Shift+L` by default) and reload the config. See `AGENTS.md` for the full
contributor / AI-agent workflow.

### Running the tests

A deterministic, zero-install unit suite lives in `tests/` (vendored
[luaunit](https://github.com/bluebird75/luaunit) + a fake `wezterm` module, so
it needs only `lua` on your `PATH` - no luarocks, no real WezTerm, no network,
no disk access). It covers the config merge logic, label formatting, and the
finder's discovery/ordering (including regression tests for previously fixed
bugs).

```sh
mise run test     # or: lua tests/run.lua
mise run lint     # syntax-check every Lua file with luac -p
mise run check    # lint + test
```

## License

MIT - see [LICENSE](./LICENSE).
