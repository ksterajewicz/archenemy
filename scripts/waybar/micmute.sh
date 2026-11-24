#!/usr/bin/env bash
# =============================================
#   archenemy - micmute.sh
#   Ikona mikrofonu w waybarze (moduł custom/micmute, return-type json,
#   2026-11-24). Wcześniej exec był jednolinijkowcem w config.jsonc i
#   wypisywał sam glif — bez klasy CSS nie miał czego przygasić, więc
#   wyciszony mikrofon świecił jak włączony (zgłoszenie właściciela
#   2026-11-24). Teraz klasa "muted" / "unmuted"; kolor przygaszenia
#   daje #custom-micmute.muted w rices/*/waybar/style.css — ten sam co
#   wyłączony Bluetooth, wyciszona głośność i włączone „nie przeszkadzać”
#   (pilnuje tests/waybar-dimmed.sh).
#
#   Stan z "wpctl get-volume @DEFAULT_AUDIO_SOURCE@" ("Volume: 0.40" albo
#   "Volume: 0.40 [MUTED]"). Brak wpctl, błąd albo zawieszony PipeWire
#   (limit 2 s) → "unmuted", jak dawny jednolinijkowiec; kod wyjścia
#   zawsze 0 (niezerowy chowa moduł bez śladu).
#
#   Odświeżanie bez zmian: config ma "interval": 1 i "signal": 9
#   (on-click przełącza wyciszenie i woła pkill -RTMIN+9 waybar).
#
#   Użycie: micmute.sh   (woła waybar; jedna linia JSON, kod zawsze 0)
# =============================================

set -uo pipefail
export LC_ALL=C

SOURCE="@DEFAULT_AUDIO_SOURCE@"
GLYPH_MUTED="󰍭"     # U+F036D nf-md-microphone_off
GLYPH_UNMUTED="󰍬"   # U+F036C nf-md-microphone

state=unmuted
if command -v wpctl >/dev/null 2>&1; then
    raw="$(timeout 2 wpctl get-volume "$SOURCE" 2>/dev/null)"
    [[ "$raw" == *"[MUTED]"* ]] && state=muted
fi

if [[ "$state" == muted ]]; then text="$GLYPH_MUTED"; else text="$GLYPH_UNMUTED"; fi
# Same stałe napisy — JSON składany ręcznie.
printf '{"text":"%s","alt":"%s","class":"%s"}\n' "$text" "$state" "$state"
exit 0
