# dotfiles

Personal dotfiles, linked into `$HOME` with [GNU Stow](https://www.gnu.org/software/stow/). Each top-level folder is a Stow package:

- `tmux/`: `.tmux.conf`
- `zsh/`: `.zprofile`, `.zshrc`. Oh My Zsh and fnm are used when installed and skipped when not.
- `git/`: `.gitconfig`, and the global ignore at `~/.config/git/ignore`

## Install

Needs `git`, `stow` and `tmux` (`sudo apt install git stow tmux` or `brew install git stow tmux`). The script won't install packages for you.

```sh
curl -fsSL https://raw.githubusercontent.com/cgm-16/dotfiles/main/install.sh | sh
```

or

```sh
git clone https://github.com/cgm-16/dotfiles.git ~/dotfiles && ~/dotfiles/install.sh
```

Then start `tmux`. TPM and the plugins install automatically on first launch.

The script is idempotent. Re-run it any time to pull updates and relink.

- **Existing files** such as `~/.zshrc` are moved to `~/.zshrc.bak.<timestamp>`. To pull them into the repo instead, pass `--adopt` (`… | sh -s -- --adopt`), then review with `git -C ~/dotfiles diff`.
- **Checkout somewhere else:** `DOTFILES=~/repos/dotfiles ~/repos/dotfiles/install.sh`.

## Machine-local tmux settings

`~/.tmux.local.conf` is sourced if it exists and is never committed. Example: colour the status bar on one host:

```tmux
%if "#{==:#{host},prod-node-1}"
set -g status-style bg=red
%endif
```

Truecolor is enabled for outer terminals reporting `TERM=xterm-256color`. If yours reports something else (e.g. Ghostty's `xterm-ghostty`), add it here:

```tmux
set -as terminal-features ",xterm-ghostty:RGB"
```

## Machine-local shell and git settings

Both files are read if they exist and are never committed:

- `~/.zshrc.local`, sourced from `.zshrc` before fnm. Lines an installer appends to `~/.zshrc` (Docker Desktop, opencode) land in the repo copy, so move them here.
- `~/.gitconfig.local`, included last by `.gitconfig`, so its values win. Put credential helpers here. `git config --global` and `gh auth setup-git` write through the link into the tracked `.gitconfig`, so use `git config --file ~/.gitconfig.local` instead.

## Tests

Needs `zsh` as well as the install prerequisites.

```sh
sh test/install_test.sh
```

Runs every case in a throwaway `$HOME`, cloning from the local checkout (no network).
