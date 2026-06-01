# Workbranch architecture

`workbranch` is authored as modular Bash under `src/workbranch/**` and distributed as one generated executable at `bin/workbranch`.

## Edit/build rule

- Edit `src/workbranch/**`.
- Run `scripts/build-workbranch.sh`.
- Commit both source changes and the regenerated `bin/workbranch`.
- Do not hand-edit `bin/workbranch`.

## Command boundary

Each user command should have one `src/workbranch/commands/<command>.sh` file.

A command file owns orchestration:

1. parse command-specific args
2. validate project/config/task names
3. run preflight checks before mutation
4. call `workbranch_git_*` functions for documented Git operations
5. print concise user-facing status

`src/workbranch/git-ops.sh` owns the exact mutating Git commands mirrored by `docs/git-operations.md`.

`src/workbranch/lib/preflight.sh` owns safety checks and aggregate preflight failure reporting.

## Distribution boundary

All install channels use the same generated `bin/workbranch` artifact:

- direct curl/wget downloads
- `install.sh`
- Homebrew formula installation from a release tarball

Homebrew can support multi-file runtime payloads through private install directories, but this project intentionally keeps the runtime as one file so all install channels behave the same.

## Optional packaging checks

Run these only when Homebrew is available locally:

```bash
brew audit --strict --online packaging/homebrew/workbranch.rb
brew test packaging/homebrew/workbranch.rb
```
