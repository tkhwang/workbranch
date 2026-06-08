# AI agent workflows

[README](../README.md) | [한국어](ai-agents.ko.md)

`workbranch` is useful for AI-agent work when one product change spans multiple repos.

## Why multi-repo workspaces help

- One task folder contains every repo needed for the change, so an agent can inspect frontend, backend, shared libraries, and docs together.
- Each repo still keeps its own Git branch and worktree, so changes remain reviewable per repository.
- `workbranch refresh <task>` updates the whole task workspace from refreshed base branches before the agent continues.
- `workbranch status` shows dirty state and base/task diffs across repos before you review or hand work back to the agent.
- `workbranch path`, `workbranch ide`, and `workbranch terminal` make it easy to open the same task context in external tools.
- `workbranch remove <task>` cleans up the whole multi-repo task workspace after the branch is landed or abandoned.

## How this differs from a mono-repo

In a mono-repo, one checkout already gives the agent a single project surface. In a multi-repo setup, the agent usually has to coordinate several independent checkouts, branches, and update steps. `workbranch` keeps those repos separate in Git while presenting them as one task workspace on disk.
