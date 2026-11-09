# =============================================
#   archenemy · warstwa WSPÓLNA · domyślne ustawienia zsh
#   Wczytywany z bloku „archenemy shell” w ~/.zshrc PRZED plikiem użytkownika
#   config/shell/shellrc, więc wszystko tutaj da się nadpisać w sekcji
#   „zsh only” tego pliku. Bez frameworków (oh-my-zsh itp.) — tylko to, co
#   zsh ma w sobie: historia, uzupełnianie, klawisze jak w bashu, prompt jak
#   domyślny bashowy w Archu. Blok dopisany do istniejącego ~/.zshrc nie może
#   psuć cudzej konfiguracji: historia i prompt tylko gdy nieustawione,
#   compinit tylko raz.
# =============================================

# ── historia ──
[[ -n "$HISTFILE" ]] || HISTFILE="$HOME/.zsh_history"
(( HISTSIZE >= 10000 )) || HISTSIZE=10000
(( SAVEHIST >= 10000 )) || SAVEHIST=10000
setopt append_history inc_append_history hist_ignore_dups hist_ignore_space hist_reduce_blanks

# Komentarze w wierszu poleceń jak w bashu (w zsh domyślnie wyłączone).
setopt interactive_comments
setopt no_beep

# ── uzupełnianie ──
if (( ! ${+functions[compdef]} )); then
    autoload -Uz compinit
    mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
    compinit -d "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump-$ZSH_VERSION"
fi
zstyle ':completion:*' menu select
# małe litery pasują też do wielkich (jak completion-ignore-case w readline)
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
[[ -n "$LS_COLORS" ]] && zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# ── klawisze ──
# Tryb emacs jak w bashu. zsh sam wybiera vi, gdy $EDITOR zawiera „vi”
# (np. nvim) — kto chce vi, wpisuje `bindkey -v` w sekcji „zsh only”.
bindkey -e
# Home/End/Delete i Ctrl+strzałki: alacritty wysyła obie odmiany sekwencji.
for _key in '^[[H' '^[OH' '^[[1~'; do bindkey "$_key" beginning-of-line; done
for _key in '^[[F' '^[OF' '^[[4~'; do bindkey "$_key" end-of-line; done
unset _key
bindkey '^[[3~' delete-char
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word

# ── prompt ──
# Jak domyślny PS1 basha w Archu: [user@host katalog]$ (# dla roota).
# Tylko gdy prompt to wciąż domyślny zsh — cudzy motyw zostaje.
if [[ "$PROMPT" == '%m%# ' ]]; then PROMPT='[%n@%m %1~]%# '; fi
