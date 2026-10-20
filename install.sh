#!/bin/sh
# Install dotfiles: clone or update the repo, then stow packages into $HOME.
# Usage: install.sh [--adopt]
#   --adopt  move existing files into the repo instead of backing them up
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

# Tracked files only, as package/path, so untracked files beside a link are
# never touched.
files=$(git -C "$DOTFILES" ls-files -- "$@")

# Refuse before moving anything, so a failed run leaves $HOME as it was.
for file in $files; do
  target="$HOME/${file#*/}"
  # -ef is not strictly POSIX but dash, bash, busybox and macOS sh all support it
  # shellcheck disable=SC3013
  [ ! -L "$target" ] || [ "$target" -ef "$DOTFILES/$file" ] ||
    die "$target is a symlink to $(readlink "$target"); remove it and re-run"
done

backups=""
if [ -z "$ADOPT" ]; then
  stamp=$(date +%Y%m%d%H%M%S)
  for file in $files; do
    target="$HOME/${file#*/}"
    [ ! -L "$target" ] && [ -f "$target" ] || continue
    mv "$target" "$target.bak.$stamp"
    echo "backed up $target to $target.bak.$stamp"
    backups="$backups $target.bak.$stamp"
  done
fi

# --no-folding links files, never directories: a folded ~/.config would put
# everything other tools write there, gh's tokens included, inside the repo.
stow -d "$DOTFILES" -t "$HOME" $ADOPT --no-folding -R -v "$@"

echo
echo "linked into $HOME: $*"
for backup in $backups; do echo "backup: $backup"; done
[ -z "$ADOPT" ] || echo "adopted: review with: git -C $DOTFILES diff"
echo "start tmux, plugins install automatically"
