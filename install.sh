#!/bin/sh
# Install dotfiles: clone or update the repo, copy agent-token/ into $HOME, then
# stow the other packages into $HOME.
# Usage: install.sh [--adopt]
#   --adopt  pull existing files into the repo instead of backing them up
# Env: DOTFILES (checkout path, default ~/dotfiles), DOTFILES_REPO (clone URL)
set -eu

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/cgm-16/dotfiles.git}"
ADOPT=""

for arg in "$@"; do
  case "$arg" in
    --adopt) ADOPT="--adopt" ;;
    *) echo "usage: install.sh [--adopt]" >&2; exit 2 ;;
  esac
done

die() { echo "error: $*" >&2; exit 1; }

missing=""
for cmd in git stow tmux; do
  command -v "$cmd" >/dev/null 2>&1 || missing="$missing $cmd"
done
[ -z "$missing" ] || die "missing:$missing
  Debian/Ubuntu: sudo apt install$missing
  macOS:         brew install$missing"

if [ -d "$DOTFILES/.git" ]; then
  if git -C "$DOTFILES" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    git -C "$DOTFILES" pull --ff-only
  else
    echo "note: $DOTFILES has no upstream branch, skipping pull"
  fi
elif [ -e "$DOTFILES" ]; then
  die "$DOTFILES exists but is not a git checkout"
else
  git clone "$DOTFILES_REPO" "$DOTFILES"
fi

# Stow packages: each top-level folder mirrors the files it links into $HOME.
set -- tmux zsh git

# Tracked files only, as package/path, so files tools write beside an installed
# file (gh's tokens next to the loader) are never touched.
files=$(git -C "$DOTFILES" ls-files -- "$@")
# agent-token/ is copied, not linked: a link left dangling by a moved, deleted
# or switched checkout would drop agent shells back to the keyring token.
copies=$(git -C "$DOTFILES" ls-files -- agent-token)

# Refuse before moving anything, so a failed run leaves $HOME as it was. Any
# link at a copy target is refused, even one into the repo, which would keep
# the guard tied to the checkout.
for file in $files $copies; do
  target="$HOME/${file#*/}"
  # -ef is not strictly POSIX but dash, bash, busybox and macOS sh all support it
  # shellcheck disable=SC3013
  case "$file" in
    agent-token/*) [ ! -L "$target" ] ;;
    *) [ ! -L "$target" ] || [ "$target" -ef "$DOTFILES/$file" ] ;;
  esac || die "$target is a symlink to $(readlink "$target"); remove it and re-run"
done

backups=""
stamp=$(date +%Y%m%d%H%M%S)
backup() {
  mv "$1" "$1.bak.$stamp"
  echo "backed up $1 to $1.bak.$stamp"
  backups="$backups $1.bak.$stamp"
}

for file in $copies; do
  src="$DOTFILES/$file" target="$HOME/${file#*/}"
  if [ -f "$target" ]; then
    cmp -s "$src" "$target" && continue
    if [ -n "$ADOPT" ]; then
      cp "$target" "$src"
      echo "copied $target to $src"
      continue
    fi
  fi
  mkdir -p "$(dirname "$target")"
  # Copy beside the target and rename over it, so a failed copy never leaves
  # it half-written; -p keeps the repo file's mode over mktemp's 0600.
  tmp=$(mktemp "$target.XXXXXX")
  cp -p "$src" "$tmp"
  [ ! -f "$target" ] || backup "$target"
  mv "$tmp" "$target"
  echo "copied $src to $target"
done

if [ -z "$ADOPT" ]; then
  for file in $files; do
    target="$HOME/${file#*/}"
    [ ! -L "$target" ] && [ -f "$target" ] || continue
    backup "$target"
  done
fi

# --no-folding links files, never directories: a folded ~/.config would put
# everything other tools write there, gh's tokens included, inside the repo.
stow -d "$DOTFILES" -t "$HOME" $ADOPT --no-folding -R -v "$@"

echo
echo "copied into $HOME: agent-token"
echo "linked into $HOME: $*"
for backup in $backups; do echo "backup: $backup"; done
[ -z "$ADOPT" ] || echo "adopted: review with: git -C $DOTFILES diff"
echo "start tmux, plugins install automatically"
