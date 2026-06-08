# workbranch

**English** | [한국어](README.ko.md)

Manage Git worktree task spaces without memorizing `git worktree` commands.

`workbranch` creates one task folder per feature, works with one repo or many repos, and keeps branch refresh commands short and safe.

Its two core workflows are **Workspace lifecycle** for creating and removing task workspaces, and **Branch workflow** for updating, landing, and pushing task branches.

![img](./docs/figs/workbranch-git-flow.png)

## Install

### Homebrew

```bash
brew install tkhwang/tap/workbranch
```

If you prefer to add the tap first:

```bash
brew tap tkhwang/tap
brew install workbranch
```

### curl installer

```bash
curl -fsSL https://raw.githubusercontent.com/tkhwang/workbranch/main/install.sh | bash
```

Homebrew installs published releases. The curl installer tracks `main`.

## Quick start

After cloning the base worktrees, `workbranch init` asks whether to add your first task, walks through the same prompts as `workbranch add`, then finishes with IDE and terminal tool config.

### Feature flow: \_base : `main` -> feature

```bash
workbranch init

workbranch add login
# develop feat-login feature
workbranch pull              # update base
workbranch update feat-login # apply latest update from base
workbranch land feat-login   # apply feature commit to base

workbranch push
```

### Stacked flow : \_base: `feat/AAA` -> feature `feat/AAA-XXX`

```bash
workbranch init

workbranch add feat-XXX
# develop XXX feature

workbranch pull            # update base
workbranch update feat-XXX # apply latest update from base
workbranch land feat-XXX   # apply feature commit to base

workbranch add feat-YYY
# develop YYY  feature
workbranch finalize feat-YYY # same as above: pull -> update-> land

workbranch push
```

## Task identity and branch names

New task creation asks for two values:

| Prompt           | Example | Used for             |
| ---------------- | ------- | -------------------- |
| Task type        | `feat`  | Git branch prefix    |
| Task detail name | `login` | Folder/branch detail |

`workbranch` derives:

- task folder: `feat-login`
- per-repo default Git branch:
  - base `main` or `master` -> `feat/login`
  - base `feature/cpq` -> `feature/cpq-login`

Folder names and branch names stay separate because folders must be path-safe while Git branches normally use `/`. `workbranch` uses `-` as the folder-safe type/detail separator, so `feat-login` is the task-folder form of `feat/login`. Repo-specific branch prompts still let you override the default per repo.

Interactive `workbranch add <detail>` enters the same creation flow, using `<detail>` as the default Task detail name. For example, `workbranch add login` asks for Task type, shows `login` as the editable detail default, and recommends the folder `feat-login`; each repo then suggests a branch from its configured base branch. `workbranch add feat-login` remains a direct shorthand for the conventional task key. Non-interactive scripts can still pass task keys without the conventional `type-` prefix; those legacy explicit keys keep branch-prefix defaults for compatibility.

By default, `workbranch add` creates task branches from the current HEAD of your local `_base/<repo>` worktrees. It does not pull remote base branches automatically. To start from the latest remote base, run:

```bash
workbranch pull
workbranch add
```

Use `workbranch add [<task>] --from <ref>` to seed the new task branches from another source ref. For example, `workbranch add task1 --from feat/XXX` fetches origin, prefers `origin/feat/XXX` when it exists, and creates the linked task worktrees from that ref while still using the prompted task branch names. Later `workbranch status` still compares the task branch to the current local base; the source ref is creation context, not a persistent status baseline.

During active work, run `workbranch refresh` to pull remote base branches into `_base/<repo>` and then update every task workspace from those refreshed local bases. Use `workbranch refresh <task>` to refresh one task. `refresh` first checks that target task worktrees are updateable; dirty or otherwise blocked tasks stop the command before base branches are pulled.

Use `workbranch config` when you want to update project settings, base branches, IDE/terminal launch commands, or per-repo setup commands without cloning repos again. If base branches change, existing `_base/<repo>` worktrees are fetched, checked out, and fast-forward pulled to those branches. Use `workbranch config base` when you only want to update base branches.

## What it creates

For every task, `workbranch` creates linked worktrees under one shared task directory:

```text
my-app-workspace
├── .workbranch.config
├── _base
│   ├── frontend
│   └── backend
└── login
    ├── frontend
    └── backend
```

Single-repo projects use the same shape with one repo directory inside each task.

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

See the [MVP spec](docs/specs/0001-workbranch-mvp.md) for the config format and setup environment variables.

## Safety

Before changing worktrees, `workbranch` checks for dirty worktrees, wrong branches, rebase state, missing repos, and non-fast-forward Git paths.

## More docs

- [Architecture](docs/architecture.md)
- [Git operations](docs/git-operations.md)
- [MVP spec](docs/specs/0001-workbranch-mvp.md)
