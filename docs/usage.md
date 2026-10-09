# Usage details

[README](../README.md) | [한국어](usage.ko.md)

## Platform support

Core workbranch commands are supported on macOS, Linux, and WSL. Tool app launchers are macOS-only because the built-in app presets use macOS `open` and macOS app names.

Supported everywhere: Git/worktree commands, `path`, `list`, `memo`, `noti`, `status`, `config`, `init`, and generated CLI distribution checks.

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
| `workbranch config language`             | Update preferred language for generated task guidance                        |
| `workbranch add [<task>] [--from <ref>]` | Create a task workspace                                                      |
| `workbranch list [--json]`               | Show repos and task workspaces; `--json` emits the companion-facing contract |
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
| `workbranch stash [-m <msg>]` | Set aside the current worktree's changes under its branch |
| `workbranch stash pop`     | Restore the current branch's saved changes           |

`git stash` keeps one stash list for every worktree of a repo, so a bare `git stash pop` can restore another worktree's entry. `workbranch stash` runs in the current worktree and stores tracked, staged, and untracked changes under `refs/workbranch/stash-v2/<encoded-branch>` without touching the shared list. `pop` and `apply` only restore the current branch's slot unless `--branch <branch>` is given; `list`, `show [-p]`, and `drop` inspect or discard slots. Each branch holds one slot at a time.

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
| `workbranch terminal <task>` | Open the task root in the configured terminal       |

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

## Agent runtime and migration

`workbranch add` creates workspace guidance and metadata, without a task brief. Agents do not manually report status. A bundled Rust collector writes hook observations to `~/.workbranch/runtime/state.sqlite3` without a DB server, Node, or the sqlite3 CLI. `workbranch runtime --json` reads the latest sessions without refreshing Git. `list --json` uses schema 2; update CLI and Companion together.

Install one or both providers with `workbranch hooks install --provider claude` / `--provider codex` / `--provider grok`. Review native hook trust and restart agent sessions. `hooks status` delegates to the provider manager; first observed events confirm collection. `hooks uninstall` removes only the selected plugin.

Run `workbranch migrate agent-runtime --dry-run --global` to inspect legacy files/instructions and `--apply --global` to remove them. Companion detects the same migration and runs the CLI when you select migration. Existing `memo`, `done`, and Plan archive prompts are removed. Ordinary repository Plan documents remain independent. Migration does not synthesize runtime state from old briefs.

Notifications remain at `<task>/.workbranch/notifications.jsonl`; `noti add|list|clear` and `notiCount` are unchanged.

`workbranch remove <task>` removes task worktrees, local task branches, and known generated task-root state: `TASK-WORKBRANCH.md`, generated `AGENTS.md`, `.workbranch/`, and `.workbranch.task`. Everything else left in the task root, including `.omx/` and `.omc/`, is not git-managed. Normal remove prints those remaining item names and, in an interactive shell, asks once whether to delete the entire task root. No/EOF keeps the task root. `workbranch remove <task> --force` still runs the normal safety preflights, then deletes the task root without prompting.

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

Configure one IDE and one terminal command for the project, and optionally the language used by generated task guidance:

```bash
workbranch config ide
workbranch config terminal
workbranch config language
```

Then open task surfaces:

```bash
workbranch finder login      # task root in Finder
workbranch ide login         # repo worktrees in the IDE
workbranch terminal login    # task root in the terminal
```

Built-in macOS IDE presets open each repo path in a separate IDE window for VS Code-like apps. The config directive is `IDE <command>`; preset order is Cursor, Antigravity, Windsurf, Zed, Sublime Text, Xcode, then VS Code. For the VS Code-like presets (Cursor, Antigravity, Windsurf, VS Code), `workbranch ide` runs the CLI bundled inside the installed app (`<App>.app/Contents/Resources/app/bin/<cli>`, looked up under `/Applications` and then `~/Applications`) as `<cli> --new-window <repo-path>`. When that IDE is already running, `open -a <App>.app` then brings it to the front once the CLI's short-lived helper instance has exited, because that helper hands macOS focus back to the caller and focusing a repo window that is already the IDE's key window does not bring the app forward on its own. A repo that is already open is focused in its existing window and the IDE comes to the front; a repo that is not open gets a new window; an IDE that is not running is launched. This path waits for the bundled CLI and confirms the activation, so `workbranch ide` takes roughly three to four seconds per repo before it returns; the repo window itself appears within about a second. When the bundled CLI is not found or not executable, the configured `open -na ... --args --new-window` command runs instead. Existing `IDE open -a Cursor`, `IDE open -a "Antigravity IDE"`, `IDE open -a "Visual Studio Code"`, or `IDE open -a Windsurf` command shapes are normalized the same way. Zed remains `open -na Zed` until its CLI contract is verified.

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

`workbranch ide <task>` runs repo-by-repo. `workbranch terminal <task>` opens the task root once so an agent can see `AGENTS.md`, and all repos. Use `--repo` when you intentionally want either launcher scoped to one repo.

## Setup commands

`workbranch config` can store a setup command per repo. When you run `workbranch add <task>`, each setup command runs inside `<task>/<repo>`.

See the [MVP spec](specs/0001-workbranch-mvp.md) for the config format and setup environment variables.

## Safety

Before changing worktrees, `workbranch` checks for dirty worktrees, wrong branches, rebase state, missing repos, and non-fast-forward Git paths.

When a preflight detects a rebase conflict, diverged pull path, or non-fast-forward land path, it stops before changing the target worktree and prints the manual commands for that exact repo. The guidance may tell you to inspect moved refs with `git fetch` and `git log --left-right`, or to run `workbranch update <task> --repo <repo>` before landing. Resolve the conflict or non-fast-forward state outside `workbranch`, then rerun the original `workbranch` or `workbranch land` command.


## Companion installation and agent connections

Install the Companion using `brew install --cask tkhwang/tap/workbranch-companion`. First-run onboarding and Settings share the same installation and connection controls.

Install CLI runs `brew install tkhwang/tap/workbranch` to install both the CLI and collector. Update/repair target that formula only; an existing standalone CLI without a formula is routed through Homebrew installation first. The panel shows the version and actual selected path.

Connect Claude Code, Codex or Grok Build individually. Agent installation and account sign-in are separate. Review native hook trust and restart existing sessions. Configured hooks and observed events are distinct; old receipts do not verify a reconnection. The installation screen works even without a CLI. No installation or connection changes occur before a button is selected.

For direct CLI usage, use `workbranch hooks install --provider claude|codex|grok`. A development checkout selects its local plugin source, or pass `--source <checkout>`. Connecting registers the collector at `~/.workbranch/runtime/hook-collector` so GUI PATH differences do not break hooks. This is automatically managed executable metadata, not an agent-maintained status document.


Grok plugin installation requires explicit trust. Companion first shows the source and execution permissions; only selecting Trust and install applies `--trust` to that approved source. CLI users can inspect the target with `workbranch hooks describe --provider grok`, then explicitly run `workbranch hooks install --provider grok --trust` if they trust it. No automatic approval or cross-provider trust is applied.
