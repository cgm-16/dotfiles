#!/bin/sh
# Install dotfiles: clone or update the repo, then stow packages into $HOME.
# Usage: install.sh [--adopt]
#   --adopt  move an existing ~/.tmux.conf into the repo instead of backing it up
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

target="$HOME/.tmux.conf"
backup=""
if [ -L "$target" ]; then
  # -ef is not strictly POSIX but dash, bash, busybox and macOS sh all support it
  # shellcheck disable=SC3013
  [ "$target" -ef "$DOTFILES/tmux/.tmux.conf" ] ||
    die "$target is a symlink to $(readlink "$target"); remove it and re-run"
elif [ -f "$target" ] && [ -z "$ADOPT" ]; then
  backup="$target.bak.$(date +%Y%m%d%H%M%S)"
  mv "$target" "$backup"
  echo "backed up $target to $backup"
fi

stow -d "$DOTFILES" -t "$HOME" $ADOPT -R -v tmux

echo
echo "linked: $target -> $DOTFILES/tmux/.tmux.conf"
[ -z "$backup" ] || echo "backup: $backup"
[ -z "$ADOPT" ] || echo "adopted: review with: git -C $DOTFILES diff"
echo "start tmux, plugins install automatically"
