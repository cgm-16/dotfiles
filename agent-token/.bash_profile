# A bash login shell reads only the first of ~/.bash_profile, ~/.bash_login and
# ~/.profile, so keep ~/.profile, which Debian and Ubuntu chain ~/.bashrc from.
[ -r ~/.profile ] && . ~/.profile
[ -r ~/.config/gh/agent-token.sh ] && . ~/.config/gh/agent-token.sh
