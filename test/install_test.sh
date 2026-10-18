#!/bin/sh
# Acceptance tests for install.sh. Each case runs in a throwaway $HOME.
# Usage: sh test/install_test.sh   (needs git, stow, tmux; no network)
set -eu

REPO=$(cd "$(dirname "$0")/.." && pwd -P)
INSTALL="$REPO/install.sh"
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok - $*"; }

# Fresh $HOME; clones from the local repo so no network is needed.
new_home() {
  HOME="$ROOT/home$1"
  mkdir -p "$HOME"
  export HOME
  export DOTFILES_REPO="$REPO"
  unset DOTFILES
}

run_install() { sh "$INSTALL" "$@" >"$HOME/out.log" 2>&1; }

assert_linked() {
  [ -L "$HOME/.tmux.conf" ] || fail "$1: ~/.tmux.conf is not a symlink"
  [ "$HOME/.tmux.conf" -ef "$HOME/dotfiles/tmux/.tmux.conf" ] ||
    fail "$1: ~/.tmux.conf does not point into ~/dotfiles/tmux/"
}

# 1. config parses and every option is valid
new_home 1
tmux -L "install_test_$$" -f /dev/null new-session -d
grep -v -e '^if ' -e '^ *"run ' -e '^run ' "$REPO/tmux/.tmux.conf" >"$HOME/no-tpm.conf"
tmux -L "install_test_$$" source-file "$HOME/no-tpm.conf" ||
  { tmux -L "install_test_$$" kill-server; fail "tmux config has errors"; }
tmux -L "install_test_$$" kill-server
pass "tmux config parses"

# 2. fresh install links ~/.tmux.conf
new_home 2
run_install || fail "fresh install exited non-zero: $(cat "$HOME/out.log")"
assert_linked "fresh install"
pass "fresh install links ~/.tmux.conf"

# 3. second run succeeds and changes nothing
before=$(ls -la "$HOME")
run_install || fail "second run exited non-zero: $(cat "$HOME/out.log")"
assert_linked "second run"
[ "$(ls -la "$HOME" | grep -v out.log)" = "$(echo "$before" | grep -v out.log)" ] ||
  fail "second run changed \$HOME"
[ -z "$(git -C "$HOME/dotfiles" status --porcelain)" ] || fail "second run dirtied the repo"
pass "second run is a no-op"

# 4. pre-existing regular file is backed up, then linked
new_home 4
echo "old config" >"$HOME/.tmux.conf"
run_install || fail "backup run exited non-zero: $(cat "$HOME/out.log")"
assert_linked "backup run"
set -- "$HOME"/.tmux.conf.bak.*
[ -f "$1" ] || fail "no backup file created"
[ "$(cat "$1")" = "old config" ] || fail "backup content differs"
grep -q "$1" "$HOME/out.log" || fail "backup path not reported"
pass "existing file is backed up to $(basename "$1")"

# 5. --adopt pulls the existing file into the repo instead of backing it up
new_home 5
echo "adopted config" >"$HOME/.tmux.conf"
run_install --adopt || fail "adopt run exited non-zero: $(cat "$HOME/out.log")"
assert_linked "adopt run"
[ "$(cat "$HOME/dotfiles/tmux/.tmux.conf")" = "adopted config" ] || fail "file not adopted"
! ls "$HOME"/.tmux.conf.bak.* >/dev/null 2>&1 || fail "adopt also made a backup"
grep -q "git -C .* diff" "$HOME/out.log" || fail "adopt did not suggest git diff"
pass "--adopt adopts the existing file"

# 6. a symlink pointing elsewhere stops the install with a clear message
new_home 6
echo "elsewhere" >"$HOME/other.conf"
ln -s "$HOME/other.conf" "$HOME/.tmux.conf"
! run_install || fail "foreign symlink: install should fail"
grep -q "is a symlink to" "$HOME/out.log" || fail "foreign symlink: unclear message: $(cat "$HOME/out.log")"
[ "$HOME/.tmux.conf" -ef "$HOME/other.conf" ] || fail "foreign symlink was modified"
pass "foreign symlink is refused"

# 7. missing stow gives one clear error
new_home 7
mkdir "$HOME/bin"
ln -s "$(command -v git)" "$HOME/bin/git"
ln -s "$(command -v tmux)" "$HOME/bin/tmux"
! PATH="$HOME/bin" /bin/sh "$INSTALL" >"$HOME/out.log" 2>&1 || fail "missing stow: install should fail"
grep -q "stow" "$HOME/out.log" || fail "missing stow: no mention of stow"
grep -q "install stow" "$HOME/out.log" || fail "missing stow: no install hint"
[ "$(wc -l <"$HOME/out.log")" -le 3 ] || fail "missing stow: noisy output: $(cat "$HOME/out.log")"
pass "missing stow gives a clear error"

echo "all tests passed"
