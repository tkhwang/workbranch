# monotree

AI-friendly worktrees for multi-repo projects.

`monotree` is a small Bash CLI for developers who work across separate repositories — for example frontend, backend, mobile, or infra — but want one clean task workspace for AI coding assistants.

Instead of turning your repos into a real monorepo, monotree keeps them as independent Git repositories and uses `git worktree` to create task-local folders:

```text
/fullstack
  /.monotree
    config
  /_base
    /frontend
    /backend
  /login
    /frontend
    /backend
```

Run your AI assistant from the task directory:

```bash
cd /fullstack/login
codex
# or claude
```

Then mention files naturally:

```text
@frontend/src/...
@backend/app/...
```

## Install

```bash
./install.sh
```

The installer copies `bin/monotree` to:

```text
~/.local/bin/monotree
```

## Config

Create `.monotree/config` in a project root:

```text
project fullstack
base_dir _base
branch_prefix feature

repo frontend git@github.com:example/frontend.git master
repo backend git@github.com:example/backend.git master
```

Or run `monotree init` outside an existing monotree project to create this interactively.

## CLI

```bash
monotree init
monotree add login
monotree list
monotree sync
monotree update login
monotree push login
monotree remove login
```

## Development

The MVP spec is in:

```text
docs/specs/0001-monotree-mvp.md
```

The implementation plan is in:

```text
docs/plans/0001-monotree-mvp-implementation.md
```

Run the integration suite with local temporary bare remotes:

```bash
./tests/run.sh
```
