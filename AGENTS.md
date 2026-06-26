# AGENTS.md

Guidance for AI agents (and humans) working on **git-project-picker.wezterm**.
Read this before making changes so your work matches the established style.

## Writing rules (MANDATORY)

- NEVER use em-dashes (the long " - " character) or en-dashes (" - "). Not in code,
  comments, docs, commit messages, or chat. Always use a regular hyphen "-"
  (optionally surrounded by spaces: " - "). This applies everywhere, without
  exception.

## What this project is

A WezTerm plugin: a fuzzy, frecency-ranked picker for git repositories that can
open a project as a tab / split / current pane, in shell or editor mode.
It is distributed as a git repo and loaded via `wezterm.plugin.require`.

## Repository layout

```
plugin/
  init.lua                      -- entry point; sets package.path, named events, exports apply_to_config
  git-project-picker/
    config.lua                  -- option defaults + deep_merge (M.resolve)
    finder.lua                  -- zoxide + fd discovery, tool resolution, git filtering, frecency order
    style.lua                   -- entry -> styled InputSelector choice
    picker.lua                  -- show() the picker, open() the selection
tests/                          -- deterministic, zero-install unit suite (see below)
mise.toml                       -- dev tasks: lint / test / check
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
  - config.resolve(opts)               -> resolved options table (M.options)
  - register_handlers()                -> one wezterm.on per (target, mode) [once]
  - register_keys(config, opts.keys)   -> binds keys to M.action(target, mode)

key press -> EmitEvent "git-project-picker.<target>.<mode>"
          -> wezterm.on handler -> picker.show(window, pane, target, mode, opts)
  - finder.projects(opts)   -> { {path, source}, ... }  (zoxide-first, deduped)
  - style.choices(entries)  -> { {id=path, label=fmt}, ... }
  - InputSelector (fuzzy)   -> picker.open(...)
       - foreground_is_shell check for "here" target
       - finder.touch(opts, path)   -> zoxide add
       - spawn tab / split / send_text to current pane
```

Keep these responsibilities separated:
- **config.lua** owns defaults and merge semantics. No I/O.
- **finder.lua** owns all external-process and filesystem work. Must degrade
  gracefully (never raise) if `zoxide`/`fd` are missing.
- **style.lua** owns presentation only. Pure functions, no I/O.
- **picker.lua** owns WezTerm window/pane side effects.
- **init.lua** owns wiring, package.path, named events, and the public API.

## Conventions

- **Lua style**: 2-space indent, `local M = {}` module pattern returning `M`.
- **Doc comments**: use `---@param` / `---@return` annotations on public functions.
- **Splits**: `split_v` = vertical tile = left/right (new pane `Right`);
  `split_h` = horizontal split = top/bottom (new pane `Bottom`). Do not swap
  these meanings.
- **Default keys**: lowercase = shell mode, uppercase = editor mode.
  `t`/`T` = tab, `v`/`V` = split_v (new pane right), `h`/`H` = split_h (new
  pane bottom), `f` = here (shell), `e` = here (editor). See config.lua `keys`
  for the exact mapping; keep README in sync.
- **No new runtime deps** beyond `fd` and `zoxide`. Everything else must be
  pure Lua + the WezTerm API.
- **External commands** must go through `wezterm.run_child_process` wrapped so a
  failure logs a warning and returns empty, never aborting the picker.
- **Shell safety**: any path interpolated into a shell command string must be
  quoted with `wezterm.shell_quote_arg` (see `picker.q`).
- **README is part of the contract**: if you add/rename/remove an option in
  `config.lua`, update the corresponding section in `README.md` in the same change.

## Hard-won knowledge (read before debugging)

These are real issues hit during development. Do not regress them.

### 1. Key actions MUST use stable named events, not anonymous callbacks

`wezterm.action_callback` returns an action with an auto-generated
`user-defined-N` id. Those ids are assigned in registration order and **desync
across config reloads**: after a few `SHIFT+CTRL+r` reloads, a key bound to one
callback starts firing a different one (symptom: "T opens a bottom split", keys
feel scrambled).

Fix in place: `init.lua` registers one `wezterm.on("git-project-picker.<target>.<mode>", ...)`
handler per action (guarded by `handlers_registered`), and `M.action` returns
`wezterm.action.EmitEvent(event_name(target, mode))`. Event names are
deterministic strings, so bindings survive reloads. Keep it this way.

### 2. Uppercase letter keys need `mods = "SHIFT"`

In a key table, an entry `{ key = "T" }` has implicit `mods = "NONE"` and will
NEVER match, because the OS emits Shift+t as key `"T"` WITH `mods = "SHIFT"`.
`register_keys` detects single uppercase-letter keys and sets `mods = "SHIFT"`.
Note: `wezterm show-keys --lua` cosmetically prints these as `mods = 'NONE'`
even when SHIFT is set - verify the real value by dumping `config.key_tables`
in a headless run, not via show-keys.

### 3. GUI WezTerm has a minimal PATH (no mise/asdf)

When launched from Finder/dock, WezTerm does not inherit your shell PATH, so a
bare `zoxide`/`fd` fails to spawn and discovery silently returns 0 entries
(symptom: picker "does nothing", no overlay). `finder.resolve_tool` resolves a
bare tool name to an absolute path by asking the user's shell
(`<shell> -lc`, then `-ic`, then `-ilc` - mise may be activated in interactive
rc files, not login profiles), and caches the result. Keep that multi-attempt
fallback.

### 4. Editor mode runs in an interactive login shell

`editor` is an explicit config option (NOT read from `$EDITOR`, which GUI
terminals often lack). `editor_argv` runs `cd <path> && <editor>; exec <shell> -i`
via `<shell> -ilc` so PATH and shell aliases (e.g. `vi` aliased to `nvim`)
resolve. A non-interactive shell would launch the wrong/real binary.

### 5. "here" mode is only safe when a shell is in the foreground

`here` types a `cd` line into the current pane. If the foreground process is an
editor/REPL/pager, that types garbage into it. `picker.foreground_is_shell`
checks `pane:get_foreground_process_name()` against
`opts.here_shell_processes`. When it is not a shell:
- `opts.here_fallback_to_tab == false` (default): show an explanatory toast and
  do nothing.
- `opts.here_fallback_to_tab == true`: open a new tab instead.
If the process name cannot be determined, assume shell (best effort).

## Verifying changes

There is no network test harness; verify locally. There is now a deterministic,
zero-install unit-test suite under `tests/` (see "Test suite" below) - run it
after every change.

1. **Run the test suite** (covers config merge, style formatting, and finder
   discovery logic, including regression tests for the fd stray-`.` bug and the
   `search_paths = {}` merge bug):
   ```sh
   mise run test          # or: lua tests/run.lua
   ```
2. **Syntax-check + test in one go**:
   ```sh
   mise run check         # = lint (luac -p every file) + test
   ```
   `mise run lint` alone just syntax-checks every Lua file with `luac -p`.
3. **Verify key wiring headlessly**: dump `config.key_tables.git_project_picker`
   (and the EmitEvent names) from a `wezterm --config-file ... show-keys` run
   with a probe config, to confirm key -> target/mode mapping. Do not trust the
   `mods` field shown by `show-keys --lua` (see knowledge item 2). This is the
   one area the unit suite cannot cover (it needs the live WezTerm runtime).
4. **Manual smoke test**: load via a `file://` URL in your WezTerm config,
   reload (`SHIFT+CTRL+r`), and exercise each launch mode. For fast iteration on
   a `file://` install you can copy the working tree straight into the cloned
   plugin dir (find it via `wezterm.plugin.list()`), then just reload - no
   commit needed. `wezterm.plugin.update_all()` only syncs COMMITTED state.

Always run at least steps 1-2 before claiming a change works.

### Test suite

```
tests/
  luaunit.lua     -- vendored luaunit v3.4 (BSD-licensed); zero-install runner
  helpers.lua     -- controllable fake `wezterm` + fresh-require helper
  run.lua         -- entry point: lua tests/run.lua (one process, one summary)
  test_config.lua -- config.resolve / deep_merge semantics
  test_style.lua  -- split_label + format_choice (pure)
  test_finder.lua -- discovery, tool resolution, ordering + regressions
```

How it stays deterministic: the suite never touches the real network, clock, or
disk and never spawns a real process. `tests/helpers.lua` installs a fake
`wezterm` module (via `package.loaded`) whose `run_child_process` and `glob` are
driven by per-test fixtures, so a given input always yields the same output -
change a module and re-run to see exactly what moved.

This supersedes the older guidance that `finder` "cannot be unit-tested": by
injecting `run_child_process`/`glob` through the mock, finder's discovery logic
(argv construction, zoxide-first dedup, graceful degradation) is now fully and
deterministically testable WITHOUT the live WezTerm API. Add a test alongside
any finder/config/style change. The two fixed bugs each have a dedicated
regression test - `TestFromFd.test_fd_argv_has_no_stray_dot` and
`TestConfig.test_empty_search_paths_clears_default` - so they cannot silently
return.

## Gotchas

- `wezterm.plugin.list()` URLs differ between `https://` and `file://` installs;
  `init.lua` matches on the repo-name substring, not an exact URL. Preserve that.
- `is_git_repo` matches `.git` as a **dir or file** (worktrees/submodules use a
  `.git` file). Keep the glob `<dir>/.git`, not `<dir>/.git/`.
- The fd scan uses `--prune` so it stops descending once a repo is found; do not
  remove it or nested `.git` dirs inside repos will appear.
- `here` mode cannot change an existing pane's cwd directly - it sends a `cd`
  command line to the running shell. That is intentional.

## Commit conventions

This repo follows conventional commits with gitmoji, e.g.:

```
feat(picker): :sparkles: add option to open project in a new window
fix(finder): :bug: handle search paths that do not exist
docs(readme): :memo: document flat key binding mode
```

Do not commit unless explicitly asked.
