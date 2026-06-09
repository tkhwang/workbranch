# workbranch demo

A reproducible [VHS](https://github.com/charmbracelet/vhs) recording of the core
multi-repo workflow, mirroring the main [README](../../README.md).

## Files

- `demo.tape` — the VHS script (what gets recorded).
- `setup.sh` — builds a throwaway project (two fake bare remotes + `.workbranch.config`)
  and prints its path. Invoked automatically from `demo.tape`'s hidden setup block;
  it never touches a real repository.

## Record

From the repository root:

```bash
# 1. Install VHS once: https://github.com/charmbracelet/vhs#installation
# 2. Make the in-repo build available as `workbranch` (or install it):
export PATH="$PWD/bin:$PATH"

# 3. Render -> docs/figs/workbranch-demo.gif
vhs docs/demo/demo.tape
```

## What it shows

1. `workbranch init` — clone every base repo from config
2. `workbranch add feat-login` — one task workspace across all repos
3. `ls feat-login` — every repo under a single task folder
4. `workbranch status` — base/task diff across repos at a glance
5. `workbranch refresh feat-login` — update every repo to the latest base in one command

## Tuning

The demo runs real commands, so a few things depend on your environment:

- **`workbranch` must be on `PATH`** (see step 2 above), or VHS fails the `Require` check.
- **`add feat-login` prompts once per repo** for the task branch; the tape presses
  `Enter` to accept each default. The sample config has two repos, so there are two
  `Enter` lines after the `add` step — adjust the count if your config differs.
- **Increase the `Sleep` values** if a command needs longer on your machine.
- To preview without rendering a GIF, use `vhs --publish` or `vhs validate docs/demo/demo.tape`.
