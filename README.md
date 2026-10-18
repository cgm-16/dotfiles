# dotfiles

Personal dotfiles, linked into `$HOME` with [GNU Stow](https://www.gnu.org/software/stow/). Each top-level folder is a Stow package (currently only `tmux/`).

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

- **Existing `~/.tmux.conf`** is moved to `~/.tmux.conf.bak.<timestamp>`. To pull it into the repo instead, pass `--adopt` (`… | sh -s -- --adopt`), then review with `git -C ~/dotfiles diff`.
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

## Tests

```sh
sh test/install_test.sh
```

Runs every case in a throwaway `$HOME`, cloning from the local checkout (no network).
