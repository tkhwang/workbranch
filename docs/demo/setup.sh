#!/usr/bin/env bash
# Builds a throwaway workbranch playground (two fake bare remotes + a config)
# and prints the project path so demo.tape can `cd` into it.
#
# Nothing here touches a real repository: everything lives under a fresh mktemp
# directory. Safe to run standalone for testing:  cd "$(bash docs/demo/setup.sh)"
set -eu

demo_root="$(mktemp -d "${TMPDIR:-/tmp}/workbranch-demo.XXXXXX")"
mkdir -p "$demo_root/remotes"

for repo in frontend backend; do
  seed="$demo_root/seed/$repo"
  mkdir -p "$seed"
  git init -q "$seed"
  git -C "$seed" config user.email "demo@workbranch.dev"
  git -C "$seed" config user.name "workbranch demo"
  printf '# %s\n' "$repo" > "$seed/README.md"
  git -C "$seed" add .
  git -C "$seed" commit -qm "init $repo"
  git -C "$seed" branch -M main
  git clone -q --bare "$seed" "$demo_root/remotes/$repo.git"
done

project="$demo_root/my-app"
mkdir -p "$project"
cat > "$project/.workbranch.config" <<CONFIG
PROJECT_NAME my-app
MAIN_WORKTREES_DIR _base
BRANCH_PREFIX feature
REPO frontend $demo_root/remotes/frontend.git main
REPO backend $demo_root/remotes/backend.git main
CONFIG

printf '%s\n' "$project"
