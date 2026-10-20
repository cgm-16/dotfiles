# shellcheck shell=sh
# Hand agent sessions a GitHub token with no Administration rights, so a ruleset
# or branch protection cannot be edited from one. Interactive shells are left
# alone and keep whatever `gh auth login` stored.
#
# Sourced from ~/.zshenv (zsh reads it for non-interactive shells, which is what
# every agent's shell tool runs) and from ~/.bash_profile (bash -lc).

case $- in
  *i*) ;;  # a human is typing; gh keeps the admin token
  *)
    # Harnesses mark their shells (CLAUDECODE, HERMES_SESSION_ID, CODEX_SANDBOX,
    # OPENCODE_*), but a harness that sets none of these, or a new one, must not
    # fall through to the admin token, so every non-interactive shell lands here.
    # An admin command opts out explicitly with `env -u GH_TOKEN`.
    if [ -r "$HOME/.config/gh/agent-token" ]; then
      # A fine-grained PAT covers one owner. Use agent-token-<owner> when the
      # current repo's origin owner has one, else the default agent-token.
      _agent_tok="$HOME/.config/gh/agent-token"
      _agent_owner=$(git remote get-url origin 2>/dev/null | sed -nE 's#.*github\.com[:/]([^/]+)/.*#\1#p' | tr '[:upper:]' '[:lower:]')
      [ -n "$_agent_owner" ] && [ -r "$_agent_tok-$_agent_owner" ] && _agent_tok="$_agent_tok-$_agent_owner"
      GH_TOKEN=$(cat "$_agent_tok"); export GH_TOKEN
      unset _agent_tok _agent_owner
    fi
    ;;
esac
