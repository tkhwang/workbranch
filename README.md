# monotree

AI-friendly worktrees for multi-repo projects.

`monotree` is a small shell CLI for developers who work across separate repositories — for example frontend, backend, mobile, or infra — but want one clean task workspace for AI coding assistants.

Instead of turning your repos into a real monorepo, monotree keeps them as independent Git repositories and uses `git worktree` to create task-local folders:

```text
/fullstack
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

## Planned CLI

```bash
monotree init
monotree add login
monotree list
monotree sync
monotree update login
monotree push login
monotree remove login
```

## Status

Early design stage. The MVP spec is in:

```text
docs/specs/0001-monotree-mvp.md
```

Implementation is next.
