# Login shells, interactive or not.
#
# zsh reads ~/.zshrc only for interactive shells, so anything a script, git
# hook or launchd job needs has to live here instead. Without this, a
# non-interactive login shell fell through to Homebrew's node (v22) rather
# than the version fnm selects -- under the >=24 floor several projects pin.
#
# /opt/homebrew/bin is already on PATH via /etc/paths.d/homebrew, so fnm
# resolves here without brew shellenv.

# Added by cua-driver-rs installer -- see https://github.com/trycua/cua
# Moved here from ~/.zshrc: it carries a node symlink into the Hermes bundle,
# so it has to be prepended BEFORE fnm or it shadows the version fnm selected.
export PATH="$HOME/.local/bin:$PATH"

if command -v fnm >/dev/null; then
  eval "$(fnm env --use-on-cd --version-file-strategy=recursive --corepack-enabled --shell zsh)"
fi
