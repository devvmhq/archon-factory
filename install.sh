#!/usr/bin/env bash
# Installs the factory pack for every project on this machine by symlinking this
# repo's workflows, commands and scripts into ~/.archon/<kind>/factory, and
# bin/factory into ~/.local/bin. Edits to the repo apply at once. Safe to rerun;
# it never replaces anything that isn't already its own symlink.
set -euo pipefail

repo=$(cd "$(dirname "$0")" && pwd)
archon_home=${ARCHON_HOME:-$HOME/.archon}

link() {
  local target=$1 link=$2
  mkdir -p "$(dirname "$link")"
  if [ -L "$link" ]; then
    rm "$link"
  elif [ -e "$link" ]; then
    echo "install: $link exists and isn't a symlink; move it away first" >&2
    exit 1
  fi
  ln -s "$target" "$link"
  echo "$link -> $target"
}

for kind in workflows commands scripts; do
  link "$repo/$kind" "$archon_home/$kind/factory"
done
link "$repo/bin/factory" "$HOME/.local/bin/factory"
