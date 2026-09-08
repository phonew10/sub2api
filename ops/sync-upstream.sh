#!/usr/bin/env bash
# Fast-forward this fork's main to upstream main and push to origin.
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

read -r ahead behind < <(git rev-list --left-right --count origin/main...upstream/main)
echo "==> fork main: ${ahead} ahead, ${behind} behind upstream/main"

if (( ahead > 0 )); then
  echo "error: origin/main has ${ahead} commit(s) not in upstream; main must stay a pure mirror." >&2
  echo "       Move those commits to a branch, then re-run." >&2
  exit 1
fi

if (( behind == 0 )); then
  echo "==> already up to date"
else
  git merge --ff-only upstream/main
  git push origin main
  echo "==> pushed $(git rev-parse --short HEAD) to origin/main"
fi

git push --quiet origin --tags 2>/dev/null || true
echo "==> latest upstream tag: $(git describe --tags --abbrev=0 upstream/main)"
[[ "$cur_branch" == "main" ]] || git checkout --quiet "$cur_branch"
