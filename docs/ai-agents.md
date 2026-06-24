# AI agent workflows

[README](../README.md) | [한국어](ai-agents.ko.md)

`workbranch` is useful for AI-agent work when one product change spans multiple repos.

```
└── feat-login      // task root: run AI agent here; not a Git repo
    ├── frontend    // actual Git repo worktree
    └── backend     // actual Git repo worktree
```

## Why multi-repo workspaces help

- One task folder contains every repo needed for the change, so an agent can inspect frontend, backend, shared libraries, and docs together.
- Each repo still keeps its own Git branch and worktree, so changes remain reviewable per repository.
- `workbranch refresh <task>` updates the whole task workspace from refreshed base branches before the agent continues.
- `workbranch status` shows dirty state and base/task diffs across repos before you review or hand work back to the agent.
- `workbranch path`, `workbranch ide`, and `workbranch terminal` make it easy to open the right surface: IDE opens repo worktrees, terminal opens the task root by default, and `--repo` scopes either tool to one repo.
- `workbranch remove <task>` cleans up the whole multi-repo task workspace after the branch is landed or abandoned.

## How this differs from a mono-repo

In a mono-repo, one checkout already gives the agent a single project surface. In a multi-repo setup, the agent usually has to coordinate several independent checkouts, branches, and update steps. `workbranch` keeps those repos separate in Git while presenting them as one task workspace on disk.

## Task root convention

Run agent sessions from `<task>` by default so the agent can see `AGENTS.md`, `TASK-WORKBRANCH.md`, and every repo under the task. The task root itself is not git-managed; make code changes and run Git commands inside `<task>/<repo>`. Before editing a repo, read and follow repo-local agent instructions such as `<task>/<repo>/AGENTS.md`, `<task>/<repo>/CLAUDE.md`, or `<task>/<repo>/.claude/` when present. Runtime state such as `.omx/` or `.omc/` is treated as non-git task-root leftover and is listed by `workbranch remove <task>` before deletion.
