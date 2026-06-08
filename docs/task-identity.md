# Task identity and branch names

[README](../README.md) | [한국어](task-identity.ko.md)

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
