# Task identity and branch names

[README](../README.md) | [한국어](task-identity.ko.md)

Task creation uses the prompt shape that matches the configured base branches.

On `main`/`master`-style bases, `workbranch add` asks for the conventional task identity:

| Prompt           | Example | Used for             |
| ---------------- | ------- | -------------------- |
| Task type        | `feat`  | Git branch prefix    |
| Task detail name | `login` | Folder/branch detail |

`workbranch` derives:

- task folder: `feat-login`
- per-repo default Git branch: `feat/login`

When every repo shares one identical parent feature base, such as `feature/cpq`, the conventional task type would not appear in the branch. In that case `workbranch add` asks only for the task name and mirrors the resulting branch into the folder name by replacing `/` with `-`:

- task name: `login`
- task folder: `feature-cpq-login`
- per-repo default Git branch: `feature/cpq-login`

Interactive `workbranch add <name>` follows the same base-aware prompt flow with `<name>` as the editable default. On `main`/`master` bases it asks for `Task type` and `Task detail name [<name>]`; on a shared parent feature base it asks only for `Task name [<name>]`.

`workbranch add feat-login` remains a direct shorthand for the conventional task key. On a parent feature base, that explicit shorthand keeps folder `feat-login` for compatibility while defaulting the branch to `feature/cpq-login`. Explicit parent-slug keys such as `workbranch add feature-cpq-login` are accepted and resolve back to `feature/cpq-login`. Non-interactive scripts can still pass task keys without the conventional `type-` prefix; those legacy explicit keys keep branch-prefix defaults for compatibility.

Folder names and branch names stay separate surfaces because folders must be path-safe while Git branches normally use `/`. Repo-specific branch prompts still let you override the default per repo.

By default, `workbranch add` creates task branches from the current HEAD of your local `_base/<repo>` worktrees. It does not pull remote base branches automatically. To start from the latest remote base, run:

```bash
workbranch pull
workbranch add
```

Use `workbranch add [<task>] --from <ref>` to seed the new task branches from another source ref. For example, `workbranch add task1 --from feat/XXX` fetches origin, prefers `origin/feat/XXX` when it exists, and creates the linked task worktrees from that ref while still using the prompted task branch names. Later `workbranch status` still compares the task branch to the current local base; the source ref is creation context, not a persistent status baseline.

During active work, run `workbranch refresh` to pull remote base branches into `_base/<repo>` and then update every task workspace from those refreshed local bases. Use `workbranch refresh <task>` to refresh one task. `refresh` first checks that target task worktrees are updateable; dirty or otherwise blocked tasks stop the command before base branches are pulled.

Use `workbranch config` when you want to update project settings, base branches, IDE/terminal launch commands, or per-repo setup commands without cloning repos again. If base branches change, existing `_base/<repo>` worktrees are fetched, checked out, and fast-forward pulled to those branches. Use `workbranch config base` when you only want to update base branches.
