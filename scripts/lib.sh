# Helpers for the factory pack's bash nodes. Source this file; don't run it.
#
# Runs happen in an Archon worktree, but dex's storage (.dex/, gitignored) lives
# only in the project's main checkout, so every dex and lane call goes there.

set -euo pipefail

# The project's main checkout: the parent of the git directory that every
# worktree shares.
factory_root() {
  dirname "$(git rev-parse --path-format=absolute --git-common-dir)"
}

# dex, pointed at the main checkout's storage.
factory_dex() {
  dex --storage-path "$(factory_root)/.dex" "$@"
}

# Refuse anything that doesn't look like a dex task ID before it reaches a shell
# command or a file.
factory_check_id() {
  [[ ${1:-} =~ ^[a-z0-9]+$ ]] || { echo "not a dex task ID: '${1:-}'" >&2; return 1; }
  factory_dex show "$1" --json >/dev/null
}

# factory_lane <task-id> <lane> <run-id>
# Records the task's lane in .dex/lanes.json, a sidecar that dex never rewrites
# (dex drops metadata keys it doesn't know). A mkdir lock serialises writers.
factory_lane() {
  local id=$1 lane=$2 run=$3 dir file lock tmp now
  dir="$(factory_root)/.dex"
  file="$dir/lanes.json"
  lock="$dir/lanes.lock"
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  for _ in $(seq 50); do mkdir "$lock" 2>/dev/null && break; sleep 0.1; done
  [ -d "$lock" ] || { echo "could not lock $lock" >&2; return 1; }
  [ -f "$file" ] || echo '{}' >"$file"
  tmp=$(mktemp "$file.XXXXXX")
  if jq --arg id "$id" --arg lane "$lane" --arg run "$run" --arg now "$now" \
    '.[$id] = {lane: $lane, run: $run, updated: $now}' "$file" >"$tmp"; then
    mv "$tmp" "$file"
  else
    rm -f "$tmp"; rmdir "$lock"; return 1
  fi
  rmdir "$lock"
}

# Gets a fresh worktree ready: trusts the project's mise config (the worktree
# path is new to mise) and records the commit the run started from.
# factory_prepare <artifacts-dir>
factory_prepare() {
  if [ -f mise.toml ] || [ -f .mise.toml ]; then mise trust --quiet >/dev/null; fi
  git rev-parse HEAD >"$1/base"
}

# The run's changes so far, new files included, against the starting commit.
# factory_diff <artifacts-dir> [git diff options]
factory_diff() {
  local base
  base=$(cat "$1/base")
  shift
  git add --intent-to-add --all
  git diff "$@" "$base"
}

# The project gate. The project's mise.toml defines fmt, lint and test.
factory_gate() {
  mise run fmt && mise run lint && mise run test
}

# Fail-first check: new or changed test files exist, and the test suite fails.
# factory_red <artifacts-dir>
factory_red() {
  local log="$1/red.log"
  if [ -z "$(factory_diff "$1" --name-only | grep -E '_test\.go$|(^|/)testdata/' || true)" ]; then
    echo "no test files were added or changed" >&2
    return 1
  fi
  if mise run test >"$log" 2>&1; then
    echo "the tests pass before any implementation, so they don't test the change" >&2
    tail -20 "$log" >&2
    return 1
  fi
  echo "red as expected:"
  tail -30 "$log"
}

# Commits the worktree as one commit with the message the commit-message node
# wrote, fast-forwards the main checkout's current branch to it, and completes
# the dex task. Never pushes. The task ID stays out of the commit (AGENTS.md);
# dex links the task to the commit instead.
# factory_commit <task-id> <run-id> <artifacts-dir>
factory_commit() {
  local id=$1 run=$2 msg="$3/commit-message.txt" sha root branch
  [ -s "$msg" ] || { echo "no commit message at $msg" >&2; return 1; }
  git add --all
  if git diff --cached --quiet; then echo "nothing to commit" >&2; return 1; fi
  git commit --quiet --file "$msg"
  sha=$(git rev-parse HEAD)
  root=$(factory_root)
  branch=$(git -C "$root" branch --show-current)
  if ! git -C "$root" merge --ff-only --quiet "$sha"; then
    echo "committed $sha on $(git branch --show-current), but could not fast-forward $branch in $root; merge it by hand" >&2
    return 1
  fi
  factory_dex complete "$id" --result "Committed $sha (Archon run $run)" --commit "$sha" >/dev/null
  factory_lane "$id" "done" "$run"
  echo "$sha"
}
