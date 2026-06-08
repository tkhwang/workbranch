# Usage details

[README](../README.md) | [한국어](usage.ko.md)

## Platform support

Core workbranch commands are supported on macOS, Linux, and WSL. Tool app launchers are macOS-only because the built-in app presets use macOS `open` and macOS app names.

Supported everywhere: Git/worktree commands, `path`, `list`, `status`, `config`, `init`, and generated CLI distribution checks.

macOS-only: `finder`, `ide`, `terminal`, `config ide`, and `config terminal`. On Linux/WSL, full `workbranch config` and `workbranch init` stay available and skip tool app prompts.

## Common commands

### Workspace lifecycle

| Command                                  | Use it to                                                                    |
| ---------------------------------------- | ---------------------------------------------------------------------------- |
| `workbranch init`                        | Create or clone base worktrees from config                                   |
| `workbranch config`                      | Edit project settings, base branches, tool commands, and repo setup commands |
| `workbranch config base`                 | Update only base branch settings and checkout base worktrees                 |
| `workbranch config ide`                  | Update only the configured IDE command                                       |
| `workbranch config terminal`             | Update only the configured terminal command                                  |
| `workbranch add [<task>] [--from <ref>]` | Create a task workspace                                                      |
| `workbranch list`                        | Show repos and task workspaces                                               |
| `workbranch remove <task>`               | Remove task worktrees and local task branches                                |
| `workbranch doctor [--fix]`              | Diagnose project health; `--fix` prunes stale worktree registrations only    |

### Branch workflow

| Command                    | Use it to                                            |
| -------------------------- | ---------------------------------------------------- |
| `workbranch status`        | Show base remote diff, task diff, and dirty state    |
| `workbranch pull`          | Pull remote base branches into `_base/<repo>`        |
| `workbranch update [task]` | Rebase task worktrees onto local base (`git rebase <_base/repo HEAD>`) |
| `workbranch push`          | Push base branches                                   |
| `workbranch push <task>`   | Push task branches                                   |
| `workbranch land <task>`   | Fast-forward task work back into local base branches |

### Combined flow

| Command                      | Use it to                                                                  |
| ---------------------------- | -------------------------------------------------------------------------- |
| `workbranch refresh`         | Pull base branches, then update every task workspace                       |
| `workbranch refresh <task>`  | Pull base branches, then update one task workspace                         |
| `workbranch finalize <task>` | Pull base branches, update one task, then land it into local base branches |
| `workbranch prune`           | Remove clean task workspaces already merged into local base branches       |

### Tool commands

| Command                      | Use it to                                           |
| ---------------------------- | --------------------------------------------------- |
| `workbranch path <task>`     | Print a task workspace or repo path                 |
| `workbranch finder <task>`   | Open the task workspace folder in Finder            |
| `workbranch ide <task>`      | Open task repo worktrees in the configured IDE      |
| `workbranch terminal <task>` | Open task repo worktrees in the configured terminal |

### Other

| Command         | Use it to                  |
| --------------- | -------------------------- |
| `workbranch -v` | Show the installed version |

Add `--repo <repo>` to supported Branch workflow and Tool commands when you want to operate on one repo only.

## CLI display

In an interactive terminal, `workbranch` uses color, a compact banner on help/init screens, and section titles to make command output easier to scan. Captured or piped output stays plain by default so scripts and tests do not receive ANSI escape sequences.

Color controls:

```bash
NO_COLOR=1 workbranch help              # always plain
WORKBRANCH_COLOR=never workbranch help  # always plain
WORKBRANCH_COLOR=always workbranch help # force enhanced display
```

`workbranch path <task>` and `workbranch path <task> --repo <repo>` remain plain path-only outputs for scripting.

## Project health

Run `workbranch doctor` to diagnose base worktree drift, partial task workspaces, stale task directories, and stale Git worktree registrations. It is read-only by default and exits non-zero when it finds issues, so it can be used in local checks or CI.

Use `workbranch doctor --fix` for the safe repair path. It only runs `git worktree prune` for in-scope base repos; it never deletes task directories or branches. For destructive cleanup, follow the printed `workbranch remove <task>` or `workbranch remove <task> --force` hint yourself. Add `--repo <repo>` to scope diagnosis and pruning to one repo.

## Shell completion

Generate shell completion scripts with `workbranch completion <shell>`. The script provides command, task key, repo, and option completion through your shell; display color and dimmed preview styling are controlled by your shell, completion framework, and terminal theme.

```bash
# bash
workbranch completion bash > ~/.local/share/bash-completion/completions/workbranch

# zsh: write to a directory on fpath
workbranch completion zsh > "${fpath[1]}/_workbranch"

# fish
workbranch completion fish > ~/.config/fish/completions/workbranch.fish
```

## Opening task workspaces

Configure one IDE and one terminal command for the project:

```bash
workbranch config ide
workbranch config terminal
```

Then open every repo in a task workspace:

```bash
workbranch finder login
workbranch ide login
workbranch terminal login
```

Built-in macOS IDE presets open each repo path in a separate IDE window for VS Code-like apps. The config directive is `IDE <command>`; preset order is Cursor, Antigravity, Windsurf, Zed, Sublime Text, Xcode, then VS Code. Existing `IDE open -a Cursor`, `IDE open -a "Antigravity IDE"`, `IDE open -a "Visual Studio Code"`, or `IDE open -a Windsurf` command shapes are launched as `open -na ... --args --new-window` for the same behavior. Zed remains `open -na Zed` until its CLI contract is verified.

Limit to one repo when needed:

```bash
workbranch ide login --repo frontend
workbranch terminal login --repo backend
```

Print full paths for scripting:

```bash
workbranch path login
workbranch path login --repo frontend
```

Launcher commands run repo-by-repo. Commands that keep running in the foreground, such as a raw TUI terminal command, should use `--repo` or a custom non-blocking wrapper.

## Setup commands

`workbranch config` can store a setup command per repo. When you run `workbranch add <task>`, each setup command runs inside `<task>/<repo>`.

See the [MVP spec](specs/0001-workbranch-mvp.md) for the config format and setup environment variables.

## Safety

Before changing worktrees, `workbranch` checks for dirty worktrees, wrong branches, rebase state, missing repos, and non-fast-forward Git paths.
