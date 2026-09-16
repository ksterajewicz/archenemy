# AGENTS.md

Instrukcje dla agentów AI (Claude Code, Copilot, Cursor i inne — własne narzędzie
każdego kontrybutora) pracujących nad tym repozytorium. Cel: żeby każdy agent,
niezależnie od operatora i narzędzia, utrzymywał spójność projektu i niczego nie
psuł. Ten plik jest jedynym źródłem takich instrukcji w repo — nie ma tu
`CLAUDE.md` ani innego pliku per-narzędzie; jeśli Twój agent czyta inny format,
zacznij od tego pliku i tam się odwołaj.

## Zanim zaczniesz — start sesji

1. Przeczytaj `README.md` (struktura repo, cztery warstwy, instalacja).
2. Sprawdź `packages/requirements-*.txt` i `packages/additional-packages-*.txt`
   — co faktycznie ma być zainstalowane.
3. Jeśli zadanie dotyka nieznanego modułu — otwórz go i przeczytaj, zanim
   napiszesz linijkę kodu.
4. Nie zakładaj, że coś działa tak, jak sugeruje nazwa — weryfikuj w źródle
   (kodzie repo albo dokumentacji Hyprlanda/waybara), nie z pamięci.

## Stack

- Bash (skrypty) + konfiguracja Hyprlanda w **Lua** (od Hyprlanda 0.55 stary
  hyprlang `.conf` jest przestarzały; stare pliki zostają obok jako
  `*.conf.bak` do czasu pełnej weryfikacji migracji na żywej maszynie —
  `hyprlock.conf` i `hyprpaper.conf` celowo ZOSTAJĄ w hyprlangu, to osobne
  programy, nie Hyprland).
- Jeden komponent w C: `src/flux-wall/` — animowana tapeta (Wayland
  `wlr-layer-shell` + EGL + GLES 3.0). Opcjonalny: buduje go krok `install.sh`
  [9.6] z fallbackiem, brak kompilatora/zależności nie blokuje reszty
  instalacji.
- Bez systemu budowania na poziomie repo (poza `make -C src/flux-wall`) i bez
  własnego menedżera pakietów — wszystko przez `pacman`/AUR (`yay`), listy w
  `packages/`.

## Architektura — cztery warstwy (NIGDY ich nie mieszaj)

| Warstwa | Gdzie mieszka | W gicie? |
|---|---|---|
| **Rice** (wygląd) | `rices/<nazwa>/`, symlinkowane do `~/.config` | tak |
| **Wspólna** (bindy, klawisze media, ogólny env Waylanda) | `config/hypr/*.lua` | tak |
| **Maszynowa** (monitory, env GPU, klawisze sprzętowe, workspace'y) | generowana przez `install.sh` do `config/hypr/` | NIE (gitignore) |
| **Osobista** (autostart użytkownika, appbindy użytkownika) | `config/hypr/autostartpersonalisation.lua`, `config/hypr/appbinds.lua` | NIE (gitignore) |

Reguły wynikające wprost z tabeli:

- Żadnych nazw monitorów, producentów GPU, hostname'ów ani osobistych
  aplikacji w plikach trackowanych. Jeśli coś takiego pojawia się w Twoim
  diffie — to znak, że powinno być generowane, nie commitowane.
- `install.sh` musi tworzyć KAŻDY plik generowany (nawet pusty) — `hyprland.lua`
  rice'ów je `require()`/`source`'uje, więc jego brak wywala start.
- Nowa zawartość maszynowa/osobista → dopisz wzorzec do `.gitignore`.

## Znane pułapki (nie odkrywaj ich drugi raz)

- **`interval` modułów `custom/*` waybara TYLKO liczba całkowita (sekundy).**
  Waybar 0.15.0 rzutuje ułamek na `long` PRZED mnożeniem przez 1000 — `0.5`
  daje **1 ms**, czyli pętlę forków skryptu bez przerwy, osobno na każdym
  monitorze. Natychmiastowe odświeżenie modułu zawsze przez sygnał
  (`pkill -RTMIN+N waybar`) z akcji zmieniającej stan, nigdy przez skrócenie
  interwału.
- **Przełączanie rice'ów to 2-liniowe stuby** w
  `scripts/changing-theme-scripts/*.sh` (nazwa pliku = etykieta menu rofi;
  `RICE_NAME` w środku musi równać się nazwie folderu `rices/<folder>`). CAŁA
  logika mieszka w `scripts/changing-theme-scripts/lib/switch-rice.sh` —
  edytuj bibliotekę, nigdy nie wklejaj logiki z powrotem do stuba (tak
  powstaje dryf parytetu kopiuj-wklej).
- **Generatory maszynowe są jedno źródło prawdy**: `scripts/hypr/lib/gen-workspaces.sh`
  i `gen-autostart.sh` wołane są zarówno z `install.sh`, jak i z przełączników
  działających na żywo (`workspace-mode-switch.sh`). To samo dotyczy
  `install/bootloader.sh` (source'owany przez instalatory CPU/kernela). Nie
  duplikuj tej logiki między skryptami.
- **Przełączenie rice'a usuwa WSZYSTKIE symlinki w `~/.config` wskazujące do
  `rices/`, zanim podlinkuje nowy rice.** Bez tego motyw poprzedniego rice'a
  przecieka przez foldery, których nowy rice nie nadpisuje. Zachowaj ten
  inwariant przy każdej zmianie przełącznika.
- **Parytet `white-blue` / `tron`:** każda NIE-wizualna zmiana (funkcjonalność,
  bindy, source'y, reguły okien, hooki skryptów) idzie do OBU naraz, nigdy
  tylko do jednego. `white-blue_beta` to legacy — WYŁĄCZNIE bug-fixy tego, co
  już ma; nie rozszerzaj go o bindy/moduły/source'y, których nigdy nie miał.
  Zmiany czysto wizualne/GUI zostają per rice z założenia.
- **Workspace'y mają dwa tryby** (`shared`/`decades`, stan w
  `data/workspace-mode.dat`). Zmiana jednego elementu z czwórki {generator
  `gen-workspaces.sh`, bindy w generowanym `workspaces-monitors.conf`, guard
  sierot `scripts/hypr/workspace-orphan-guard.sh`, moduł `hyprland/workspaces`
  waybara} wymaga sprawdzenia pozostałych trzech.
- **Tło hyprlocka i tapeta (`hyprpaper.conf`) to warstwa maszynowa**, mimo że
  wyglądają jak config rice'a — oba są plikami generowanymi, źródłowanymi
  (`source = `) z `hypr/hyprlock.conf` / `hyprpaper.conf` każdego rice'a.
  Nigdy nie zapisuj stanu tapet/tła bezpośrednio w folderach `rices/`.
- Binarka użyta w dowolnym configu/skrypcie musi być pokryta przez
  `packages/requirements-*.txt` (obowiązkowa) albo
  `packages/additional-packages-*.txt` (opcjonalna — wywołanie zabezpieczone
  `command -v X && X`). Nie dokładaj zależności „przy okazji" — każda nowa
  wymaga podanego powodu.

Więcej kontekstu architektonicznego (pełne drzewo plików, workspace'y, skróty
klawiszowe) jest w `README.md` — to on jest źródłem prawdy dla struktury repo,
ten plik tylko dodaje reguły zachowania.

## Jak pisać kod tutaj

- Nie zgaduj API, flag ani nazw opcji Hyprlanda/waybara — otwórz źródło albo
  man page i sprawdź.
- Dyscyplina zakresu: rób dokładnie to, o co poproszono. Widzisz coś innego
  zepsutego — zgłoś, nie naprawiaj bez zlecenia.
- Małe kroki. Duża zmiana architektoniczna → najpierw krótki plan w
  odpowiedzi, implementacja po akceptacji.
- Trzymaj styl istniejących skryptów: nagłówek-ramka z `=====`, zmienne
  kolorów ANSI, `set -uo pipefail` w instalatorach (bez `-e` — kroki
  opcjonalne nie mogą przerywać biegu).
- **Język:** komentarze w kodzie, README, dokumentacja, komunikaty commitów —
  **polski**. Identyfikatory (zmienne, funkcje, nazwy plików) — **angielski**.
  Teksty UI w TUI appbinds (Super+A) i w power menu (Super+Shift_R) —
  **angielski** (to świadomy wyjątek, nie niekonsekwencja).

## Testowanie — czym tu jest „CI"

Nie ma pipeline'u. Weryfikacja ma trzy poziomy:

1. **Składnia** — `bash -n <skrypt>` dla każdego dotkniętego skryptu; dla
   plików `.lua` sprawdzenie przez `lua5.4`/`loadfile` (jeśli dostępne w
   Twoim środowisku).
2. **Logika na atrapie** — symlinki/generowanie da się przetestować na
   fałszywym drzewie `~/.config` w katalogu tymczasowym, bez dotykania
   prawdziwego systemu.
3. **Prawdziwy test** — `install.sh` i przełączanie rice'ów (`Super+T`)
   wymagają żywej maszyny Arch + Hyprland. Jeśli nie masz jej pod ręką,
   **powiedz to wprost** i wypisz dokładne kroki „live-only" do sprawdzenia
   przez człowieka zamiast twierdzić, że coś działa.

## Definition of Done

Zadanie nie jest skończone, dopóki:

- dotknięte skrypty przechodzą `bash -n` (logikę zweryfikowano na atrapie tam,
  gdzie się dało);
- rzeczy testowalne wyłącznie na żywej maszynie są wypisane po imieniu jako
  „live-only", z konkretnymi krokami sprawdzenia;
- `README.md` jest zaktualizowane (drzewo plików i opisy zgodne z
  rzeczywistością);
- `packages/requirements-*.txt` / `additional-packages-*.txt` zaktualizowane,
  jeśli config/skrypt zaczął (lub przestał) potrzebować binarki;
- zero danych maszynowych i sekretów w plikach trackowanych i w treści
  commitów.

Raportuj wprost, które punkty odhaczyłeś i których nie dało się zweryfikować —
i dlaczego.

## Gałęzie i commity

- **`dev` → `main`.** Nowa praca ląduje na `dev`. `main` musi zawsze zostawać
  stabilny i bootowalny — trafia tam wyłącznie to, co jest sprawdzone na
  żywej maszynie, i tylko za zgodą osoby prowadzącej dane repo/fork.
- Commit = jedna logiczna zmiana. Format:
  `typ: opis po polsku w trybie rozkazującym`, np.
  `fix: popraw sprzątanie symlinków przy zmianie rice'a`,
  `docs: zaktualizuj drzewo plików w README`. Typy jak w Conventional
  Commits (`feat`, `fix`, `docs`, `refactor`, …), opis po polsku.
- **Przed `git checkout -- <plik>` / `restore` / `reset` sprawdź
  `git diff HEAD -- <plik>`.** Working tree bywa brudny mimo statusu „clean"
  ze startu sesji (cudza niescommitowana praca z wcześniejszej sesji). Nie
  wciągaj cudzych zmian do swojego commita — wydziel je osobno.
- Prawo do `git commit` w lokalnym repo ustala każdy operator ze swoim
  agentem. Niezależnie od tych ustaleń: **nigdy `push --force`, nigdy merge
  `dev` → `main` bez wyraźnej zgody człowieka**, nigdy commit z danymi
  maszynowymi/sekretami (patrz DoD).
- Nie dopisuj stopki narzędzia (`Co-Authored-By`, `Generated by …`) do
  komunikatu commita, chyba że operator repo jawnie o to poprosi — tożsamość
  autora ustala on, nie agent.

## Pull requesty

Repo nie ma CI. Jeśli pracujesz przez pull request (a nie bezpośrednio na
`dev`), opisz w nim wprost: co zweryfikowano automatycznie (`bash -n`, testy
na atrapie) i co zostaje jako „live-only" do sprawdzenia przez recenzenta na
prawdziwej maszynie Arch + Hyprland — recenzent nie ma innego sposobu, żeby
się tego dowiedzieć.

## Gdy nie wiesz

Powiedz „nie wiem" i zapytaj albo sprawdź w źródle. Nie wypełniaj luki
wiarygodnie brzmiącym kodem czy nazwą flagi.
