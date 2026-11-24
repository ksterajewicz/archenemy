# =============================================
#   archenemy · SHARED layer · zsh look of the active rice
#   Sourced by config/shell/zsh-defaults.zsh (prompt section), i.e. inside
#   the "archenemy shell" block of ~/.zshrc and BEFORE your file
#   config/shell/shellrc, so anything you set there still wins.
#
#   Super+T links rices/<rice>/zsh to ~/.config/zsh. From there:
#   - colors.zsh: highlight/suggestion styles and the prompt colours of the
#     rice. Loaded only when ~/.config/zsh is the archenemy rice link, never
#     a zsh directory of your own (e.g. ZDOTDIR=~/.config/zsh).
#   - prompt: only while it is still the default one ([user@host dir]$ from
#     zsh-defaults.zsh or the bare zsh default). A theme of your own, set
#     earlier in ~/.zshrc, stays untouched.
#   - Starship (optional package): if it is installed, STARSHIP_CONFIG points
#     to the rice's starship.toml, unless you use Starship with your own
#     config (~/.config/starship.toml or another STARSHIP_CONFIG). With the
#     default prompt it also starts Starship; ARCHENEMY_ZSH_STARSHIP=0
#     (before the archenemy block) turns that off.
#   After a rice switch: a new terminal (or `exec zsh`) loads the new colours;
#   a running Starship prompt follows the link at the next prompt.
#
#   Written in the subset shared by zsh and bash, so tests/zsh-rice-look.sh
#   can run it without zsh. Expects archenemy_shell_dir (set by the block).
# =============================================

archenemy_look_dir="$HOME/.config/zsh"
archenemy_look_rices="$(readlink -f -- "${archenemy_shell_dir:-.}/../../rices" 2>/dev/null)"
archenemy_look_real="$(readlink -f -- "$archenemy_look_dir" 2>/dev/null)"

# ~/.config/zsh is ours only as a link into <archenemy>/rices/<rice>/zsh.
if [[ -n "$archenemy_look_rices" && -L "$archenemy_look_dir" \
    && "$archenemy_look_real" == "$archenemy_look_rices"/*/zsh \
    && -r "$archenemy_look_dir/colors.zsh" ]]; then

    . "$archenemy_look_dir/colors.zsh"

    # Default prompt only: the Arch-like one from zsh-defaults.zsh or zsh's own.
    archenemy_look_default=0
    if [[ "${PROMPT-}" == '[%n@%m %1~]%# ' || "${PROMPT-}" == '%m%# ' ]]; then
        archenemy_look_default=1
    fi

    # Starship as the prompt engine, with the rice's config.
    archenemy_look_starship="$archenemy_look_dir/starship.toml"
    if [[ "${ARCHENEMY_ZSH_STARSHIP:-1}" != 0 && -r "$archenemy_look_starship" ]] \
        && command -v starship >/dev/null 2>&1; then
        if [[ "${STARSHIP_CONFIG-}" == "$archenemy_look_starship" ]] \
            || [[ -z "${STARSHIP_CONFIG-}" && ! -e "$HOME/.config/starship.toml" ]]; then
            export STARSHIP_CONFIG="$archenemy_look_starship"
            # Not started yet (no prompt_starship_precmd) and the prompt is
            # still the default: start it. Already started earlier in
            # ~/.zshrc: it reads STARSHIP_CONFIG at every prompt anyway.
            if [[ "$archenemy_look_default" == 1 ]] \
                && ! typeset -f prompt_starship_precmd >/dev/null 2>&1; then
                eval "$(starship init zsh)"
                archenemy_look_default=0
            fi
        fi
    fi

    # Without Starship: the same [user@host dir]$ prompt in the rice colours
    # (ARCHENEMY_PROMPT_* from colors.zsh, only #RRGGBB accepted).
    if [[ "$archenemy_look_default" == 1 ]]; then
        archenemy_look_ok=1
        for archenemy_look_c in "${ARCHENEMY_PROMPT_TEXT-}" "${ARCHENEMY_PROMPT_PATH-}" \
            "${ARCHENEMY_PROMPT_OK-}" "${ARCHENEMY_PROMPT_ERROR-}"; do
            [[ "$archenemy_look_c" == \#[[:xdigit:]][[:xdigit:]][[:xdigit:]][[:xdigit:]][[:xdigit:]][[:xdigit:]] ]] \
                || archenemy_look_ok=0
        done
        if [[ "$archenemy_look_ok" == 1 ]]; then
            PROMPT="%F{$ARCHENEMY_PROMPT_TEXT}[%n@%m %F{$ARCHENEMY_PROMPT_PATH}%1~%F{$ARCHENEMY_PROMPT_TEXT}]%(?.%F{$ARCHENEMY_PROMPT_OK}.%F{$ARCHENEMY_PROMPT_ERROR})%#%f "
        fi
        unset archenemy_look_ok archenemy_look_c
    fi
    unset archenemy_look_default archenemy_look_starship
fi
unset archenemy_look_dir archenemy_look_rices archenemy_look_real
