#!/bin/sh
# Acceptance test for agent-token.sh. Usage: sh agent-token-test.sh [path-to-agent-token.sh]
# Runs every case in a throwaway $HOME with fake token files; real tokens are never read.
LOADER=${1:-$HOME/.config/gh/agent-token.sh}
LOADER=$(cd "$(dirname "$LOADER")" && pwd -P)/$(basename "$LOADER")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.config/gh" "$T/repo"
printf 'fake-default' > "$T/.config/gh/agent-token"
printf 'fake-acme' > "$T/.config/gh/agent-token-acme"
git -C "$T/repo" init -q && git -C "$T/repo" remote add origin https://github.com/Acme/widget.git

FAIL=0
check() { # want description shell-command...
  want=$1; desc=$2; shift 2
  got=$(cd "$T" && env -i HOME="$T" PATH="$PATH" LOADER="$LOADER" "$@" 2>/dev/null)
  if [ "$got" = "$want" ]; then echo "ok - $desc"; else FAIL=$((FAIL + 1)); echo "FAIL - $desc: want '$want' got '$got'"; fi
}
PRINT='. "$LOADER"; printf %s "${GH_TOKEN-}"'

check fake-default "zsh, non-interactive, no agent marker" zsh -f -c "$PRINT"
check fake-default "zsh, non-interactive, CLAUDECODE set" env CLAUDECODE=1 zsh -f -c "$PRINT"
check fake-default "bash, non-interactive, no agent marker" bash --norc --noprofile -c "$PRINT"
check fake-acme "owner token for the cwd repo's origin" sh -c "cd repo && $PRINT"
check "" "zsh, interactive" zsh -f -i -c "$PRINT"
check "" "bash, interactive" bash --norc --noprofile -i -c "$PRINT"
rm "$T/.config/gh/agent-token"
check "" "no default token file, marker set" env CLAUDECODE=1 zsh -f -c "$PRINT"

[ "$FAIL" = 0 ] && echo "all cases pass" || { echo "$FAIL case(s) failed"; exit 1; }
