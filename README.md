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
| **Wspólne** (skróty, klawisze media) | `config/hypr/*.conf` | ✅ |
| **Maszyna** (monitory, GPU, klawisze sprzętowe) | `config/hypr/*-monitors/keys/env*.conf` — generuje `install.sh` | ❌ |
| **Osobiste** (Twój autostart, Twoje skróty do aplikacji) | `config/hypr/autostartpersonalisation.conf`, `config/hypr/appbinds.conf` | ❌ |

Dzięki temu to samo repo działa na każdej maszynie i nic prywatnego nie wycieka na GitHuba.

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
│   │   ├── workspaces.conf           # Skróty workspace'ów (wspólne dla wszystkich maszyn).
│   │   ├── keyboard.conf             # Klawisze multimedialne (wspólne).
│   │   ├── gpu_wayland_scaling.conf  # Uniwersalne zmienne Wayland (wspólne).
│   │   └── custom_window_rules.conf  # Reguły okien (wspólne).
│   │   # + pliki generowane przez install.sh (poza gitem):
│   │   # monitorshyprl.conf, workspaces-monitors.conf, hardware-keys.conf,
│   │   # gpu-env.conf, autostartpersonalisation.conf, appbinds.conf,
│   │   # hyprpaper.conf (rice'y wskazują na niego symlinkiem)
├── rices/
│   ├── white-blue/                   # Domyślny rice: alacritty, fastfetch, hypr(+hyprlock), mako,
│   │                                 #   MangoHud, networkmanager-dmenu, nvim, rofi, waybar.
│   ├── white-blue_beta/              # Pierwotny wygląd, trzymany do wglądu/odwrotu.
│   │                                 #   mako i hyprlock dziedziczy z white-blue (symlinki w repo).
│   └── tron/                         # Tron: Legacy — ciemny neon (cyjan + pomarańcz CLU), glow,
│                                     #   rogi 4-6px. Własny fastfetch (logo Archa w cyjanie) + launcher
│                                     #   w waybarze; nvim/networkmanager-dmenu z white-blue (symlinki).
├── scripts/
│   ├── appbinds/                     # Terminalowy menedżer skrótów do aplikacji (Super+A).
│   ├── changing-theme-scripts/       # Po jednym stubie na rice (nazwa pliku = pozycja w menu);
│   │                                 #   wspólna logika przełączania w lib/switch-rice.sh.
│   ├── hypr/                         # workspace-orphan-guard.sh — demon (tylko tryb decades): scala
│   │                                 #   workspace'y-sieroty z ekranem, który jest — koniec z podwójną
│   │                                 #   „1" na pasku. ws-scroll.sh — scroll waybara wg trybu workspace'ów.
│   ├── rofi/                         # Menu rofi: rice'y, tapety, sieć (z reskanem), zasilanie.
│   ├── wallpapers/                   # Matematyczne generatory tapet (czysty Python, zero zależności):
│   │                                 #   logo Archa + siatka Tron (gen_tron_wallpaper.py).
│   └── waybar/                       # Przełącznik profili zasilania (asus/uniwersalny).
└── wallpapers/                       # Tapety (w gicie) — dowolne pliki, opcjonalnie w folderach zestawów.
    ├── arch-white/                   # Zestaw: logo Archa (#0148ED) na bieli — v1 1920x1080, v2 2560x1600.
    └── tron-grid/                    # Zestaw: siatka Tron (neon cyjan na #020A0F) — v1/v2 jak wyżej.
```

## Tapety

Tapety mieszkają w `wallpapers/` (mogą być luzem albo w podfolderach) i są wersjonowane w gicie — świeża instalacja ma je od razu. Przełączanie: `Super + W` — menu pokazuje wszystkie obrazy (jpg/jpeg/png/webp).

Na górze menu jest przełącznik **`[x] Upload to all monitors`** (domyślnie zaznaczony):

- **Zaznaczony** — tapeta trafia na wszystkie monitory. Jeśli obok wybranego pliku `*v1*`/`*v2*` leży druga połowa pary, monitor główny dostaje `v1`, dodatkowy `v2`; bez pary — ten sam obraz wszędzie.
- **Odznaczony** (kliknij pozycję, żeby przełączyć) — tapeta trafia tylko na monitor, na którym masz fokus; pozostałe zostają bez zmian.

Wybór per-monitor jest pamiętany w `data/wallpaper.dat` i przywracany przy zmianie rice'a. Który monitor jest „główny" ustalasz przy instalacji (rola primary/secondary) — instalator sam proponuje: pierwszy = primary, drugi = secondary.

Rola dotyczy **tylko tapet** (primary→v1, secondary→v2). Przydziałem workspace'ów rządzi co innego: **numeracja monitorów lewa→prawa** i **tryb workspace'ów** — oba ustawiane przy instalacji (patrz sekcja „Workspace'y").

## Rice'y

| Rice | Opis |
|---|---|
| `white-blue` | Domyślny. Biało-niebieskie szkło: zaokrąglone rogi, dostrojony blur, własne animacje, spójny akcent `#0148ED`, motyw mako + hyprlock. |
| `white-blue_beta` | Pierwotny wygląd biało-niebieski, trzymany do wglądu/odwrotu. Tylko poprawki funkcjonalne, bez zmian wizualnych. Mako i hyprlock dziedziczy z `white-blue` przez symlinki w repo. |
| `tron` | Tron: Legacy — ciemne szkło `#020A0F`, neon cyjan `#00E5FF` z poświatą (glow), pomarańcz CLU `#FF7B1C` tylko dla alarmów, rogi niemal ostre (4–6px). Własny motyw waybar (z launcherem „portal do Gridu" i podświetlanymi wyspami HUD), rofi (glif szukania), fastfetch (logo Archa w neonowym cyjanie), alacritty/mako/hyprlock (kinowa oprawa z neonowymi liniami)/MangoHud; nvim i networkmanager-dmenu dziedziczy z `white-blue` przez symlinki w repo. Tapeta: zestaw `tron-grid` (generowany). |

Każdy rice to folder w `rices/`, którego podfoldery są linkowane do `~/.config`. Przełączanie: `Super + T` — menu pokazuje skrypty z `scripts/changing-theme-scripts/` (nazwa pliku `.sh` to etykieta w menu: `white-blue`, `white-blue_beta`). Przy przełączeniu stare symlinki rice'a są sprzątane, więc motywy się nie mieszają.

**Nowy rice:** utwórz `rices/<folder>/`, skopiuj `scripts/changing-theme-scripts/white-blue.sh` jako `<etykieta>.sh` i ustaw w nim `RICE_NAME` na nazwę swojego folderu. Skrypt to dwulinijkowy stub — cała logika przełączania siedzi we wspólnym `lib/switch-rice.sh`, więc nowy rice nie wymaga kopiowania żadnej logiki.

## Własne skróty do aplikacji (Super + A)

`Super + A` otwiera terminalowy menedżer skrótów: wybierasz klawisz (np. `g`, `F5`, `semicolon`) i polecenie (np. `spotify`), a skrót `Super + klawisz` działa od razu. Menedżer pilnuje kolizji z istniejącymi skrótami archenemy, a opcja `[s]` pokazuje pełną ściągę wszystkich obecnych skrótów — co jest pod którym klawiszem i jaką aplikację/akcję odpala. Twoje bindy trafiają do `config/hypr/appbinds.conf` — pliku osobistego poza gitem, więc przetrwają `git pull` i zmianę rice'a.

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
| `Super + prawy Shift` | Menu zasilania (wyłącz / restart) |

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

Tryb i numerację zmienisz, uruchamiając `install.sh` ponownie. Skróty działają tak samo w obu trybach — różni się tylko zasięg:

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
