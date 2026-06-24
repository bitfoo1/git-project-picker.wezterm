# git-project-picker.wezterm

A fuzzy, frecency-ranked **git project picker** for [WezTerm](https://wezterm.org).

Press a key, fuzzy-find any git repository on your machine, and open it as a
**new tab**, a **vertical/horizontal split**, or **in the current pane** —
either as a plain **shell** or by launching your **`$EDITOR`**. Every one of
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

- **Git-only** — lists directories that contain a `.git` entry (dir *or* file,
  so worktrees and submodules work).
- **Frecency** — repositories you visit often/recently float to the top, powered
  by [`zoxide`](https://github.com/ajeetdsouza/zoxide). Opening a project records
  it in zoxide so the ranking keeps improving.
- **Fresh discovery** — a [`fd`](https://github.com/sharkdp/fd) scan of your
  configured `search_paths` surfaces brand-new repos you have never `cd`'d into.
- **Fuzzy search** — native WezTerm `InputSelector` fuzzy matching.
- **Eight launch modes** — `{ tab | vertical split | horizontal split | here } ×
  { shell | editor }`, each its own key.
- **Fully configurable** — search paths, scan depth, tool paths, editor, colors,
  markers, and every key binding.

## Requirements

| Tool | Why | Required |
|------|-----|----------|
| WezTerm (recent — `InputSelector` w/ `fuzzy`) | the picker UI | yes |
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

  -- External tool paths (bare names are looked up on PATH).
  zoxide_path = "zoxide",
  fd_path     = "fd",

  -- "editor" launch mode runs: cd <project> && <editor>; exec <shell>
  editor = os.getenv("EDITOR") or "vi",
  shell  = os.getenv("SHELL") or "/bin/sh",

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

#### Prefix (key table) — default

A leader/prefix key enters a one-shot key table; the next key picks the launch
mode. By convention **lowercase = shell**, **uppercase = `$EDITOR`**.

```lua
keys = {
  prefix = { mods = "LEADER", key = "f", timeout_milliseconds = 2000 },

  tab_shell      = "t",  -- open in a new TAB,            shell
  split_v_shell  = "s",  -- open in a VERTICAL split,     shell  (left/right)
  split_h_shell  = "v",  -- open in a HORIZONTAL split,   shell  (top/bottom)
  here_shell     = "f",  -- cd in the CURRENT pane,       shell
  tab_editor     = "T",  -- open in a new TAB,            $EDITOR
  split_v_editor = "S",  -- open in a VERTICAL split,     $EDITOR
  split_h_editor = "V",  -- open in a HORIZONTAL split,   $EDITOR
  here_editor    = "e",  -- cd in the CURRENT pane,       $EDITOR
}
```

So with the defaults: `LEADER f` then `t` opens a shell tab; `LEADER f T` opens
the project in `$EDITOR` in a new tab; `Escape` cancels the prefix.

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
and `mode ∈ {"shell","editor"}` and returns a WezTerm `action_callback`.

## How it works

1. **Collect** — `zoxide query -l` (frecency order) filtered to git repos, then
   a `fd` scan of `search_paths` for `.git`. Results are merged and de-duplicated;
   zoxide-ranked repos come first.
2. **Pick** — entries are shown in a fuzzy `InputSelector`; the label is
   `org/repo`, the hidden `id` is the absolute path.
3. **Open** — the chosen path is launched per the (target, mode) of the key you
   pressed. In `editor` mode the pane runs `cd <path> && <editor>; exec <shell>`
   so an interactive shell remains in the project directory when the editor exits.
4. **Learn** — the path is added to zoxide (`zoxide add`) so it ranks higher next
   time.

## Local development

```lua
local project_picker =
  wezterm.plugin.require("file:///Users/you/git/.../git-project-picker.wezterm")
```

After editing the plugin, run `wezterm.plugin.update_all()` in the Debug Overlay
(`Ctrl+Shift+L` by default) and reload the config. See `AGENTS.md` for the full
contributor / AI-agent workflow.

## License

MIT — see [LICENSE](./LICENSE).
