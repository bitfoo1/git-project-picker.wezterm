# AGENTS.md

Guidance for AI agents (and humans) working on **git-project-picker.wezterm**.
Read this before making changes so your work matches the established style.

## What this project is

A WezTerm plugin: a fuzzy, frecency-ranked picker for git repositories that can
open a project as a tab / split / current pane, in shell or `$EDITOR` mode.
It is distributed as a git repo and loaded via `wezterm.plugin.require`.

## Repository layout

```
plugin/
  init.lua                      -- entry point; sets package.path, exports apply_to_config
  git-project-picker/
    config.lua                  -- option defaults + deep_merge (M.resolve)
    finder.lua                  -- zoxide + fd discovery, git filtering, frecency order
    style.lua                   -- entry -> styled InputSelector choice
    picker.lua                  -- show() the picker, open() the selection
README.md                       -- user-facing docs (keep in sync with config.lua)
AGENTS.md                       -- this file
LICENSE                         -- MIT
```

WezTerm requires the entry point at **`plugin/init.lua`** and it must export an
`apply_to_config` function. Sub-modules live under `plugin/git-project-picker/`
and are loaded with the dotted name `require("git-project-picker.<mod>")` after
`init.lua` adds the plugin dir to `package.path`.

## Architecture / data flow

```
apply_to_config(config, opts)
  └─ config.resolve(opts)               -> resolved options table
  └─ register_keys(config, opts.keys)   -> binds keys to M.action(target, mode)

key press -> M.action(target, mode) -> picker.show(window, pane, target, mode, opts)
  └─ finder.projects(opts)   -> { {path, source}, ... }  (zoxide-first, deduped)
  └─ style.choices(entries)  -> { {id=path, label=fmt}, ... }
  └─ InputSelector (fuzzy)   -> picker.open(...)
       └─ finder.touch(opts, path)   -> zoxide add
       └─ spawn tab / split / send_text to current pane
```

Keep these responsibilities separated:
- **config.lua** owns defaults and merge semantics. No I/O.
- **finder.lua** owns all external-process and filesystem work. Must degrade
  gracefully (never raise) if `zoxide`/`fd` are missing.
- **style.lua** owns presentation only. Pure functions, no I/O.
- **picker.lua** owns WezTerm window/pane side effects.
- **init.lua** owns wiring, package.path, and the public API.

## Conventions

- **Lua style**: 2-space indent, `local M = {}` module pattern returning `M`.
- **Doc comments**: use `---@param` / `---@return` annotations on public functions.
- **Splits**: `split_v` = vertical = left/right (new pane `Right`); `split_h` =
  horizontal = top/bottom (new pane `Bottom`). Do not swap these meanings.
- **Key convention**: lowercase action key = shell mode, uppercase = editor mode.
- **No new runtime deps** beyond `fd` and `zoxide`. Everything else must be
  pure Lua + the WezTerm API.
- **External commands** must go through `wezterm.run_child_process` wrapped so a
  failure logs a warning and returns empty, never aborting the picker.
- **Shell safety**: any path interpolated into a shell command string must be
  quoted with `wezterm.shell_quote_arg` (see `picker.q`).
- **README is part of the contract**: if you add/rename/remove an option in
  `config.lua`, update the corresponding section in `README.md` in the same change.

## Verifying changes

There is no network test harness; verify locally.

1. **Syntax check every file**:
   ```sh
   for f in plugin/init.lua plugin/git-project-picker/*.lua; do
     luac -p "$f" && echo "OK $f"
   done
   ```
2. **Unit-test pure logic** (config merge, label splitting) by stubbing the
   `wezterm` global via `package.preload["wezterm"]`, then `require` the pure
   modules (`config`, `style`) and assert. Do **not** require `finder`/`picker`
   in unit tests — they touch the live WezTerm API and external processes.
3. **Manual smoke test**: load via a `file://` URL in your WezTerm config, run
   `wezterm.plugin.update_all()` in the Debug Overlay, reload, and exercise each
   of the eight launch modes.

Always run at least steps 1–2 before claiming a change works.

## Gotchas

- `wezterm.plugin.list()` URLs differ between `https://` and `file://` installs;
  `init.lua` matches on the repo-name substring, not an exact URL. Preserve that.
- `is_git_repo` matches `.git` as a **dir or file** (worktrees/submodules use a
  `.git` file). Keep the glob `<dir>/.git`, not `<dir>/.git/`.
- The fd scan uses `--prune` so it stops descending once a repo is found; do not
  remove it or nested `.git` dirs inside repos will appear.
- `here` mode cannot change an existing pane's cwd directly — it sends a `cd`
  command line to the running shell. That is intentional.

## Commit conventions

This repo follows conventional commits with gitmoji, e.g.:

```
feat(picker): :sparkles: add option to open project in a new window
fix(finder): :bug: handle search paths that do not exist
docs(readme): :memo: document flat key binding mode
```

Do not commit unless explicitly asked.
