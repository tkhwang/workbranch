# 0001 Workbranch MVP Spec

## Goal

Workbranch creates AI-friendly task workspaces for one repo or many independent Git repositories.

It keeps every repo as a normal Git repo, then uses `git worktree` so one task folder can contain linked worktrees for all configured repos.

```text
fullstack
├── .workbranch.config
├── _base
│   ├── frontend
│   └── backend
└── login
    ├── frontend
    └── backend
```

Run the AI agent from the task folder:

```bash
cd fullstack/login
codex
```

## Config

The config file is `.workbranch.config` in the project root.

```text
PROJECT_NAME fullstack
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature
EDITOR open -na Cursor --args --new-window
TERMINAL open -a Warp
TASK_SETUP sh scripts/workbranch-setup.sh

REPO frontend git@github.com:example/frontend.git master
REPO backend git@github.com:example/backend.git feature/cpq

REPO_SETUP frontend pnpm install
REPO_SETUP backend ./gradlew dependencies
```

Format:

```text
EDITOR <command>
TERMINAL <command>
TASK_SETUP <command>
REPO <name> <git-url> <base-repo-branch>
REPO_SETUP <repo> <command>
```

Rules:

- `PROJECT_NAME` must be a safe directory name.
- `MAIN_WORKTREES_DIR` must be a safe directory name.
- `BRANCH_PREFIX` is retained for compatibility and as the default branch prompt prefix. New interactive setup asks for the default task branch prefix and writes the selected value.
- `EDITOR` is optional. It stores one project-level editor launch command text after the directive.
- `TERMINAL` is optional. It stores one project-level terminal launch command text after the directive.
- `TASK_SETUP` is optional. It stores one project-level command text after the directive.
- `REPO` requires name, URL, and base repo branch.
- `REPO_SETUP` is optional. It references an existing repo name and stores one repo-level command text after the repo name.
- Repo names must be unique safe names.
- Git URLs and branch names must be non-empty and contain no whitespace.
- Config values are split on whitespace except `EDITOR`, `TERMINAL`, `TASK_SETUP`, and `REPO_SETUP`, which preserve command text.
- The file is not a shell script.
- Safety: `.workbranch.config` is trusted project configuration. Running `workbranch add <task>` executes configured setup commands with `sh -c`; running `workbranch editor <task>` or `workbranch terminal <task>` executes configured tool commands with the resolved repo path appended. Review configs from untrusted projects before running those commands.

## Branch names

Task folder names and Git branch names are separate values.

`workbranch add <task>` uses `<task>` as the workspace folder name, then prompts for each repo's task branch. Press Enter to accept the default branch name.

```text
base repo branch master       + task login + default prompt      -> feature/login
base repo branch feature/cpq  + task task1 + default prompt      -> feature/cpq-task1
base repo branch feat/cpq     + task task1 + default prompt      -> feat/cpq-task1
base repo branch master       + task login + override tk/login   -> tk/login
```

Rule:

- If the base repo branch starts with `feature/`, `feat/`, or the configured legacy `<BRANCH_PREFIX>/`, the default task branch is `<base-branch>-<task>`.
- Otherwise, the default task branch is `<BRANCH_PREFIX>/<task>`, with `feature` used when no prefix is configured.
- Chosen branches are validated with `git check-ref-format --branch`; whitespace is not supported.
- Chosen branches are persisted in `<task>/.workbranch.task` as `REPO_BRANCH <repo> <branch>` lines so later commands use the real branch.
- Existing task workspaces without metadata keep working by falling back to the current task worktree branch, then the default rule.

Git operation internals are defined in [`docs/git-operations.md`](../git-operations.md).

## Commands

### `workbranch config`

Create or update config without cloning repos.

If `.workbranch.config` or legacy `.tasktree.config` / `.monotree.config` already exists in the current project, load it, then prompt for the project name, main worktrees directory, editor command, terminal command, each repo's base branch, and each repo-level setup command. Press Enter to keep the current value. Type `--clear` at a tool or repo setup prompt to remove that command.

Changing a repo base branch updates config only. `workbranch config` does not clone, move, rename, or check out existing worktrees. Existing `BRANCH_PREFIX` values are preserved silently; it is no longer an interactive setting. Changing `MAIN_WORKTREES_DIR` is allowed only before base worktrees exist. Once matching base worktrees exist, `workbranch config` rejects that change.

Existing project-level `TASK_SETUP` values remain supported for `workbranch add` and are preserved by `workbranch config` unless another explicit flow clears or migrates them. `workbranch config editor` and `workbranch config terminal` update only the matching tool command.

When a base branch changes after repos are cloned, `workbranch config` only updates `.workbranch.config`. It then prints the checkout/fetch/pull procedure needed for the existing `_base/<repo>` worktree.

### `workbranch config --rewrite`

Rewrite `.workbranch.config` or legacy `.tasktree.config` / `.monotree.config` to the current `.workbranch.config` format without prompts and without cloning repos.

If no config exists, run interactive config setup:

1. Ask for target directory, default `.`.
2. Ask for project name, default `fullstack`.
3. Ask for main worktrees directory, default `_base`.
4. Ask for the default task branch prefix, defaulting to `feature`, and write `BRANCH_PREFIX <prefix>`.
5. Ask for optional editor and terminal commands from presets or custom input.
6. Explain that each repo base repo branch is checked out in `_base/<repo>` and task branch names are prompted by `workbranch add`.
7. Ask for one or more repos: name, Git URL, base branch for this repo, and optional repo-level setup command.
8. Write `.workbranch.config`.

### `workbranch init`

Initialize main worktrees from config.

- If `.workbranch.config` exists in the current directory, read it and clone each repo into `_base/<repo>` on its base repo branch. Legacy `.tasktree.config` / `.monotree.config` are also accepted by `workbranch init` and can be rewritten with `workbranch config`.
- If `.workbranch.config` does not exist, run the same interactive setup as `workbranch config`, then clone repos.
- If cloning fails, remove paths created by the failed command.

### `workbranch path <task>`

Print the absolute task workspace path. With `--repo <repo>`, print the absolute path for one task repo worktree. This command writes only the path to stdout so it can be used in scripts. It never emits the banner, section titles, or ANSI color controls.

### CLI display and color

Interactive terminal output may use ANSI color, a compact help/init banner, and section markers for readability. Non-TTY output is plain by default. `NO_COLOR` disables ANSI/color/banner enhancement and takes precedence over `WORKBRANCH_COLOR=always`. `WORKBRANCH_COLOR` accepts `auto`, `always`, or `never`.

Examples in this spec show the plain output shape. Enhanced terminal output may render section headings with `➤` and color status labels, but command semantics and machine-sensitive outputs such as `workbranch path` remain unchanged.

### `workbranch editor <task>` / `workbranch terminal <task>`

Run the configured editor or terminal command once per matching task repo worktree. The resolved repo path is appended as the final argument. With `--repo <repo>`, run only for that repo. Tool launchers do not modify repositories.

Built-in macOS editor app presets use `open -n` plus `--args --new-window` so each matching repo path opens in a separate editor window instead of being folded into an existing workspace. Legacy configs that still contain `open -a Cursor`, `open -a "Antigravity IDE"`, `open -a "Visual Studio Code"`, `open -a Windsurf`, or `open -a Zed` are normalized to the matching `open -na ... --args --new-window` command at launch time.

### `workbranch list`

Show configured repos, base branches, current branches, and task workspaces.

### `workbranch status`

Show commit position, clean/dirty state, and the next suggested action for task worktrees.

```text
[*] Base worktrees
    repo        branch           commit     status
    frontend    master           a1b2c3d4e  clean
    backend     master           f6e7d8c9a  untracked

[*] Task workspaces
[*] login
    repo        base       task       diff  status    next
    frontend    a1b2c3d4e  f6e7d8c9a  +3    clean     land
    backend     a1b2c3d4e  a1b2c3d4e  0     modified  -

[*] Next
    land    task has commits not in base: workbranch land <task>
    update  task is behind base: workbranch update <task>
```

### `workbranch add <task>`

Create one task workspace with one linked worktree per repo.

For each repo:

1. Ensure `_base/<repo>` exists and is clean.
2. Show the repo's configured base branch, then prompt for the task branch name, defaulting from the branch naming rule above.
3. Fail if the chosen local or remote task branch already exists. Local task branches can be deleted with `workbranch remove <task>` before adding again; remote-only task branches must be deleted or renamed outside workbranch.
4. Create the task directory and write `<task>/.workbranch.task`.
5. Create a new local task branch from the base branch.
6. Create a linked worktree at `<task>/<repo>`.
7. Run configured repo-level setup commands. If no repo setup ran and the operation is not repo-filtered, run project-level `TASK_SETUP` when configured.

If any repo fails, roll back paths and branches created by the command.
If any setup command fails, keep created worktrees and tell the user the exact failed setup context, setup directory, and setup command. The user can fix setup with `workbranch config`, then rerun the command shown in the failure output or remove and add the task again.

The project-level setup command runs from the project root with these environment variables:

```text
WORKBRANCH_PROJECT_ROOT
WORKBRANCH_TASK
WORKBRANCH_TASK_DIR
WORKBRANCH_BASE_DIR
WORKBRANCH_REPOS
```

Repo-level setup commands run from `<task>/<repo>` with the same variables plus:

```text
WORKBRANCH_REPO
WORKBRANCH_REPO_DIR
WORKBRANCH_BASE_REPO_DIR
```

Safety: `.workbranch.config` is trusted project configuration. Setup commands are executed with `sh -c`.

### `workbranch pull`

Update base worktrees from remote base branches.

For each repo:

```bash
cd _base/<repo>
git pull --ff-only origin <base-branch>
```

Fails if any base worktree is dirty.

### `workbranch update`

Update every task worktree from its local base worktree.

For each task and repo:

```bash
cd <task>/<repo>
git rebase <_base/repo HEAD>
```

Fails if any target task worktree is dirty.
Fails if any matching base worktree is not checked out to the configured base branch.
Fails if any matching base worktree has a rebase in progress.

### `workbranch update <task>`

Same as `workbranch update`, but only for one task workspace.

### `workbranch push`

Push base branches to origin.

For each repo:

```bash
cd _base/<repo>
git push origin <base-branch>
```

### `workbranch push <task>`

Push task branches to origin.

For each repo in the task:

```bash
cd <task>/<repo>
git push -u origin <task-branch>
```

### `workbranch land <task>`

Land task branches into base branches. This must not create merge commits.

For each repo:

```bash
cd _base/<repo>
git checkout <base-branch>
git pull --ff-only origin <base-branch>
git merge --ff-only <task-branch>
```

This is useful when the base repo branch is already a parent feature branch, such as `feature/cpq`. Run `workbranch push` afterward to push the updated base repo branch.

### `--repo <repo>`

Git and tool operations default to every configured repo. Add `--repo <repo>` to limit the operation to one repo.

Examples:

```bash
workbranch pull --repo frontend
workbranch update --repo frontend
workbranch update login --repo frontend
workbranch push --repo frontend
workbranch push login --repo frontend
workbranch land login --repo frontend
```

### `workbranch remove <task>`

Remove linked worktrees and local task branches for a task.
Remote task branches are not deleted.

If the task worktree directory was removed manually, `workbranch remove <task>` still deletes the local task branch when workbranch can identify it from metadata, an existing task worktree, stale Git worktree registration, or the default branch rule.

Fails if any task worktree is dirty.
Use `workbranch remove <task> --force` to discard dirty local task worktrees and local task branches.

### `workbranch version`

Print the installed CLI version as `workbranch <version>`. `workbranch -v` and `workbranch --version` are aliases. The generated single-file executable embeds the version from `.release-please-manifest.json` at build time and falls back to `0.0.0-dev` when no manifest version is available.

## Safety

- Do not overwrite existing worktrees or branches.
- `workbranch config --rewrite` may rewrite an existing `.workbranch.config` to the current format without cloning repos.
- Fail before destructive operations if a target worktree is dirty.
- Use `--ff-only` for pull and merge operations.
- On command-local creation failure, roll back paths and branches created by that command.
- Leave conflict resolution to Git and the user.

## Installer

`install.sh` copies `bin/workbranch` to a target directory. The default is `~/.local/bin`. Standalone installs default to the `main` raw GitHub URL, so the common pasteable install command is `curl -fsSL https://raw.githubusercontent.com/tkhwang/workbranch/main/install.sh | bash`. Pinned tag or SHA installs may pass `WORKBRANCH_RAW_BASE_URL` so the downloaded executable uses the same ref as the installer script.

If the target directory is not on `PATH`, the installer asks whether to add it to the user's shell profile.

- zsh: `~/.zshrc`
- bash: `~/.bash_profile`

If the user declines, print direct-run and manual PATH guidance.

## Acceptance checks

- `config` writes config without cloning base worktrees.
- `init` clones base worktrees from config, or writes config then clones when no config exists.
- `add` creates task worktrees with expected branch names.
- `status` shows base/task commits, diff, and dirty state.
- `pull` fast-forwards base worktrees.
- `update` updates all task worktrees.
- `update <task>` updates one task workspace.
- `push` pushes base branches.
- `push <task>` pushes task branches.
- `land <task>` lands task branches into local base branches without merge commits.
- `--repo <repo>` limits supported Git commands to one repo.
- `remove <task>` removes linked worktrees and local task branches.
- `-v`, `--version`, and `version` print the manifest-backed installed CLI version.
- Dirty worktree checks prevent unsafe operations.
- Integration tests use temporary local bare remotes.
