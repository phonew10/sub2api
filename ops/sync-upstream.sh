#!/usr/bin/env bash
# Merge upstream main into this fork's main and push to origin.
# main = upstream main + our ops/ directory; merges are conflict-free as long as
# our changes stay under ops/.
# Usage: ./ops/sync-upstream.sh          (from anywhere inside the repo)
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

UPSTREAM_URL="https://github.com/Wei-Shaw/sub2api.git"
if ! git remote get-url upstream >/dev/null 2>&1; then
  git remote add upstream "$UPSTREAM_URL"
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree is dirty; commit or stash first" >&2
  exit 1
fi

echo "==> fetching upstream + origin"
git fetch --quiet --tags upstream
git fetch --quiet origin

cur_branch=$(git rev-parse --abbrev-ref HEAD)
[[ "$cur_branch" == "main" ]] || git checkout --quiet main

git merge --ff-only origin/main 2>/dev/null || true   # pick up anything pushed from elsewhere

read -r ahead behind < <(git rev-list --left-right --count main...upstream/main)
echo "==> fork main: ${ahead} ahead (ours), ${behind} behind upstream/main"

if (( behind == 0 )); then
  echo "==> already up to date with upstream"
else
  echo "==> merging upstream/main"
  if ! git merge --no-edit upstream/main; then
    echo "error: merge conflict; resolve, commit, then 'git push origin main'" >&2
    exit 1
  fi
  git push origin main
  echo "==> pushed $(git rev-parse --short HEAD) to origin/main"
fi

git push --quiet origin --tags 2>/dev/null || true
echo "==> latest upstream tag: $(git describe --tags --abbrev=0 upstream/main)"
[[ "$cur_branch" == "main" ]] || git checkout --quiet "$cur_branch"
