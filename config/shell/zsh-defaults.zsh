# =============================================
#   archenemy · SHARED layer · zsh defaults
#   Loaded by the "archenemy shell" block in ~/.zshrc BEFORE your file
#   config/shell/shellrc, so you can override anything here in the
#   "zsh only" section of that file. No frameworks (oh-my-zsh etc.), only
#   what zsh has built in: history, completion, bash-like keys and the Arch
#   default bash prompt. The block may be added to an existing ~/.zshrc and
#   must not break someone else's setup: history and prompt only when unset,
#   compinit only once.
# =============================================

# ── history ──
[[ -n "$HISTFILE" ]] || HISTFILE="$HOME/.zsh_history"
(( HISTSIZE >= 10000 )) || HISTSIZE=10000
(( SAVEHIST >= 10000 )) || SAVEHIST=10000
setopt append_history inc_append_history hist_ignore_dups hist_ignore_space hist_reduce_blanks

# Comments on the command line, as in bash (off by default in zsh).
setopt interactive_comments
setopt no_beep

# ── completion ──
if (( ! ${+functions[compdef]} )); then
    autoload -Uz compinit
    mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
    compinit -d "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump-$ZSH_VERSION"
fi
zstyle ':completion:*' menu select
# lowercase also matches uppercase (like completion-ignore-case in readline)
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
[[ -n "$LS_COLORS" ]] && zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# ── keys ──
# Emacs mode, as in bash. zsh picks vi by itself when $EDITOR contains "vi"
# (e.g. nvim); if you want vi, put `bindkey -v` in the "zsh only" section.
bindkey -e
# Home/End/Delete and Ctrl+arrows: alacritty sends both sequence variants.
for _key in '^[[H' '^[OH' '^[[1~'; do bindkey "$_key" beginning-of-line; done
for _key in '^[[F' '^[OF' '^[[4~'; do bindkey "$_key" end-of-line; done
unset _key
bindkey '^[[3~' delete-char
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word

# ── prompt ──
# Like the Arch default bash PS1: [user@host dir]$ (# for root).
# Only while the prompt is still the zsh default, so your own theme stays.
if [[ "$PROMPT" == '%m%# ' ]]; then PROMPT='[%n@%m %1~]%# '; fi
