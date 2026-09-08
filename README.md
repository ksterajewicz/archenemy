# archenemy

Osobisty rice Arch Linuxa pod Hyprlanda. Jeden instalator stawia cały wygląd pulpitu — pasek, powiadomienia, terminal, ekran blokady — i pozwala przełączać się między motywami (rice'ami) jednym skrótem. Konfiguracja specyficzna dla Twojej maszyny (monitory, karta graficzna, autostart) jest generowana lokalnie i nie trafia do gita.

## Gałęzie

- **dev** — gałąź główna, tu lądują wszystkie zmiany
- **main** — tylko stabilne wydania, aktualizowana gdy dev jest stabilny

## Wymagania

- Arch Linux z Hyprlandem (instalator zaproponuje instalację, jeśli go brak)
- **hyprpaper >= 0.8** — używamy nowej składni `wallpaper {}` i IPC `hyprctl hyprpaper wallpaper "mon, path, fit_mode"`

## Zanim zainstalujesz

Przeczytaj cały ten plik. Projekt podmienia foldery w `~/.config` — instalator proponuje kopię zapasową (ląduje w `~/archenemy/backups/`), ale zachowaj ostrożność.

## Instalacja

1. Sklonuj repozytorium do katalogu domowego:

```bash
cd ~
git clone https://github.com/ksterajewicz/archenemy
```

2. Wejdź do folderu instalatora i nadaj skryptom prawa wykonywania:

```bash
cd ~/archenemy/install/
chmod +x install.sh cpudrivers-installation.sh gpudrivers-installation.sh kernel-install.sh
```

3. Uruchom instalator:

```bash
./install.sh
```

Instalator: wykryje i skonfiguruje monitory (w tym ich numerację lewa→prawa i tryb workspace'ów — patrz sekcja „Workspace'y"), zainstaluje pakiety z `packages/`, ustawi przełącznik profili zasilania (ASUS ROG / uniwersalny — typ sprzętu wykrywany z DMI jako podpowiedź; na ASUS-ach instaluje z AUR `asusctl-devel-git`, który dostarcza także `rog-control-center`, więc ten drugi NIE jest instalowany osobno; bez działającego asusctl automatyczny fallback na power-profiles-daemon, na końcu samokontrola `profile-get.sh`), opcjonalnie odpali instalatory mikrokodu CPU / sterowników GPU / kernela, wygeneruje pliki maszynowe, podlinkuje domyślny rice do `~/.config`, ustawi pierwszą tapetę (jeśli jakaś jest w `wallpapers/`) i zadba o usługi: NetworkManager, audio (pipewire-pulse), asusd na ASUS-ach, opcjonalnie UFW i bluetooth.

**Aktualizujesz działającą maszynę po `git pull`?** Uruchom `install.sh` ponownie — wygeneruje brakujące pliki maszynowe.

## Jak to jest poukładane — cztery warstwy

| Warstwa | Gdzie mieszka | W gicie? |
|---|---|---|
| **Rice** (wygląd) | `rices/<nazwa>/` — foldery podlinkowywane do `~/.config` | ✅ |
| **Wspólne** (skróty, klawisze media) | `config/hypr/*.lua` | ✅ |
| **Maszyna** (monitory, GPU, klawisze sprzętowe) | `config/hypr/*-monitors/keys/env*.lua` — generuje `install.sh` | ❌ |
| **Osobiste** (Twój autostart, Twoje skróty do aplikacji) | `config/hypr/autostartpersonalisation.lua`, `config/hypr/appbinds.lua` | ❌ |

Dzięki temu to samo repo działa na każdej maszynie i nic prywatnego nie wycieka na GitHuba.

**Config Hyprlanda jest w Lua** (od Hyprlanda 0.55 stary format hyprlang
`.conf` jest przestarzały): każdy rice ma `hypr/hyprland.lua`, warstwy
wspólna/maszynowa/osobista to też pliki `.lua` dołączane przez `require()`.
Konwencja repo: jeden bind = jedna linia `hl.bind(...)` — na tym polegają
menedżer skrótów Super+A i guard workspace'ów. Wyjątki od migracji:
`hyprlock.conf` i `hyprpaper.conf` zostają w hyprlangu (to osobne programy,
nie Hyprland). Stare pliki `.conf` leżą obok jako `*.conf.bak` do czasu
zweryfikowania migracji na żywej maszynie. Tło ekranu blokady każdego rice'a
(`background { ... }`) jest wydzielone przez `source =` do generowanego
`config/hypr/hyprlock-background-<rice>.conf` — zmieniasz je checkboxem w
`Super + W`, nie edycją `hyprlock.conf`.

## Struktura plików

```
archenemy/
├── install/
│   ├── install.sh                    # Główny instalator. Prowadzi za rękę przez całą konfigurację.
│   ├── bootloader.sh                 # Biblioteka: wykrywa bootloader i regeneruje config (GRUB auto,
│   │                                 #   systemd-boot = instrukcja ręczna). Źródłowana przez cpu/kernel.
│   ├── cpudrivers-installation.sh    # Mikrokod CPU (Intel/AMD) — wykrywa procesor, instaluje i regeneruje bootloader.
│   ├── gpudrivers-installation.sh    # Sterowniki GPU — wykrywa kartę; NVIDIA: open/własnościowy, modeset,
│   │                                 #   initramfs; a gdy sterownik już jest: aktualizacja (-Syu) / zmiana wariantu.
│   │                                 #   Do gier: włącza repo [multilib] i stawia lib32 (Steam/Proton/Wine).
│   └── kernel-install.sh             # Instalacja alternatywnego kernela (zen/lts) + regeneracja bootloadera.
├── packages/
│   ├── requirements-pacman.txt       # Pakiety wymagane (oficjalne repo).
│   ├── requirements-aur.txt          # Pakiety wymagane (AUR).
│   ├── additional-packages-pacman.txt # Pakiety opcjonalne (oficjalne repo).
│   └── additional-packages-aur.txt   # Pakiety opcjonalne (AUR).
├── config/
│   └── hypr/
│   │   ├── workspaces.lua            # Autostart guarda workspace'ów (wspólny dla wszystkich maszyn).
│   │   ├── keyboard.lua              # Klawisze multimedialne (wspólne).
│   │   ├── gpu_wayland_scaling.lua   # Uniwersalne zmienne Wayland (wspólne).
│   │   ├── custom_window_rules.lua   # Reguły okien (wspólne).
│   │   │   # (obok leżą *.conf.bak — stare wersje hyprlang do usunięcia
│   │   │   #  po zweryfikowaniu migracji na żywej maszynie)
│   │   # + pliki generowane przez install.sh (poza gitem):
│   │   # monitorshyprl.lua, workspaces-monitors.lua, hardware-keys.lua,
│   │   # gpu-env.lua, autostartpersonalisation.lua, autostart-apps.lua, appbinds.lua,
│   │   # hyprpaper.conf (hyprpaper nie migruje na Lua; rice'y wskazują
│   │   # na niego symlinkiem), hyprlock-background-<rice>.conf ×3
│   │   # (tło hyprlocka; rice'y wskazują na nie przez `source =`)
├── rices/
│   ├── white-blue/                   # Domyślny rice: alacritty, fastfetch, hypr(+hyprlock), mako,
│   │                                 #   MangoHud, networkmanager-dmenu, nvim, rofi, waybar.
│   ├── white-blue_beta/              # Pierwotny wygląd, trzymany do wglądu/odwrotu.
│   │                                 #   mako i hyprlock dziedziczy z white-blue (symlinki w repo).
│   ├── tron/                         # Tron: Legacy — ciemny neon (cyjan + pomarańcz CLU), glow,
│   │                                 #   rogi 4-6px. Własny fastfetch (logo Archa w cyjanie) + launcher
│   │                                 #   w waybarze i motyw nvim (neon cyjan);
│   │                                 #   networkmanager-dmenu z white-blue (symlink).
│   ├── asia-n-rice/                  # Mauve/róż na granacie, płaski look. Własny hypr, rofi,
│   │                                 #   mako, hyprlock, alacritty, waybar i motyw nvim (mauve);
│   │                                 #   fastfetch domyślny;
│   │                                 #   MangoHud/networkmanager-dmenu z white-blue (symlinki).
│   └── dither-flux/                  # Dither art + algorithmic art w palecie deszczowej
│                                     #   milford-woda: zero zaokrągleń, bez blura i poświat,
│                                     #   ramki 1 px, płaskie płyty. Własny komplet warstw;
│                                     #   networkmanager-dmenu z white-blue (symlink).
├── scripts/
│   ├── appbinds/                     # Terminalowy menedżer skrótów do aplikacji (Super+A);
│   │                                 #   [w] przełącza tryb workspace'ów shared/decades na żywo;
│   │                                 #   [v] przełącza styl paska głośności w waybarze;
│   │                                 #   [t] timer waybara: włącz/wyłącz, domyślny czas, kolor;
│   │                                 #   autostart-picker.sh — [u] wybór aplikacji do autostartu
│   │                                 #   (checkboxy + filtr, czysty bash).
│   ├── changing-theme-scripts/       # Po jednym stubie na rice (nazwa pliku = pozycja w menu);
│   │                                 #   wspólna logika przełączania w lib/switch-rice.sh.
│   ├── hypr/                         # workspace-orphan-guard.sh — demon (tylko tryb decades): scala
│   │                                 #   workspace'y-sieroty z ekranem, który jest — koniec z podwójną
│   │                                 #   „1" na pasku. ws-scroll.sh — scroll waybara wg trybu workspace'ów.
│   │                                 #   workspace-mode-switch.sh — przełącza shared/decades na żywo
│   │                                 #   (regeneracja + reload + guard); lib/gen-workspaces.sh — wspólny
│   │                                 #   generator reguł/bindów workspace'ów (współdzielony z install.sh);
│   │                                 #   lib/gen-autostart.sh — generator autostart-apps.lua
│   │                                 #   (współdzielony z install.sh i pickerem z Super+A → [u]).
│   ├── rofi/                         # Menu rofi: rice'y, tapety, sieć (z reskanem), zasilanie.
│   ├── wallpapers/                   # Matematyczne generatory tapet (czysty Python, zero zależności):
│   │                                 #   logo Archa (gen_arch_wallpaper.py), siatka Tron
│   │                                 #   (gen_tron_wallpaper.py) i generatywne tapety ditherowe
│   │                                 #   rice'a dither-flux (gen_dither_flux_wallpaper.py);
│   │                                 #   flux-wall.sh — start/stop tapety liczonej shaderem.
│   └── waybar/                       # Przełącznik profili zasilania (asus/uniwersalny) +
│                                     #   volume-bar.sh — pasek głośności zamiast modułu pulseaudio;
│                                     #   styl line/ticks/solid przełączalny w Super+A → [v].
│                                     #   timer.sh + timer-ctl.sh — timer (odliczanie) obok zegara,
│                                     #   opcjonalny, włączany w Super+A → [t];
│                                     #   lib/timer-state.sh — wspólny odczyt/zapis stanu timera.
├── src/
│   └── flux-wall/                    # Tapeta liczona shaderem na GPU (C, wlr-layer-shell + EGL/GLES 3):
│       ├── main.c                    #   jedna powierzchnia na monitor, uniformy: resolution, time,
│       ├── test.c                    #   paleta rice'a, detail (z baterii); testy funkcji czystych;
│       ├── Makefile                  #   kod protokołów generuje wayland-scanner z XML-i w repo;
│       ├── protocols/                #   wlr-layer-shell + xdg-shell (XML, licencja MIT/X11);
│       └── shaders/                  #   animacje do wyboru w Super+W: dither-flux (domain warping),
│                                     #   dither-waves (interferencja), dither-drift (wędrujące ziarno).
│                                     #   Buduje install.sh [9.6]; build/ poza gitem.
└── wallpapers/                       # Tapety (w gicie) — dowolne pliki, opcjonalnie w folderach zestawów.
    ├── arch-white/                   # Zestaw: logo Archa (#0148ED) na bieli — v1 1920x1080, v2 2560x1600.
    ├── tron-grid/                    # Zestaw: siatka Tron (neon cyjan na #020A0F) — v1/v2 jak wyżej.
    └── dither-flux/                  # Zestaw: 3 formy generatywne (pole przepływu ×2, atraktor) w rastrze
                                      #   Bayera, paleta milford-woda — v1/v2 z repo; generated/ (poza gitem)
                                      #   = te same formy pod REALNE monitory, install.sh [9.7].
```

## Tapety

Tapety mieszkają w `wallpapers/` (mogą być luzem albo w podfolderach) i są wersjonowane w gicie — świeża instalacja ma je od razu. Wyjątek: zestaw `dither-flux` jest **generowany pod realne monitory** — `install.sh` krok **[9.7]** czyta rozdzielczości i role z `data/monitors/*.dat` (primary → `v1`, secondary → `v2`, dalsze → `m-<nazwa>`; tryby nazwane jak `preferred` dopytuje `hyprctl`) i w tle uruchamia `gen_dither_flux_wallpaper.py` do `wallpapers/dither-flux/generated/` (poza gitem; log `generate.log`). Raster 1 px nie znosi skalowania, więc tapeta musi mieć dokładnie rozdzielczość ekranu. Pliki `v1`/`v2` z repo zostają jako zestaw awaryjny.

Na górze menu `Super+W` (gdy flux-wall jest zbudowany) są też pozycje **`Animation: <nazwa>`** — jedna na każdy shader w `src/flux-wall/shaders/` — oraz **`Animation: off`**. Wybór animacji nie zmienia tapety hyprpapera: animacja rysuje nad nią i działa w **każdym** rice'ie, w jego palecie (deklaracja `rices/<rice>/flux-wall.conf`). Wybór jest zapamiętywany w `data/flux-wall.dat` i przeżywa `Super+T` oraz restart; `off` wyłącza animację wszędzie, a usunięcie pliku przywraca domyślne zachowanie rice'a (dither-flux: włączona, pozostałe: wyłączona). Przełączanie: `Super + W` — menu pokazuje wszystkie obrazy (jpg/jpeg/png/webp), na górze dwa checkboxy: `[x] Upload to all monitors` (domyślnie zaznaczony — tapeta na wszystkie monitory zamiast tylko na ten z fokusem) i `[ ] Set as hyprlock background (no blur)` (domyślnie odznaczony — zaznaczenie ustawia wybrany obraz jako tło ekranu blokady bez blura, zamiast domyślnego żywego zrzutu ekranu + blur; przeżywa przełączenie rice'a).

Na górze menu jest przełącznik **`[x] Upload to all monitors`** (domyślnie zaznaczony):

- **Zaznaczony** — tapeta trafia na wszystkie monitory. Jeśli obok wybranego pliku `*v1*`/`*v2*` leży druga połowa pary, monitor główny dostaje `v1`, dodatkowy `v2`; bez pary — ten sam obraz wszędzie.
- **Odznaczony** (kliknij pozycję, żeby przełączyć) — tapeta trafia tylko na monitor, na którym masz fokus; pozostałe zostają bez zmian.

Wybór per-monitor jest pamiętany w `data/wallpaper.dat` i przywracany przy zmianie rice'a. Który monitor jest „główny" ustalasz przy instalacji (rola primary/secondary) — instalator sam proponuje: pierwszy = primary, drugi = secondary.

Rola dotyczy **tylko tapet** (primary→v1, secondary→v2). Przydziałem workspace'ów rządzi co innego: **numeracja monitorów lewa→prawa** i **tryb workspace'ów** — oba ustawiane przy instalacji (patrz sekcja „Workspace'y").

## Animowana tapeta liczona shaderem (flux-wall)

`src/flux-wall` to mały klient Waylanda (C, ~600 linii): otwiera powierzchnię na warstwie tła (`wlr-layer-shell`) osobno na każdym monitorze, zakłada kontekst EGL z GLES 3.0 i w każdej klatce rysuje jeden fragment shader. Tapeta nie jest plikiem ani wideo — jest **kodem**: nie ma pętli, nie powtarza się, liczy się natywnie w pikselach fizycznych monitora (raster Bayera 1 px bez skalowania) i zmienia paletę bez regenerowania czegokolwiek.

Shader (`src/flux-wall/shaders/dither-flux.frag`) dostaje uniformy: `resolution`, `time`, `palette_bg`/`palette_ink`/`palette_accent` (trzy kolory rice'a) i `detail` (0–1). **`detail` steruje szczegółowością z poziomu baterii** (`--battery`: `/sys/class/power_supply/BAT*`): mniej procent = mniej oktaw szumu i wolniejszy dryf, czyli mniej pracy GPU dokładnie wtedy, gdy energii ubywa; na zasilaniu sieciowym pełnia. Zmiana jest interpolowana płynnie.

**Rozdzielczość i skala.** Każdy monitor dostaje własną powierzchnię w rozmiarze, który podaje kompozytor, pomnożonym przez skalę — także **ułamkową** (`wp_fractional_scale_v1` + `wp_viewporter`: bufor ma rozmiar logiczny × np. 1.25 zaokrąglony do pikseli fizycznych, a viewport mapuje go na rozmiar logiczny). Raster jest 1:1 przy każdej rozdzielczości i skali ustawionej w `install.sh` [3.5]; bez tych protokołów wraca skala całkowita `wl_output`.

**Warstwa.** flux-wall rysuje na warstwie `bottom` — **nad** tapetą hyprpapera (warstwa `background`) i **pod** oknami. Hyprpaper działa zawsze i zostaje pod spodem: gdyby flux-wall padł albo nie został zbudowany, widać zwykłą tapetę. To jest cały fallback — bez osobnej logiki.

**Out of the box.** `install.sh` krok **[9.6]** buduje binarkę (`make -C src/flux-wall`; wymaga `base-devel wayland mesa` z `requirements-pacman.txt`; XML-e protokołów są w repo, więc `wayland-protocols`/`wlr-protocols` nie są potrzebne). Build jest opcjonalny z definicji — brak narzędzi albo błąd `make` ląduje w podsumowaniu instalatora, nigdy nie przerywa instalacji.

**Animacje do wyboru** (`src/flux-wall/shaders/`): `dither-flux` — domain warping, pole dryfuje bez końca; `dither-waves` — interferencja fal kołowych płynących od źródeł; `dither-drift` — kompozycja stoi, a wędruje samo ziarno rastra (skokowo, jak stary ekran). Każda w palecie bieżącego rice'a, każda z `detail` z baterii.

**Kto decyduje, co się wyświetla** — dwa źródła w tej kolejności: (1) wybór użytkownika z `Super+W` w `data/flux-wall.dat` (`off` albo nazwa animacji — działa w każdym rice'ie); (2) bez wyboru — deklaracja rice'a `rices/<rice>/flux-wall.conf`: `FLUX_WALL_PALETTE` (trzy kolory), `FLUX_WALL_SHADER` (domyślna animacja), `FLUX_WALL_ARGS` (`--battery`), `FLUX_WALL_AUTOSTART` (`1` tylko w `dither-flux`; `tron`, `white-blue`, `asia-n-rice` mają paletę, ale animację wyłączoną, dopóki jej nie wybierzesz). Autostart rice'a (`hyprland.lua`) i `Super+T` wołają `scripts/wallpapers/flux-wall.sh autostart`, który zatrzymuje instancję poprzedniego rice'a i startuje wg tych reguł. Brak binarki = cicho nic.

Ręcznie:

```
scripts/wallpapers/flux-wall.sh list                 # dostępne animacje
scripts/wallpapers/flux-wall.sh select dither-waves  # wybierz i zapamiętaj (to samo, co Super+W)
scripts/wallpapers/flux-wall.sh off                  # wyłącz i zapamiętaj
scripts/wallpapers/flux-wall.sh start -f 30          # uruchom wg reguł, opcje idą do flux-wall (log w $XDG_RUNTIME_DIR/flux-wall.log)
scripts/wallpapers/flux-wall.sh stop | status
```

Bezpośrednio: `flux-wall -s shader.frag [-p bg,ink,acc] [-d 0..1 | --battery] [-f fps] [-o nazwa-monitora] [-l bottom|background] [--once] [-v]`. Kody wyjścia: 1 argumenty/plik, 2 brak Waylanda lub layer-shell, 3 błąd EGL/shadera. Testy funkcji czystych (paleta, bateria): `make -C src/flux-wall test`.

## Rice'y

| Rice | Opis |
|---|---|
| `white-blue` | Domyślny. Biało-niebieskie szkło: zaokrąglone rogi, dostrojony blur, własne animacje, spójny akcent `#0148ED`, motyw mako + hyprlock + nvim (ręczny colorscheme w palecie rice'a). |
| `white-blue_beta` | Pierwotny wygląd biało-niebieski, trzymany do wglądu/odwrotu. Tylko poprawki funkcjonalne, bez zmian wizualnych. Mako i hyprlock dziedziczy z `white-blue` przez symlinki w repo. |
| `tron` | Tron: Legacy — ciemne szkło `#020A0F`, neon cyjan `#00E5FF` z poświatą (glow), pomarańcz CLU `#FF7B1C` tylko dla alarmów, rogi niemal ostre (4–6px). Własny motyw waybar (z launcherem „portal do Gridu" i podświetlanymi wyspami HUD), rofi (glif szukania), fastfetch (logo Archa w neonowym cyjanie), alacritty/mako/hyprlock (kinowa oprawa z neonowymi liniami)/MangoHud/nvim (ręczny colorscheme: neon cyjan na `#020A0F`, alarmy w pomarańczu CLU); networkmanager-dmenu dziedziczy z `white-blue` przez symlink w repo. Tapeta: zestaw `tron-grid` (generowany). |
| `asia-n-rice` | Przygaszony mauve/róż (`#b47687`) na ciemnym granacie (`#2a3444`), płaski look: waybar z zaokrąglonymi wyspami (14px) i kursywnymi tytułami okien, ostre rogi okien, ramka `#131a2a`. Wygląd zaadaptowany z zewnętrznego rice'a i przepięty pod backend archenemy: alacritty zamiast kitty, rofi zamiast wofi, warstwa maszynowa (GPU/monitory/workspace'y) przez `source`, bez cava. Własny motyw waybar/rofi/mako/hyprlock/alacritty w palecie mauve; fastfetch domyślny (bez przebarwienia); własny motyw nvim (ręczny colorscheme w palecie mauve, płaski — bez boldów); MangoHud i networkmanager-dmenu dziedziczy z `white-blue` przez symlinki. Bez własnej tapety — używa aktualnej (warstwa maszynowa). |
| `dither-flux` | Dither art + algorithmic art: tapety to generatywne pola (pole przepływu, atraktor Clifforda) kwantyzowane rastrem Bayera 8×8, w palecie deszczowej `milford-woda` z kadru Milford Sound — mokre góry `#0F1A24`, stalowa woda `#5C87A3`, mgła `#A8C4D4`, piana `#D8E6EE` jako akcent; bursztyn `#E0A23C` to jedyny ciepły kolor i służy wyłącznie alarmom. Geometria idzie za rastrem: **zero zaokrągleń**, ramki okien 1 px, **blur i cień wyłączone** (rozmycie i dither to sprzeczne materiały), wyspy waybara, rofi i mako jako płaskie, niemal nieprzezroczyste płyty. Własny komplet: waybar (z launcherem), rofi, alacritty (ANSI stonowane do palety, ale rozróżnialne), mako, swayosd, hyprlock (linie 1 px, bez poświaty), fastfetch (logo Archa w pianie), MangoHud, nvim (ręczny colorscheme); networkmanager-dmenu z `white-blue` przez symlink. Tapety: zestaw `dither-flux` z `gen_dither_flux_wallpaper.py`. |

Każdy rice to folder w `rices/`, którego podfoldery są linkowane do `~/.config`. Przełączanie: `Super + T` — menu pokazuje skrypty z `scripts/changing-theme-scripts/` (nazwa pliku `.sh` to etykieta w menu: `white-blue`, `white-blue_beta`). Przy przełączeniu stare symlinki rice'a są sprzątane, więc motywy się nie mieszają.

**Nowy rice:** utwórz `rices/<folder>/`, skopiuj `scripts/changing-theme-scripts/white-blue.sh` jako `<etykieta>.sh` i ustaw w nim `RICE_NAME` na nazwę swojego folderu. Skrypt to dwulinijkowy stub — cała logika przełączania siedzi we wspólnym `lib/switch-rice.sh`, więc nowy rice nie wymaga kopiowania żadnej logiki.

## Własne skróty do aplikacji (Super + A)

`Super + A` otwiera terminalowy menedżer skrótów: wybierasz klawisz (np. `g`, `F5`, `semicolon`) i polecenie (np. `spotify`), a skrót `Super + klawisz` działa od razu. Menedżer pilnuje kolizji z istniejącymi skrótami archenemy, a opcja `[s]` pokazuje pełną ściągę wszystkich obecnych skrótów — co jest pod którym klawiszem i jaką aplikację/akcję odpala. Twoje bindy trafiają do `config/hypr/appbinds.lua` — pliku osobistego poza gitem, więc przetrwają `git pull` i zmianę rice'a.

To samo TUI ma dodatkowe pozycje: `[w]` — przełącznik trybu workspace'ów shared/decades (sekcja „Workspace'y"), `[u] autostart apps` — wybór aplikacji odpalanych przy starcie Hyprlanda z listy wszystkich wpisów `.desktop` (checkboxy `[x]`/`[ ]`, filtrowanie po nazwie przez `/tekst`; wybór ląduje w `data/autostart-apps.dat`, a z niego generowany jest osobisty `config/hypr/autostart-apps.lua` — obok ręcznego `autostartpersonalisation.lua`, którego ta warstwa nie dotyka), `[v] volume bar` — styl paska głośności w waybarze (`line` ━━━━━━────, `ticks` ▮▮▮▮▮▮▯▯▯▯, `solid` ▬▬▬▬▬▬▬▬▬▬▬▬────────), zapisywany w `data/volume-bar-style.dat` i stosowany od razu (sygnał 10 do waybara), `[t] timer` — timer odliczający obok zegara (sekcja „Timer"), oraz `[p] update archenemy` — aktualizator repo: wybierasz gałąź (`dev` — najnowsze zmiany / `main` — tylko stabilne wydania), skrypt robi `git fetch`/`checkout`/`pull --ff-only`, a lokalne zmiany w plikach śledzonych przez git chowa `git stash` na czas pull i przywraca po nim. Warstwa maszynowa i osobista (monitory, appbinds, autostart, rice, styl paska głośności...) jest poza gitem, więc update jej nie rusza — Twoje ustawienia zostają domyślnie bez zmian. Na końcu proponuje ponowne uruchomienie `install.sh`, żeby dogenerować ewentualne nowe pliki maszynowe.

Menu główne TUI (Super+A) i potwierdzenia w podmenu (`[v]`, `[w]`, `[t]`, `[p]`) odpowiadają na jeden klawisz bez Entera (wyjątek: wpisywanie czasu i koloru w `[t]` kończysz Enterem) — `Escape` wychodzi/anuluje tak samo jak `q`/`N`.

Głośność: moduł `pulseaudio` waybara zastąpiony własnym `custom/volumebar` (skrypt `scripts/waybar/volume-bar.sh`) — rysuje pasek wypełnienia z procentem zamiast samej ikony. Scroll na pasku i klawisze głośności działają jak dotąd (klawisze sprzętowe dodatkowo wysyłają do waybara sygnał 10 = natychmiastowe odświeżenie paska). Klik: LPM `pavucontrol`, PPM mute. Trzy style do wyboru w `Super+A` → `[v]`: `line` (cienka kreska, 10 komórek), `ticks` (segmenty ▮▮▯, 10 komórek) i `solid` (gruby blok głośności na cienkiej linii, dłuższy — 20 komórek, po 5% na komórkę). Stan `>100%` (boost) ma osobną klasę koloru per rice. Ikona głośnika automatycznie zamienia się na słuchawki, gdy Active Port domyślnego sinka (z `pactl`) wskazuje na wyjście słuchawkowe — i wraca do głośnika po odpięciu; wykrywane w tym samym backstopie `interval:1`, bez osobnego triggera. Sam glif słuchawek siedzi w Iosevce niżej niż głośnik i mikrofon, więc skrypt podnosi go pango-spanem (`rise`) — wysokość korekty to jedna stała `ICON_RISE_HEADPHONES` na górze `volume-bar.sh` (dodatnia w górę, ujemna w dół, `0` = bez korekty).

Profil zasilania: moduł `custom/profileswitcher` pokazuje aktualny profil, a klik cyklicznie go zmienia. Na ASUS-ach ROG to samo robi **górny klawisz sprzętowy profilu** (`XF86Launch4`) — od 2026-09-07 idzie tą samą drogą co klik, czyli przez `scripts/waybar/profile-switch.sh`: zmiana jest weryfikowana w `/sys/firmware/acpi/platform_profile`, przy martwym `asusd` następuje automatyczny fallback na `power-profiles-daemon`, a gdy nie zadziała nic — pojawia się krytyczne powiadomienie z prawdziwym błędem narzędzia. Wcześniej klawisz wołał surowe `asusctl profile -n`, które potrafi wyjść kodem 0 nic nie zmieniając (klient nowszy od demona po aktualizacji bez restartu `asusd`) — wtedy pasek się odświeżał, profil zostawał stary i klawisz wyglądał na martwy. Bind jest w warstwie maszynowej (`config/hypr/hardware-keys.lua`, generowany przez `install.sh`), więc po aktualizacji repo wymaga ponownego biegu instalatora.

Jasność ekranu: klawisze `XF86MonBrightness*` wołają `swayosd-client` — zmieniają jasność i pokazują pasek OSD u dołu wszystkich monitorów (serwer `swayosd-server` startuje z każdym rice'em i jest restartowany przy przełączeniu rice'a, bo czyta motyw tylko przy starcie). Motyw OSD per rice: `rices/*/swayosd/style.css` (beta dziedziczy z white-blue przez symlink). Pakiet: `swayosd-git` (AUR).

## Timer

Opcjonalny timer odliczający, jako **osobna wyspa tuż po prawej od zegara**
(własna pigułka, nie doklejona do zegara). Domyślnie wyłączony — włączasz go
w `Super + A` → `[t] timer`, tam też ustawiasz domyślny czas (domyślnie 25 min)
i kolor cyfr: **czerwony `#ff0000` niezależnie od rice'a**, zmienialny na
dowolny `#rrggbb` wpisany w TUI. Kolor idzie przez pango prosto ze skryptu, więc
zmienia się wyłącznie kolor cyfr — pigułka pod spodem zostaje w palecie rice'a.

Sterowanie na pasku: **LPM** start / pauza / wznowienie (a na odliczonym timerze
— skasowanie alarmu), **PPM** reset do domyślnego czasu, **scroll** ±1 minuta
(działa tylko, gdy timer stoi albo jest zapauzowany — biegnącego odliczania
scroll nie rusza). Po dojściu do zera leci jedno powiadomienie (`notify-send`).
Odliczanie liczy się z zegara ściennego, więc przeładowanie waybara ani zmiana
rice'a go nie przesuwają. Wyłączenie timera w TUI chowa moduł całkowicie —
zegar wraca wtedy dokładnie na środek paska.

Ustawienia i stan mieszkają w warstwie maszynowej (poza gitem):
`data/timer-enabled.dat`, `timer-duration.dat`, `timer-color.dat`,
`timer-state.dat`. `white-blue_beta` timera nie ma (rice zamrożony —
tylko bugfixy).

## Skróty klawiszowe

### Aplikacje
| Skrót | Akcja |
|---|---|
| `Super + Enter` | Terminal (Alacritty) |
| `Super + E` | Menedżer plików (Thunar) |
| `Super + R` | Launcher aplikacji (Rofi) |
| `Super + B` | Przeglądarka (Brave) |
| `Super + S` | Launcher gier (Steam) — jeśli zainstalowany |
| `Super + N` | Menedżer sieci (z reskanem Wi-Fi) |
| `Super + T` | Przełącznik rice'ów |
| `Super + W` | Przełącznik tapet |
| `Super + L` | Ekran blokady (hyprlock) |
| `Super + K` | Zmiana układu klawiatury |
| `Super + A` | Menedżer własnych skrótów do aplikacji |
| `Super + prawy Shift` | Menu zasilania (wyłącz / restart); przy zablokowanym ekranie (hyprlock) — bezpośrednie wyłączenie, bez menu i potwierdzenia |

### Sterowanie oknami
| Skrót | Akcja |
|---|---|
| `Super + Q` | Zamknij okno |
| `Super + V` | Przełącz pływanie |
| `Super + F` | Pełny ekran |
| `Super + Shift + F` | Maksymalizacja (pasek zostaje) |
| `Super + P` | Pseudokafelkowanie |

### Workspace'y — dwa tryby do wyboru

Przy instalacji monitory dostają **numery 1, 2, 3… liczone od lewej do prawej** (instalator proponuje kolejność z pozycji ekranów; możesz ją poprawić) i wybierasz jeden z dwóch trybów:

- **`shared`** — 10 wspólnych workspace'ów (1-10) dla wszystkich monitorów. Monitor o numerze k ma „domowy" workspace k (tam otwiera się po starcie), ale `Super + 1..0` działa globalnie — workspace przywołujesz na ekran, na którym jesteś. Odporny na odpinanie monitora: workspace'y istnieją zawsze po jednym, więc nic się nie dubluje.
- **`decades`** — każdy monitor ma **własne** workspace'y liczone od 1 do 10 (izolowane dekady). Pasek pokazuje tylko workspace'y swojego monitora, `Super + 1..0` działa w obrębie monitora z fokusem. Kolejność dekad monitorów zewnętrznych idzie wg numeracji lewa→prawa; wyjątek: panel wbudowany laptopa (eDP/LVDS/DSI) zawsze trzyma pierwszą dekadę — to jedyny ekran, który istnieje zawsze, inaczej praca bez monitora zewnętrznego tworzyłaby workspace'y-sieroty (podwójna „1" na pasku). Po odpięciu monitora jego workspace'y scala demon-guard (okna z workspace'u N lądują na N); po ponownym podpięciu monitor dostaje z powrotem swoje.

Tryb przełączysz **na żywo** w TUI pod `Super + A` → `[w] workspace mode` (bez ponownego biegu instalatora): regeneruje reguły i bindy workspace'ów, przeładowuje Hyprlanda i w razie potrzeby startuje demona-guarda. Numerację monitorów nadal ustawia `install.sh` (tryb korzysta z zapisanej kolejności lewa→prawa). Uwaga: przeładowanie nie przenosi już otwartych okien — dla czystego przesortowania (zwłaszcza `defaultName` dekad) przeloguj się albo przenieś okna ręcznie. Skróty działają tak samo w obu trybach — różni się tylko zasięg:

| Skrót | Akcja |
|---|---|
| `Super + 1..0` | Idź na workspace 1–10 (shared: globalnie / decades: aktywnego monitora) |
| `Super + Shift + 1..0` | Przenieś okno na workspace 1–10 |
| `Super + Ctrl + ←/→` | Przewijaj workspace'y |
| `Super + scroll` | Przewijaj workspace'y |

### Fokus
| Skrót | Akcja |
|---|---|
| `Super + strzałki` | Przenoś fokus |
| `Super + Shift + strzałki` | Przenoś okno |
| `Super + Alt + strzałki` | Zmieniaj rozmiar okna |
| `Super + .` | Fokus na następny monitor |
| `Super + ,` | Fokus na poprzedni monitor |

### Mysz
| Skrót | Akcja |
|---|---|
| `Super + LPM` | Przesuń okno |
| `Super + PPM` | Zmień rozmiar okna |

### Zrzuty ekranu
| Skrót | Akcja |
|---|---|
| `Print` | Zrzut zaznaczenia → schowek |
| `Super + Print` | Zrzut zaznaczenia → ~/Screenshots |
