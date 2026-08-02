---
name: waybar-design
description: Filozofia designu, tokeny palet i inwarianty Waybara w archenemy. Czytaj przed KAŻDĄ pracą wizualną nad Waybarem — zmianą style.css lub config.jsonc, nowym modułem, tooltipem, adaptacją paska do nowego rice'a. Frazy: waybar, pasek, wyspa, moduł paska, tooltip, kalendarz zegara, styl rice'a.
---

# waybar-design — jak projektować pasek w archenemy

> Odtworzony 2026-08-02 z mózgu AI-brain (dziennik decyzji projektu) i żywego
> kodu rice'ów — oryginał zaginął przy przebudowie historii repo 2026-07-17.
> Wszystkie tokeny poniżej pochodzą z realnych plików `rices/*/waybar/`.

## Filozofia

- **NASA-grade minimalizm**: czysta typografia, techniczny umiar, zero ozdób,
  które nie niosą informacji. Niezawodność ponad efektowność; szybkość
  odczuwalna — animacje krótkie (200 ms), bez lagujących efektów.
- **Wygląd jest per rice, zachowanie jest wspólne.** Każdy rice ma własną
  paletę i charakter, ale ten sam zestaw modułów, te same skrypty backendu
  i tę samą ergonomię. Zmiana funkcjonalna → wszystkie rice'y (parytet);
  zmiana wizualna → tylko dany rice.
- **Kierunek wizualny zadaje właściciel.** Nowe elementy dekoracyjne,
  odstępstwa od palety, nowe moduły — wymagają jego decyzji. Agent dopieszcza
  detale w ramach istniejącego języka wizualnego, nie forsuje własnych pomysłów.

## Szkielet paska (wspólny dla wszystkich rice'ów)

```jsonc
"layer": "top", "position": "top",
"height": 32, "spacing": 0,
"margin-top": 4, "margin-left": 8, "margin-right": 8,
"reload_style_on_change": true,
"modules-left":   ["hyprland/workspaces", "hyprland/window"],   // tron ma dodatkowo custom/launcher na starcie
"modules-center": ["clock"],
"modules-right":  ["custom/profileswitcher", "custom/micmute", "pulseaudio", "network", "battery", "tray"]
```

Kompozycja „wysp": `.modules-left` i `.modules-right` to półprzezroczyste
pigułki, `#clock` jest osobną wyspą w centrum, `.modules-center` przezroczysty.

## INWARIANTY (nie łam ich)

1. **Równe odstępy 4 px**: `margin-top: 4` paska = `gaps_out` górny w hyprland
   rice'a = przerwa pasek↔krawędź = przerwa pasek↔okno. Zmieniasz jedno —
   sprawdzasz wszystkie. Konsekwencja dla tronu: `shadow.range` okien ≤ 4,
   inaczej glow wchodzi pod pasek (naprawione 2026-07-23, nie cofać).
2. **Blur warstwy**: hyprland rice'a ma `layer_rule` `blur` + `ignore_alpha 0.5`
   na namespace `waybar` — tła wysp muszą mieć alfa ≥ ~0.5, żeby blur je łapał;
   piksele bardziej przezroczyste są celowo bez blura.
3. **Moduły chodzą przez backend archenemy, nigdy bezpośrednio po narzędziach**:
   profil mocy = `scripts/waybar/profile-get.sh` (exec, interval 1, signal 8)
   + `profile-switch.sh` (on-click) — NIGDY `asusctl` wprost; mikrofon =
   `wpctl` (signal 9); sieć on-click = `scripts/rofi/rofi_network.sh`;
   scroll workspace'ów = `scripts/hypr/ws-scroll.sh` (czyta tryb shared/decades).
4. **Workspace'y**: `"format": "{name}"` + `"all-outputs": false` — działa
   w OBU trybach workspace'ów. Nie hardkodować numerów ani nazw monitorów.
5. **Rewrite tytułów okna** dopasowany do `$terminal`/`$browser` rice'a
   (wszystkie rice'y: Alacritty, Brave) — zmiana terminala/przeglądarki
   w hyprland rice'a = aktualizacja rewrite.
6. **Zero danych maszynowych** w plikach trackowanych (nazwy monitorów, GPU,
   hostname) — to warstwa maszynowa, nie waybar.
7. **`white-blue_beta` jest zamrożona**: tylko naprawy tego, co już ma; żadnych
   nowych modułów ani efektów.
8. Binarka użyta w module musi być pokryta przez `packages/requirements-*.txt`
   (albo wywołanie zabezpieczone `command -v`).

## Tokeny palet

### white-blue (rice referencyjny) — „zimna biel + błękit"

| Token | Wartość |
|---|---|
| akcent / aktywny | `#0148ED` (jaśniejszy wariant `#4A7FFF` w hyprland border) |
| tekst | `#0a0a0a` |
| tekst przygaszony (sekundy, nieaktywne ws) | `#909090` (puste ws `#c8c8c8`, tytuł okna `#606060`) |
| tło wyspy | `rgba(255,255,255,0.40)` + border `rgba(1,72,237,0.10)` 0.5px |
| tooltip | tło `rgba(255,255,255,0.97)`, border `rgba(1,72,237,0.15)`, radius 8 |
| promienie | wyspy 14, pigułki ws 10, krytyczna bateria 9 |
| font | Iosevka Nerd Font 12px (zegar 12.5px, letter-spacing 0.04em) |
| stany | hover `rgba(1,72,237,0.08)`; active/urgent/critical = pełny `#0148ED` z białym tekstem |

**Zasada „no glow"**: żadnych box-shadow/text-shadow w white-blue. Jedyna
animacja stanu: rozszerzająca się pigułka aktywnego workspace'a
(`padding` z `cubic-bezier(0.25,0.10,0.25,1.00)` 200 ms) + `pulse` krytycznej baterii.

### tron — neon cyjan na ciemnym HUD (glow = świadome odstępstwo per-rice)

| Token | Wartość |
|---|---|
| neon / aktywny | `#00e5ff`, hover `#7df9ff` |
| tekst | `#9adbe8` (zegar `#cfeef7`) |
| przygaszony | `#4a7a8a`, puste ws `#2e4a55` |
| alarm (urgent/critical) | pomarańcz CLU `#ff7b1c`; warning `#ffb454` |
| tło wyspy | gradient 180° `rgba(7,22,30,0.62)→rgba(2,10,15,0.55)` + border `rgba(0,229,255,0.28)` 1px |
| glow wyspy | `box-shadow: 0 0 8px rgba(0,229,255,0.25), inset 0 1px 0 rgba(0,229,255,0.18)` (poświata + świecąca górna krawędź, symetrycznie na wszystkich wyspach) |
| tooltip | tło `rgba(4,16,22,0.97)`, border `rgba(0,229,255,0.35)`, radius 6 |
| promienie | ostre: wyspy 6, pigułki 4 |
| sygnatura | `custom/launcher` „portal do Gridu": glyph Archa `#00e5ff` 15px z `text-shadow` cyjanowym, hairline po prawej; on-click rofi, PPM power menu |
| aktywny ws | ciemny tekst `#020a0f` na świecącym cyjanie |

### asia-n-rice — mauve na granacie, płasko (wierność źródłu)

| Token | Wartość |
|---|---|
| mauve (kolor okna#waybar) | `#b47687` |
| tekst modułów | `#fefefe`, hover `#5c5c5c` |
| przygaszone/szarości | `#5c5c5c`, `#888888`, `#b0b0b0` |
| tło wyspy | `rgba(42,52,68,0.55)` (granat), bordery ledwie widoczne |
| tooltip | tło `rgba(10,10,10,0.95)`, tekst `#e8e8e8`, radius 8 |
| promienie | miękkie: wyspy 14, pigułki 11 |
| font | IosevkaTerm Nerd Font (jedyny rice z innym fontem) |
| aktywny ws | `#e8e8e8` z ciemnym tekstem; stany baterii w szarościach (nie w mauve) |

BEZ glow, BEZ gradientów — płaskość jest cechą tego rice'a. Martwe reguły
`#memory/#cpu/#temperature` w CSS zostają (wierność źródłu — decyzja 2026-07-18).

## Biblioteka wzorców

- **Nowy moduł**: wpis w `config.jsonc` KAŻDEGO rice'a (parytet funkcjonalny)
  + styl w `style.css` KAŻDEGO rice'a w jego palecie (wygląd per rice); backend
  do `scripts/waybar/`; odśwież przez `"signal"` (kolejny wolny numer; zajęte:
  8 profil, 9 micmute), nie przez krótszy interval.
- **Przygaszanie fragmentu formatu** (np. sekundy zegara): indeksowany
  placeholder fmt `{0:%H:%M}<span color='…'>:{0:%S}</span>` — zwykłe `{:…}`
  użyte dwa razy NIE działa.
- **Kalendarz zegara** (wzorzec od 2026-08-02): tooltip `<tt>…{calendar}</tt>`
  + `calendar: { mode: month, weeks-pos: left, on-scroll: 1, iso8601: true }`
  (tydzień od poniedziałku, numeracja `{:%V}`) + `format` w palecie rice'a
  (weeks przygaszone) + `actions: { on-click-right: mode, on-scroll-up:
  shift_up, on-scroll-down: shift_down }`. LPM zostaje domyślnym przełącznikiem
  `format-alt`. UWAGA: `shift_reset` nie istnieje w waybar 0.15 — nie używać.
- **Stan krytyczny**: pełne tło w kolorze alarmowym rice'a + `font-weight: 700`
  + animacja `pulse` 1 s tylko gdy nie ładuje (`#battery.critical:not(.charging)`).
- **Tooltipy**: styluj przez `tooltip` i `tooltip label` w style.css rice'a;
  treść pango w config.jsonc; kontrast sprawdzaj wobec TŁA TOOLTIPA rice'a
  (nie tła paska) — kolory kalendarza white-blue są ciemne, tronu jasne.
- **Ikony**: glyphy Nerd Fonts wprost w stringach formatów (`󰣇`, `󰓅`, `󰖟`).

## Checklista przed oddaniem pracy

1. Zmiana funkcjonalna wdrożona we WSZYSTKICH aktywnych rice'ach, wizualna
   w palecie właściwego rice'a? Beta nietknięta (chyba że bug-fix)?
2. JSONC parsuje się (komentarze poza stringami), CSS bez błędów składni?
3. Kontrast na tle wyspy ORAZ tooltipa danego rice'a sprawdzony?
4. Inwariant 4 px i blur/ignore_alpha nienaruszone?
5. Nowa binarka pokryta w `packages/`? Danych maszynowych brak?
6. Rzeczy sprawdzalne tylko na żywo wypisane po imieniu w raporcie
   (render fontów, glow, tooltip, sygnały)?
