#!/bin/sh
# Acceptance tests for install.sh. Each case runs in a throwaway $HOME.
# Usage: sh test/install_test.sh   (needs git, stow, tmux, zsh, bash; no network)
# shellcheck disable=SC3013,SC2010  # -ef is supported by every target sh; test filenames are fixed
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

# Every file install.sh links, as package:path-under-$HOME.
LINKS="tmux:.tmux.conf zsh:.zshenv zsh:.zprofile zsh:.zshrc bash:.bash_profile git:.gitconfig
gh:.config/gh/agent-token.sh gh:.config/gh/agent-token-test.sh"

assert_linked() { # context [checkout]
  for link in $LINKS; do
    pkg=${link%%:*} path=${link#*:}
    [ -L "$HOME/$path" ] || fail "$1: ~/$path is not a symlink"
    [ "$HOME/$path" -ef "${2:-$HOME/dotfiles}/$pkg/$path" ] ||
      fail "$1: ~/$path does not point into $pkg/"
  done
}

# Everything under $HOME except the checkout's contents and the log, with inodes.
snapshot() { find "$HOME" -path "$HOME/dotfiles/*" -prune -o ! -name out.log -exec ls -ldi {} +; }

# 1. config parses and every option is valid
new_home 1
tmux -L "install_test_$$" -f /dev/null new-session -d
grep -v -e '^if ' -e '^ *"run ' -e '^run ' "$REPO/tmux/.tmux.conf" >"$HOME/no-tpm.conf"
tmux -L "install_test_$$" source-file "$HOME/no-tpm.conf" ||
  { tmux -L "install_test_$$" kill-server; fail "tmux config has errors"; }
tmux -L "install_test_$$" kill-server
pass "tmux config parses"

# 2. fresh install links every file, creating real directories on the way
new_home 2
run_install || fail "fresh install exited non-zero: $(cat "$HOME/out.log")"
assert_linked "fresh install"
# A ~/.config folded into a symlink would make gh write its tokens into the repo.
for dir in .config .config/gh; do
  [ -d "$HOME/$dir" ] || fail "fresh install: ~/$dir is not a directory"
  [ ! -L "$HOME/$dir" ] || fail "fresh install: ~/$dir is a symlink into the repo"
done
pass "fresh install links every file"

# 3. second run succeeds and changes nothing
before=$(snapshot)
run_install || fail "second run exited non-zero: $(cat "$HOME/out.log")"
assert_linked "second run"
[ "$(snapshot)" = "$before" ] || fail "second run changed \$HOME"
[ -z "$(git -C "$HOME/dotfiles" status --porcelain)" ] || fail "second run dirtied the repo"
pass "second run is a no-op"

# 4. pre-existing regular files are backed up, then linked; files beside them are kept
new_home 4
mkdir -p "$HOME/.config/gh"
echo "old config" >"$HOME/.tmux.conf"
echo "old loader" >"$HOME/.config/gh/agent-token.sh"
echo "token" >"$HOME/.config/gh/agent-token"
run_install || fail "backup run exited non-zero: $(cat "$HOME/out.log")"
assert_linked "backup run"
set -- "$HOME"/.tmux.conf.bak.*
[ -f "$1" ] || fail "no backup file created"
[ "$(cat "$1")" = "old config" ] || fail "backup content differs"
grep -q "$1" "$HOME/out.log" || fail "backup path not reported"
set -- "$HOME"/.config/gh/agent-token.sh.bak.*
[ -f "$1" ] || fail "nested file not backed up"
[ "$(cat "$1")" = "old loader" ] || fail "nested backup content differs"
[ "$(cat "$HOME/.config/gh/agent-token")" = "token" ] || fail "file beside a linked file was changed"
pass "existing files are backed up"

# 5. --adopt pulls the existing file into the repo instead of backing it up
new_home 5
echo "adopted config" >"$HOME/.tmux.conf"
run_install --adopt || fail "adopt run exited non-zero: $(cat "$HOME/out.log")"
assert_linked "adopt run"
[ "$(cat "$HOME/dotfiles/tmux/.tmux.conf")" = "adopted config" ] || fail "file not adopted"
! ls "$HOME"/.tmux.conf.bak.* >/dev/null 2>&1 || fail "adopt also made a backup"
grep -q "git -C .* diff" "$HOME/out.log" || fail "adopt did not suggest git diff"
pass "--adopt adopts the existing file"

# 6. a symlink pointing elsewhere stops the install before anything is moved
for path in .tmux.conf .config/gh/agent-token.sh; do
  new_home "6-$(basename "$path")"
  mkdir -p "$(dirname "$HOME/$path")"
  echo "elsewhere" >"$HOME/other.conf"
  ln -s "$HOME/other.conf" "$HOME/$path"
  echo "mine" >"$HOME/.bash_profile"
  ! run_install || fail "foreign symlink ~/$path: install should fail"
  grep -q "is a symlink to" "$HOME/out.log" || fail "foreign symlink ~/$path: unclear message: $(cat "$HOME/out.log")"
  [ "$HOME/$path" -ef "$HOME/other.conf" ] || fail "foreign symlink ~/$path was modified"
  [ "$(cat "$HOME/.bash_profile")" = "mine" ] || fail "foreign symlink ~/$path: ~/.bash_profile was moved anyway"
  pass "foreign symlink at ~/$path is refused"
done

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

# 8. a checkout outside ~/dotfiles still links into $HOME, not its parent dir
new_home 8
DOTFILES="$HOME/repos/dotfiles" run_install || fail "custom DOTFILES exited non-zero: $(cat "$HOME/out.log")"
assert_linked "custom DOTFILES" "$HOME/repos/dotfiles"
pass "DOTFILES outside ~/dotfiles links into \$HOME"

# 9. zsh starts quietly without fnm or oh-my-zsh, and reads ~/.zshrc.local
new_home 9
run_install || fail "zsh run exited non-zero: $(cat "$HOME/out.log")"
echo 'echo local-read' >"$HOME/.zshrc.local"
# +o globalrcs skips /etc/zprofile, whose path_helper would put Homebrew's fnm back on PATH.
out=$(cd "$HOME" && env -u FNM_MULTISHELL_PATH PATH=/usr/bin:/bin zsh +o globalrcs -l -i -c true 2>"$HOME/err.log")
[ ! -s "$HOME/err.log" ] || fail "zsh startup wrote to stderr: $(cat "$HOME/err.log")"
[ "$out" = "local-read" ] || fail "zsh did not source ~/.zshrc.local (stdout: $out)"
pass "zsh starts cleanly without fnm or oh-my-zsh and sources ~/.zshrc.local"

# 10. bash login shells still read ~/.profile, which Debian and Ubuntu chain ~/.bashrc from
new_home 10
run_install || fail "bash run exited non-zero: $(cat "$HOME/out.log")"
echo 'echo profile-read' >"$HOME/.profile"
out=$(cd "$HOME" && PATH=/usr/bin:/bin bash -l -c true 2>"$HOME/err.log")
[ ! -s "$HOME/err.log" ] || fail "bash startup wrote to stderr: $(cat "$HOME/err.log")"
[ "$out" = "profile-read" ] || fail "bash login shell skipped ~/.profile (stdout: $out)"
pass "bash login shells read ~/.profile"

# 11. ~/.gitconfig.local is included after, and so overrides, the tracked config
new_home 11
run_install || fail "git run exited non-zero: $(cat "$HOME/out.log")"
printf '[user]\n\temail = local@example.com\n' >"$HOME/.gitconfig.local"
got=$(cd "$HOME" && GIT_CONFIG_NOSYSTEM=1 git config --get user.email)
[ "$got" = "local@example.com" ] || fail "git: ~/.gitconfig.local does not override ~/.gitconfig (got: $got)"
pass "values in ~/.gitconfig.local override ~/.gitconfig"

# 12. the token loader passes its own acceptance test
out=$(sh "$REPO/gh/.config/gh/agent-token-test.sh" "$REPO/gh/.config/gh/agent-token.sh" 2>&1) ||
  fail "agent-token-test.sh: $out"
pass "agent-token loader passes its own test"

# 13. the linked startup files hand non-interactive shells the agent token
new_home 13
run_install || fail "token run exited non-zero: $(cat "$HOME/out.log")"
printf 'fake-wired' >"$HOME/.config/gh/agent-token"
# Compared, never printed: if the loader never ran, this is the token the test inherited.
token_from() { (cd "$HOME" && PATH=/usr/bin:/bin "$@" 'printenv GH_TOKEN'); }
[ "$(token_from zsh -c)" = "fake-wired" ] || fail "zsh -c: ~/.zshenv did not load the agent token"
[ "$(token_from bash -l -c)" = "fake-wired" ] || fail "bash -l -c: ~/.bash_profile did not load the agent token"
pass "zsh and bash login shells load the agent token through the linked files"

echo "all tests passed"
