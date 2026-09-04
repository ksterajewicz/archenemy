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

Instalator: wykryje i skonfiguruje monitory (w tym ich numerację lewa→prawa i tryb workspace'ów — patrz sekcja „Workspace'y"), zainstaluje pakiety z `packages/`, ustawi przełącznik profili zasilania (ASUS ROG / uniwersalny — typ sprzętu wykrywany z DMI jako podpowiedź, na ASUS-ach bez działającego asusctl automatyczny fallback na power-profiles-daemon, na końcu samokontrola `profile-get.sh`), opcjonalnie odpali instalatory mikrokodu CPU / sterowników GPU / kernela, wygeneruje pliki maszynowe, podlinkuje domyślny rice do `~/.config`, ustawi pierwszą tapetę (jeśli jakaś jest w `wallpapers/`) i zadba o usługi: NetworkManager, audio (pipewire-pulse), asusd na ASUS-ach, opcjonalnie UFW i bluetooth.

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
│   └── asia-n-rice/                  # Mauve/róż na granacie, płaski look. Własny hypr, rofi,
│                                     #   mako, hyprlock, alacritty, waybar i motyw nvim (mauve);
│                                     #   fastfetch domyślny;
│                                     #   MangoHud/networkmanager-dmenu z white-blue (symlinki).
├── scripts/
│   ├── appbinds/                     # Terminalowy menedżer skrótów do aplikacji (Super+A);
│   │                                 #   [w] przełącza tryb workspace'ów shared/decades na żywo;
│   │                                 #   [v] przełącza styl paska głośności w waybarze;
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
│   │                                 #   logo Archa + siatka Tron (gen_tron_wallpaper.py).
│   └── waybar/                       # Przełącznik profili zasilania (asus/uniwersalny) +
│                                     #   volume-bar.sh — pasek głośności zamiast modułu pulseaudio;
│                                     #   styl line/ticks/solid przełączalny w Super+A → [v].
└── wallpapers/                       # Tapety (w gicie) — dowolne pliki, opcjonalnie w folderach zestawów.
    ├── arch-white/                   # Zestaw: logo Archa (#0148ED) na bieli — v1 1920x1080, v2 2560x1600.
    └── tron-grid/                    # Zestaw: siatka Tron (neon cyjan na #020A0F) — v1/v2 jak wyżej.
```

## Tapety

Tapety mieszkają w `wallpapers/` (mogą być luzem albo w podfolderach) i są wersjonowane w gicie — świeża instalacja ma je od razu. Przełączanie: `Super + W` — menu pokazuje wszystkie obrazy (jpg/jpeg/png/webp), na górze dwa checkboxy: `[x] Upload to all monitors` (domyślnie zaznaczony — tapeta na wszystkie monitory zamiast tylko na ten z fokusem) i `[ ] Set as hyprlock background (no blur)` (domyślnie odznaczony — zaznaczenie ustawia wybrany obraz jako tło ekranu blokady bez blura, zamiast domyślnego żywego zrzutu ekranu + blur; przeżywa przełączenie rice'a).

Na górze menu jest przełącznik **`[x] Upload to all monitors`** (domyślnie zaznaczony):

- **Zaznaczony** — tapeta trafia na wszystkie monitory. Jeśli obok wybranego pliku `*v1*`/`*v2*` leży druga połowa pary, monitor główny dostaje `v1`, dodatkowy `v2`; bez pary — ten sam obraz wszędzie.
- **Odznaczony** (kliknij pozycję, żeby przełączyć) — tapeta trafia tylko na monitor, na którym masz fokus; pozostałe zostają bez zmian.

Wybór per-monitor jest pamiętany w `data/wallpaper.dat` i przywracany przy zmianie rice'a. Który monitor jest „główny" ustalasz przy instalacji (rola primary/secondary) — instalator sam proponuje: pierwszy = primary, drugi = secondary.

Rola dotyczy **tylko tapet** (primary→v1, secondary→v2). Przydziałem workspace'ów rządzi co innego: **numeracja monitorów lewa→prawa** i **tryb workspace'ów** — oba ustawiane przy instalacji (patrz sekcja „Workspace'y").

## Rice'y

| Rice | Opis |
|---|---|
| `white-blue` | Domyślny. Biało-niebieskie szkło: zaokrąglone rogi, dostrojony blur, własne animacje, spójny akcent `#0148ED`, motyw mako + hyprlock + nvim (ręczny colorscheme w palecie rice'a). |
| `white-blue_beta` | Pierwotny wygląd biało-niebieski, trzymany do wglądu/odwrotu. Tylko poprawki funkcjonalne, bez zmian wizualnych. Mako i hyprlock dziedziczy z `white-blue` przez symlinki w repo. |
| `tron` | Tron: Legacy — ciemne szkło `#020A0F`, neon cyjan `#00E5FF` z poświatą (glow), pomarańcz CLU `#FF7B1C` tylko dla alarmów, rogi niemal ostre (4–6px). Własny motyw waybar (z launcherem „portal do Gridu" i podświetlanymi wyspami HUD), rofi (glif szukania), fastfetch (logo Archa w neonowym cyjanie), alacritty/mako/hyprlock (kinowa oprawa z neonowymi liniami)/MangoHud/nvim (ręczny colorscheme: neon cyjan na `#020A0F`, alarmy w pomarańczu CLU); networkmanager-dmenu dziedziczy z `white-blue` przez symlink w repo. Tapeta: zestaw `tron-grid` (generowany). |
| `asia-n-rice` | Przygaszony mauve/róż (`#b47687`) na ciemnym granacie (`#2a3444`), płaski look: waybar z zaokrąglonymi wyspami (14px) i kursywnymi tytułami okien, ostre rogi okien, ramka `#131a2a`. Wygląd zaadaptowany z zewnętrznego rice'a i przepięty pod backend archenemy: alacritty zamiast kitty, rofi zamiast wofi, warstwa maszynowa (GPU/monitory/workspace'y) przez `source`, bez cava. Własny motyw waybar/rofi/mako/hyprlock/alacritty w palecie mauve; fastfetch domyślny (bez przebarwienia); własny motyw nvim (ręczny colorscheme w palecie mauve, płaski — bez boldów); MangoHud i networkmanager-dmenu dziedziczy z `white-blue` przez symlinki. Bez własnej tapety — używa aktualnej (warstwa maszynowa). |

Każdy rice to folder w `rices/`, którego podfoldery są linkowane do `~/.config`. Przełączanie: `Super + T` — menu pokazuje skrypty z `scripts/changing-theme-scripts/` (nazwa pliku `.sh` to etykieta w menu: `white-blue`, `white-blue_beta`). Przy przełączeniu stare symlinki rice'a są sprzątane, więc motywy się nie mieszają.

**Nowy rice:** utwórz `rices/<folder>/`, skopiuj `scripts/changing-theme-scripts/white-blue.sh` jako `<etykieta>.sh` i ustaw w nim `RICE_NAME` na nazwę swojego folderu. Skrypt to dwulinijkowy stub — cała logika przełączania siedzi we wspólnym `lib/switch-rice.sh`, więc nowy rice nie wymaga kopiowania żadnej logiki.

## Własne skróty do aplikacji (Super + A)

`Super + A` otwiera terminalowy menedżer skrótów: wybierasz klawisz (np. `g`, `F5`, `semicolon`) i polecenie (np. `spotify`), a skrót `Super + klawisz` działa od razu. Menedżer pilnuje kolizji z istniejącymi skrótami archenemy, a opcja `[s]` pokazuje pełną ściągę wszystkich obecnych skrótów — co jest pod którym klawiszem i jaką aplikację/akcję odpala. Twoje bindy trafiają do `config/hypr/appbinds.lua` — pliku osobistego poza gitem, więc przetrwają `git pull` i zmianę rice'a.

To samo TUI ma dodatkowe pozycje: `[w]` — przełącznik trybu workspace'ów shared/decades (sekcja „Workspace'y"), `[u] autostart apps` — wybór aplikacji odpalanych przy starcie Hyprlanda z listy wszystkich wpisów `.desktop` (checkboxy `[x]`/`[ ]`, filtrowanie po nazwie przez `/tekst`; wybór ląduje w `data/autostart-apps.dat`, a z niego generowany jest osobisty `config/hypr/autostart-apps.lua` — obok ręcznego `autostartpersonalisation.lua`, którego ta warstwa nie dotyka), `[v] volume bar` — styl paska głośności w waybarze (`line` ━━━━━━────, `ticks` ▮▮▮▮▮▮▯▯▯▯, `solid` ▬▬▬▬▬▬▬▬──────), zapisywany w `data/volume-bar-style.dat` i stosowany od razu (sygnał 10 do waybara), oraz `[p] update archenemy` — aktualizator repo: wybierasz gałąź (`dev` — najnowsze zmiany / `main` — tylko stabilne wydania), skrypt robi `git fetch`/`checkout`/`pull --ff-only`, a lokalne zmiany w plikach śledzonych przez git chowa `git stash` na czas pull i przywraca po nim. Warstwa maszynowa i osobista (monitory, appbinds, autostart, rice, styl paska głośności...) jest poza gitem, więc update jej nie rusza — Twoje ustawienia zostają domyślnie bez zmian. Na końcu proponuje ponowne uruchomienie `install.sh`, żeby dogenerować ewentualne nowe pliki maszynowe.

Menu główne TUI (Super+A) i potwierdzenia w podmenu (`[v]`, `[w]`, `[p]`) odpowiadają na jeden klawisz bez Entera — `Escape` wychodzi/anuluje tak samo jak `q`/`N`.

Głośność: moduł `pulseaudio` waybara zastąpiony własnym `custom/volumebar` (skrypt `scripts/waybar/volume-bar.sh`) — rysuje pasek wypełnienia z procentem zamiast samej ikony. Scroll na pasku i klawisze głośności działają jak dotąd (klawisze sprzętowe dodatkowo wysyłają do waybara sygnał 10 = natychmiastowe odświeżenie paska). Klik: LPM `pavucontrol`, PPM mute. Trzy style do wyboru w `Super+A` → `[v]`: `line` (cienka kreska, 10 komórek), `ticks` (segmenty ▮▮▯, 10 komórek) i `solid` (gruby blok głośności na cienkiej linii, dłuższy — 14 komórek). Stan `>100%` (boost) ma osobną klasę koloru per rice. Ikona głośnika automatycznie zamienia się na słuchawki, gdy Active Port domyślnego sinka (z `pactl`) wskazuje na wyjście słuchawkowe — i wraca do głośnika po odpięciu; wykrywane w tym samym backstopie `interval:1`, bez osobnego triggera.

Jasność ekranu: klawisze `XF86MonBrightness*` wołają `swayosd-client` — zmieniają jasność i pokazują pasek OSD u dołu wszystkich monitorów (serwer `swayosd-server` startuje z każdym rice'em i jest restartowany przy przełączeniu rice'a, bo czyta motyw tylko przy starcie). Motyw OSD per rice: `rices/*/swayosd/style.css` (beta dziedziczy z white-blue przez symlink). Pakiet: `swayosd-git` (AUR).

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
