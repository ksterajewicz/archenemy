#!/usr/bin/env bash
# =============================================
#   archenemy - tests/doctor-platforms.sh
#   archenemy doctor per platforma (D9) na atrapach: jawny os-release
#   (ARCHENEMY_TEST=1), prawdziwe listy wymagań i mapa pakietów, prawdziwy
#   install/lib/pkg.sh (pkg_check_ids) i prawdziwy gaming-diag.sh --doctor
#   w trybie --full na atrapie korzenia (ARCHENEMY_FS_ROOT). PATH to wyłącznie
#   atrapy + podstawowe narzędzia — prawdziwy pacman/rpm/fc-list hosta nie
#   jest osiągalny.
#   Sprawdza:
#     - Arch / pochodna / Fedora / Fedora Atomic / NixOS / nieznana / brak
#       os-release × poprawne zero, braki, błąd, pusto, zawieszenie, brak
#       backendu; obcy pacman na Fedorze/NixOS/nieznanej ani razu nie pytany;
#     - wymagane AUR na Archu, wiele RPM na wiersz, RPM tylko w i686 = brak,
#       nieznana architektura RPM = stała etykieta bez surowej wartości (L2),
#       sondy NixOS bez nix CLI, system-managed jako porada (skipped), nie brak;
#     - zła/brak mapy, brak pkg.sh, pusta lista wymagań, fc-list bez zapisu cache;
#     - stan „complete/partial/unavailable” i kod wyjścia; „Missing: 0” tylko
#       przy rzeczywiście sprawdzonych pakietach;
#     - --full: gaming-diag completed / partial (lista kluczy) / timed out;
#     - rice yin: poprawny, wiszący link, zły link, brak tła hyprlock — oba tryby;
#     - prywatność: sekrety z os-release, rpm, fc-list i gaming-diag nie trafiają
#       do raportu; migawka HOME i atrapy korzenia bez zmian; budżet 4,5 s.
#   Opcja: DOCTOR_PLATFORMS_REV=<rewizja> — scenariusze Archa także na
#   doctorze z rewizji: wyjście identyczne poza nowymi liniami „Platform:”,
#   „Package check:”, „Missing: unknown” oraz jawnie wymienionymi poprawkami.
#   Zapisy tylko w $T (test_isolate, D7F R3).
#   Uruchom: bash tests/doctor-platforms.sh   (kod 0 = wszystko przeszło)
# =============================================
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/environment.sh
source "$REPO/tests/lib/environment.sh"
test_isolate "$REPO/tests/doctor-platforms.sh" "$@"   # D7F R3: zapisy poza $T wykrywalne
# shellcheck source=tests/lib/timing.sh
source "$REPO/tests/lib/timing.sh"   # walidacja skali i PYTHONDONTWRITEBYTECODE dla importu test_timing
T="$(mktemp -d)" && [[ -n "$T" && -d "$T" && "$T" != / ]] || exit 1
trap 'rm -rf "${T:?}"' EXIT
test_environment_init "$T" || exit 1
export DOCTOR_SOURCE="$REPO" DOCTOR_TEST_TREE="$T"
python - <<'PY'
import hashlib
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import time

sys.path.insert(0, str(Path(os.environ['DOCTOR_SOURCE']) / 'tests/lib'))
from test_timing import seconds

# Limity czasu testu w jednym miejscu (tests/README-timing.md).
RUN_LIMIT = seconds(10.0)  # s — ZABEZPIECZENIE: twardy limit jednego biegu doctora (× ARCHENEMY_TEST_TIME_SCALE)
DEADLINE = 5.0             # s — KONTRAKT: doctor kończy się przed 4,5 s (+ start Pythona); bez skali

root = Path(os.environ['DOCTOR_TEST_TREE'])
source = Path(os.environ['DOCTOR_SOURCE'])
home = Path(os.environ['HOME'])
repo = home / 'archenemy'
bin_dir, sys_bin, log_dir, fsroot = root / 'bin', root / 'sysbin', root / 'log', root / 'fsroot'
for d in (bin_dir, sys_bin, log_dir):
    d.mkdir()
calls = log_dir / 'calls'
results = {'pass': 0, 'fail': 0}

def ok(label, detail=''):
    results['pass'] += 1
    print('  ✓ ' + label)

def bad(label, detail=''):
    results['fail'] += 1
    print('  ✗ ' + label + (': ' + detail if detail else ''))

for name in ['scripts/archenemy-doctor.sh', 'scripts/hypr/machine-layer-check.sh', 'scripts/hypr/lib/monitor-id.sh',
             'scripts/wallpapers/flux-wall.sh', 'scripts/hypr/gaming-diag.sh', 'install/lib/pkg.sh',
             'packages/platform-map.tsv', 'packages/requirements-pacman.txt', 'packages/requirements-aur.txt']:
    path = repo / name
    path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / name, path)
(repo / 'scripts/hypr/workspace-diag.sh').write_text('#!/usr/bin/env bash\nexit 0\n')

def required_ids():
    ids = []
    for name in ('requirements-pacman.txt', 'requirements-aur.txt'):
        for line in (repo / 'packages' / name).read_text().splitlines():
            entry = line.split('#', 1)[0].strip()
            if entry and entry not in ids:
                ids.append(entry)
    return ids
REQUIRED = required_ids()
MAP = {}
for line in (repo / 'packages/platform-map.tsv').read_text().splitlines():
    if line and not line.startswith('#'):
        f = line.split('\t')
        MAP[f[0]] = {'fedora': f[3], 'check': f[6], 'status': f[8]}

# Rice: white-blue i yin z prawdziwymi nazwami katalogów (yin ma też link
# katalogu networkmanager-dmenu → ../white-blue/…, jak w repo).
for rice in ('white-blue', 'yin'):
    for entry in sorted((source / 'rices' / rice).iterdir()):
        target = repo / 'rices' / rice / entry.name
        if entry.is_symlink():
            target.parent.mkdir(parents=True, exist_ok=True)
            target.symlink_to(os.readlink(entry))
        elif entry.is_dir():
            target.mkdir(parents=True)
config = home / '.config'
config.mkdir()
def link_rice(rice):
    for entry in config.iterdir():
        if entry.is_symlink():
            entry.unlink()
    for entry in sorted((repo / 'rices' / rice).iterdir()):
        if entry.is_dir():
            (config / entry.name).symlink_to(repo / 'rices' / rice / entry.name)
    (repo / '.current_rice').write_text(rice + '\n')
link_rice('white-blue')
for name in ['monitorshyprl.lua', 'workspaces-monitors.lua', 'hardware-keys.lua', 'gpu-env.lua',
             'autostartpersonalisation.lua', 'appbinds.lua', 'hyprpaper.conf',
             'hyprlock-background-white-blue.conf', 'hyprlock-background-yin.conf']:
    path = repo / 'config/hypr' / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.touch()
(home / '.bashrc').write_text('# >>> archenemy shell >>>\n# <<< archenemy shell <<<\n')

# Atrapa korzenia dla gaming-diag --doctor (bez czytania /var /etc /usr hosta).
for d in ('etc/modprobe.d', 'usr/lib/modprobe.d', 'usr/share/vulkan/icd.d', 'var/log', 'sys/bus/pci/devices'):
    (fsroot / d).mkdir(parents=True)
(fsroot / 'var/log/pacman.log').write_text('[2026-11-01T10:00:00+0100] [ALPM] upgraded mesa (1 -> 2)\n')
(fsroot / 'etc/mkinitcpio.conf').write_text('MODULES=()\n')
(fsroot / 'usr/share/vulkan/icd.d/intel_icd.x86_64.json').touch()

secrets = [str(home), 'fixture-user-private', socket.gethostname(), 'SERIAL-EDID-PRIVATE-123', '192.0.2.81',
           'aa:bb:cc:dd:ee:ff', 'token=PRIVATE-CREDENTIAL-123', 'ARBITRARY_OPAQUE_SECRET', 'GENERATION-NAME-PRIVATE']
SECRET_TEXT = ' '.join(secrets)

# ─── atrapy ──────────────────────────────────────────────────────────────────
for tool in ['bash', 'sh', 'cat', 'grep', 'sed', 'awk', 'tr', 'sort', 'uniq', 'head', 'tail', 'basename', 'dirname',
             'readlink', 'realpath', 'wc', 'ls', 'timeout', 'sleep', 'env', 'stat', 'cut', 'find', 'mkdir', 'touch', 'tee']:
    found = shutil.which(tool)
    if found:
        (sys_bin / tool).symlink_to(found)
(sys_bin / 'python').symlink_to(sys.executable)
(sys_bin / 'python3').symlink_to(sys.executable)
LOG = 'echo "$(basename "$0") $*" >> "$DOCTOR_CALLS"\n'
mocks = {
'git': '''shift 2
case "$*" in
 'rev-parse --abbrev-ref HEAD') echo dev ;;
 'rev-parse --short=12 HEAD'|'rev-parse HEAD') echo 0123456789ab ;;
 'status --porcelain --untracked-files=normal') : ;;
 'rev-list --count HEAD..refs/remotes/origin/'*) echo 0 ;;
 *) exit 91 ;;
esac
''',
# pacman: -Qq (doctor), -Q / -Qm / -Qoq (gaming-diag --doctor).
'pacman': '''case "${DP_PACMAN:-ok}" in hang) exec sleep 30 ;; esac
case "$1" in
 -Qq)
  case "${DP_PACMAN:-ok}" in fail) echo "error: $DOCTOR_SECRETS" >&2; exit 1 ;; empty) exit 0 ;; esac
  for p in $DP_INSTALLED; do [[ " ${DP_MISSING:-} " == *" $p "* ]] || echo "$p"; done ;;
 -Q) [[ "${DP_PACMAN:-ok}" == fail ]] && exit 1; for p in $DP_INSTALLED; do echo "$p 1.0-1"; done ;;
 -Qm) exit 1 ;;
 -Qoq) echo asusctl ;;
 *) exit 92 ;;
esac
''',
# rpm -q --qf '%{NAME} %{ARCH}\\n' <nazwy…> (pkg_check_ids) i -qa / -qf (gaming-diag --doctor).
'rpm': '''case "${DP_RPM:-ok}" in hang) exec sleep 30 ;; esac
case "$1" in
 -q)
  shift 3
  case "${DP_RPM:-ok}" in
   fail) echo "error: rpmdb: $DOCTOR_SECRETS" >&2; exit 1 ;;
   empty) exit 0 ;;
   garbage) echo "$DOCTOR_SECRETS"; exit 0 ;;
  esac
  rc=0
  for n in "$@"; do
   if [[ " ${DP_RPM_MISSING:-} " == *" $n "* ]]; then echo "package $n is not installed"; rc=$((rc + 1))
   elif [[ " ${DP_RPM_I686:-} " == *" $n "* ]]; then echo "$n i686"
   elif [[ " ${DP_RPM_ODD:-} " == *" $n "* ]]; then echo "$n ${DP_RPM_ODD_ARCH:?}"
   else echo "$n x86_64"; fi
  done
  exit "$rc" ;;
 -qa)
  [[ "${DP_RPM:-ok}" == fail ]] && exit 1
  printf 'kernel-core\\t6.17.1-300.fc44\\tx86_64\\t1762000000\\t%s\\n' "${DP_VENDOR:-Fedora Project}" ;;
 -qf) echo asusctl ;;
 *) exit 93 ;;
esac
''',
# fc-list próbuje zapisać cache (jak fontconfig przy nieaktualnym cache).
'fc-list': '''mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/fontconfig" 2>/dev/null && touch "${XDG_CACHE_HOME:-$HOME/.cache}/fontconfig/CACHE-WRITTEN" 2>/dev/null
touch "$HOME/.fontconfig-CACHE-WRITTEN" 2>/dev/null
case "${DP_FC:-ok}" in
 hang) exec sleep 30 ;;
 fail) echo "Fontconfig error: $DOCTOR_SECRETS" >&2; exit 1 ;;
 empty) exit 0 ;;
esac
printf '%s\\n' "Iosevka Nerd Font,Iosevka Nerd Font Mono" "JetBrainsMono Nerd Font" "Symbols Nerd Font Mono" "Noto Sans" "$DOCTOR_SECRETS"
''',
'uname': 'case "$1" in -m) echo x86_64 ;; -r) echo 6.17.1-test ;; *) echo Linux ;; esac\n',
'nix': 'exit 99\n', 'nix-env': 'exit 99\n', 'dnf': 'exit 99\n', 'nixos-rebuild': 'exit 99\n',
'pgrep': 'exit 1\n', 'zsh': 'echo "zsh 5.9"\n',
'lspci': 'echo "00:02.0 VGA compatible controller [0300]: x [8086:a7a0]"\necho "\tKernel driver in use: i915"\n',
'asusctl': 'case "$*" in --version) echo "asusctl 6.3.8";; "profile get") echo Balanced;; *) exit 94;; esac\n',
'notify-send': 'exit 95\n',
}
probe_cmds = set()
for pid in REQUIRED:
    check = MAP[pid]['check']
    if check.startswith('cmd:'):
        probe_cmds.update(check[4:].split(','))
for name in sorted(probe_cmds - set(mocks) - {'bash', 'git', 'python3'}):
    mocks[name] = 'exit 0\n'
for name, text in mocks.items():
    path = bin_dir / name
    path.write_text('#!/usr/bin/env bash\n' + LOG + text)
    path.chmod(0o755)

ARCH_NAMES = ' '.join(REQUIRED)
base_env = {'HOME': str(home), 'TMPDIR': os.environ['TMPDIR'], 'XDG_RUNTIME_DIR': os.environ['XDG_RUNTIME_DIR'],
            'LC_ALL': 'C.UTF-8', 'USER': 'fixture-user-private', 'LOGNAME': 'fixture-user-private',
            'DOCTOR_SECRETS': SECRET_TEXT, 'DOCTOR_CALLS': str(calls), 'ARCHENEMY_TEST': '1',
            'ARCHENEMY_OS_RELEASE': str(root / 'os-release'), 'ARCHENEMY_FS_ROOT': str(fsroot),
            'ARCHENEMY_NIX_STORE': str(root / 'nix/store'), 'DP_INSTALLED': ARCH_NAMES}

def os_release(*lines):
    target = root / 'os-release'
    if lines:
        target.write_text('\n'.join(lines) + '\nPRETTY_NAME="' + SECRET_TEXT + '"\n')
    elif target.exists():
        target.unlink()

def snapshot():
    state = {}
    for top in (home, fsroot, root / 'tmp'):
        for p in top.rglob('*'):
            if p.is_symlink():
                state[str(p)] = ('link', os.readlink(p))
            elif p.is_file():
                state[str(p)] = ('file', hashlib.sha256(p.read_bytes()).hexdigest())
            else:
                state[str(p)] = ('dir',)
    return state

def path_without(*names):
    d = root / ('pv-' + '-'.join(names))
    if not d.exists():
        d.mkdir()
        for f in bin_dir.iterdir():
            if f.name not in names:
                (d / f.name).symlink_to(f)
    return str(d) + ':' + str(sys_bin)

def doctor(label, *, full=False, expected=None, env=None, path=None, contains=(), absent=(), script=None):
    current = {**base_env, 'PATH': path or (str(bin_dir) + ':' + str(sys_bin)), **(env or {})}
    calls.write_text('')
    before = snapshot()
    cmd = ['bash', str(script or repo / 'scripts/archenemy-doctor.sh')] + (['--full'] if full else [])
    start = time.monotonic()
    try:
        result = subprocess.run(cmd, env=current, capture_output=True, text=True, timeout=RUN_LIMIT)
    except subprocess.TimeoutExpired:
        bad(label, f'ZABEZPIECZENIE: hung past test limit {RUN_LIMIT:g} s')
        return '', None, ''
    elapsed = time.monotonic() - start
    out = result.stdout
    errors = []
    if elapsed >= DEADLINE:
        errors.append(f'KONTRAKT: doctor < {DEADLINE:g} s, took {elapsed:.2f} s')
    if expected is not None and result.returncode != expected:
        errors.append(f'rc {result.returncode} != {expected}')
    if result.stderr:
        errors.append('stderr: ' + result.stderr[:200])
    if snapshot() != before:
        errors.append('HOME or fixture root changed')
    if not out.rstrip().endswith('problems found'):
        errors.append('no final problem count')
    errors += ['privacy leak: ' + s for s in secrets if s in out]
    errors += ['missing: ' + c for c in contains if c not in out]
    errors += ['unexpected: ' + a for a in absent if a in out]
    if errors:
        bad(label, '; '.join(errors) + '\n' + out)
    else:
        ok(label)
    return out, result.returncode, calls.read_text()

def called(log, tool):
    return any(line.split(' ', 1)[0] == tool for line in log.splitlines())

N = len(REQUIRED)
print('Doctor (D9): platformy na atrapach')
# ─── Arch ────────────────────────────────────────────────────────────────────
os_release('ID=arch')
out, rc, log = doctor('Arch poprawne zero: complete, Missing: 0, kod 0', expected=0,
                      contains=['Platform: arch', f'Package check: complete (pacman; {N} required: {N} checked, 0 missing, 0 unavailable, 0 skipped)', 'Missing: 0'])
(ok if not called(log, 'rpm') and not called(log, 'fc-list') else bad)('Arch: bez rpm i fc-list')
doctor('Arch brak pakietu repo i wymaganego z AUR (brave-bin)', expected=1, env={'DP_MISSING': 'waybar brave-bin'},
       contains=['Missing: 2', 'Problem: required package: waybar', 'Problem: required package: brave-bin'])
doctor('Arch błąd zapytania: unavailable, „Missing: unknown”, nie zero', expected=1, env={'DP_PACMAN': 'fail'},
       contains=['Package check: unavailable', 'Missing: unknown', 'Problem: package query unavailable'], absent=['Missing: 0'])
doctor('Arch pusty wynik zapytania = błąd sondy', expected=1, env={'DP_PACMAN': 'empty'},
       contains=['Problem: package query returned no packages'], absent=['Missing: 0', 'Missing: 44'])
doctor('Arch zawieszony pacman: limit sondy, unavailable, w budżecie', expected=1, env={'DP_PACMAN': 'hang'},
       contains=['Package check: unavailable', 'Problem: package query unavailable'])
doctor('Arch bez pacmana: unavailable i problem, kod 1', expected=1, path=path_without('pacman'),
       contains=['Package check: unavailable', 'Problem: pacman not available'], absent=['Missing: 0'])
aur = repo / 'packages/requirements-aur.txt'
aur_text = aur.read_text()
aur.write_text('# empty\n')
doctor('Arch pusta lista AUR: problem i partial, nie complete', expected=1,
       contains=['Problem: required package list unreadable, empty or invalid: packages/requirements-aur.txt', 'Package check: partial'])
aur.write_text(aur_text)
os_release('ID=endeavouros', 'ID_LIKE=arch')
doctor('pochodna Archa: ścieżka pacmana', expected=0, contains=['Platform: arch-derivative', 'Package check: complete (pacman;'])

# ─── Fedora ──────────────────────────────────────────────────────────────────
os_release('ID=fedora', 'VERSION_ID=44')
fed_checked = N - 1  # ufw → firewalld: system-managed
out, rc, log = doctor('Fedora poprawne zero: rpm + sondy, ufw jako porada, kod 0', expected=0,
       contains=['Platform: fedora', f'Package check: partial (rpm; {N} required: {fed_checked} checked, 0 missing, 0 unavailable, 1 skipped)',
                 'Missing: 0', 'Skipped: ufw (managed by Fedora (firewalld))'])
rpm_calls = [line for line in log.splitlines() if line.startswith('rpm -q ')]
(ok if not called(log, 'pacman') else bad)('Fedora: obcy pacman ani razu')
(ok if len(rpm_calls) == 1 and 'pulseaudio-libs-devel pulseaudio-utils' in rpm_calls[0] else bad)('Fedora: jedno zapytanie rpm dla wszystkich nazw (wiele RPM na wiersz)', str(rpm_calls))
(ok if not called(log, 'dnf') and not called(log, 'nix') else bad)('Fedora: bez dnf/nix (sieć, cache)')
doctor('Fedora braki: RPM, część wiersza wielu RPM, tylko i686', expected=1,
       env={'DP_RPM_MISSING': 'waybar pulseaudio-utils', 'DP_RPM_I686': 'mesa-dri-drivers'},
       contains=['Missing: 3', 'Problem: required package: waybar (RPM not installed: waybar)',
                 'Problem: required package: libpulse (RPM not installed: pulseaudio-utils)',
                 'Problem: required package: mesa (RPM only for another architecture: mesa-dri-drivers (i686))'])
# L2 (przegląd D8–D10): pole ARCH spoza znanych architektur RPM nie trafia do
# raportu — stała etykieta zamiast surowej wartości (krótki kanarek bez
# prefiksów, których szuka safe()).
doctor('Fedora RPM z nieznaną architekturą: stała etykieta, bez surowej wartości', expected=1,
       env={'DP_RPM_ODD': 'mesa-dri-drivers', 'DP_RPM_ODD_ARCH': 'MAPLEBIRD-729'},
       contains=['Missing: 1', 'Problem: required package: mesa (RPM only for another architecture: mesa-dri-drivers (other architecture))'],
       absent=['MAPLEBIRD', '729'])
rpm_rows = sum(1 for p in REQUIRED if MAP[p]['fedora'] != '-' and not MAP[p]['status'].startswith('fedora=system-managed'))
for case, label in [('fail', 'błąd'), ('garbage', 'obce linie z sekretami'), ('empty', 'pusto')]:
    doctor(f'Fedora rpm {label}: unavailable, problem, bez przecieku', expected=1, env={'DP_RPM': case},
           contains=[f'Problem: package check incomplete: {rpm_rows} required packages not checked (rpm query failed)', 'Unavailable: waybar (rpm query failed)'])
doctor('Fedora zawieszony rpm: limit backendu, wszystko unavailable', expected=1, env={'DP_RPM': 'hang'},
       contains=['Package check: unavailable', 'Problem: package query timed out or unavailable'])
doctor('Fedora bez rpm: unavailable dla wierszy RPM', expected=1, path=path_without('rpm'),
       contains=['Problem: package check incomplete', '(rpm not available)'])
doctor('Fedora fc-list błąd: fonty unavailable, nie brak', expected=1, env={'DP_FC': 'fail'},
       contains=['Unavailable: ttf-iosevka-nerd (font query failed or returned no fonts', 'Problem: package check incomplete: 3 required'])
(ok if not list(home.rglob('*CACHE-WRITTEN*')) else bad)('fc-list: zero zapisów cache w HOME (XDG_CACHE_HOME i ~ w /proc)')
bad_map = root / 'bad-map.tsv'
bad_map.write_text('broken\tline\n')
doctor('Fedora zła mapa: unavailable, problem', expected=1, env={'ARCHENEMY_PKG_MAP': str(bad_map)},
       contains=['Problem: package map unreadable or invalid'])
library = repo / 'install/lib/pkg.sh'
library.rename(root / 'pkg.sh.off')
doctor('Fedora bez install/lib/pkg.sh: unavailable', expected=1, contains=['Problem: package library install/lib/pkg.sh missing'])
(root / 'pkg.sh.off').rename(library)
os_release('ID=fedora', 'VARIANT_ID=silverblue')
out, rc, log = doctor('Fedora Atomic: unsupported, bez rpm i pacmana', expected=1,
                      contains=['Platform: unsupported', 'Problem: unsupported or unknown distribution'])
(ok if not called(log, 'rpm') and not called(log, 'pacman') else bad)('Fedora Atomic: zero zapytań pakietów')

# ─── NixOS ───────────────────────────────────────────────────────────────────
os_release('ID=nixos')
nix_skipped = sum(1 for p in REQUIRED if 'nixos=system-managed' in MAP[p]['status'] or MAP[p]['check'] == '-')
out, rc, log = doctor('NixOS: sondy z mapy, system-managed jako porada, kod 0', expected=0,
       contains=['Platform: nixos', f'Package check: partial (package map probes, no nix CLI; {N} required: {N - nix_skipped} checked, 0 missing, 0 unavailable, {nix_skipped} skipped)',
                 'Skipped: hyprland (system-managed: NixOS option programs.hyprland.enable)',
                 'Skipped: hyprpolkitagent (no probe in package map)', 'Skipped: coreutils (part of the base NixOS system)'])
(ok if not any(called(log, t) for t in ('pacman', 'rpm', 'nix', 'nix-env', 'nixos-rebuild', 'dnf')) else bad)('NixOS: bez pacmana, rpm, nix CLI, dnf')
doctor('NixOS brak polecenia: missing z sondy', expected=1, path=path_without('waybar'),
       contains=['Problem: required package: waybar (command not found: waybar)'])
doctor('NixOS bez fc-list: fonty unavailable', expected=1, path=path_without('fc-list'),
       contains=['Unavailable: ttf-iosevka-nerd (fc-list not available)'])
doctor('NixOS zawieszony fc-list: limit backendu', expected=1, env={'DP_FC': 'hang'},
       contains=['Problem: package query timed out or unavailable'])

# ─── nieznana platforma ──────────────────────────────────────────────────────
os_release('ID=debian')
out, rc, log = doctor('nieznana (obcy pacman w PATH): unavailable, bez zgadywania', expected=1,
                      contains=['Platform: unsupported', 'Package check: unavailable (none;'])
(ok if not called(log, 'pacman') and not called(log, 'rpm') else bad)('nieznana: pacman i rpm ani razu')
os_release()
doctor('brak os-release: unknown, unavailable', expected=1, contains=['Platform: unknown', 'Problem: unsupported or unknown distribution'])

# ─── --full: gaming-diag --doctor (prawdziwy skrypt) ────────────────────────
os_release('ID=arch')
doctor('--full Arch: gaming-diag completed', full=True, expected=0, contains=['gaming-diag: completed'])
os_release('ID=fedora')
doctor('--full Fedora: gaming-diag completed (rpm -qa), sekrety z Vendor nie publikowane', full=True, expected=0,
       env={'DP_VENDOR': SECRET_TEXT}, contains=['gaming-diag: completed'])
doctor('--full Fedora błąd rpm: gaming-diag partial z kluczami', full=True, expected=1, env={'DP_RPM': 'fail'},
       contains=['gaming-diag: partial (not checked: packages, foreign, nvidia-32bit, history)'])
os_release('ID=nixos')
doctor('--full NixOS: gaming-diag completed bez FHS', full=True, expected=0, path=path_without('asusctl'), contains=['gaming-diag: completed'])
os_release('ID=debian')
doctor('--full nieznana: gaming-diag partial (platform…)', full=True, expected=1,
       contains=['gaming-diag: partial (not checked: platform, packages, foreign, nvidia-32bit, owners, history, initramfs)'])
os_release('ID=arch')
doctor('--full Arch zawieszony pacman: gaming-diag timed out, całość w budżecie', full=True, expected=1, env={'DP_PACMAN': 'hang'},
       contains=['gaming-diag: timed out or unavailable'])
real_gaming = repo / 'scripts/hypr/gaming-diag.sh'
gaming_text = real_gaming.read_text()
real_gaming.write_text('#!/usr/bin/env bash\necho "$DOCTOR_SECRETS"\necho "diagnosis: partial; not checked: $DOCTOR_SECRETS"\nexit 2\n')
doctor('--full: znacznik spoza listy kluczy / z sekretem odrzucony', full=True, expected=0,
       contains=['gaming-diag: reported unavailable components'])
real_gaming.write_text('#!/usr/bin/env bash\necho "diagnosis: partial; not checked: kernel-log"\nexit 2\n')
doctor('--full: klucz spoza trybu --doctor odrzucony', full=True, expected=0, contains=['gaming-diag: reported unavailable components'])
real_gaming.write_text(gaming_text)

# ─── rice yin, oba tryby ─────────────────────────────────────────────────────
link_rice('yin')
yin_dirs = sum(1 for p in (repo / 'rices/yin').iterdir() if p.is_dir())
for full in (False, True):
    mode = ' --full' if full else ''
    doctor('yin poprawny' + mode, full=full, expected=0, contains=['Active: yin', f'Expected rice links checked: {yin_dirs}']
           + (['Link OK: waybar', 'Link OK: networkmanager-dmenu'] if full else []), absent=['stale rice link'])
    (config / 'mako').unlink()
    (config / 'mako').symlink_to(repo / 'rices/yin/missing-mako')
    doctor('yin wiszący link' + mode, full=full, expected=1, contains=['Problem: missing, broken or wrong rice link: mako'])
    (config / 'mako').unlink()
    (config / 'mako').symlink_to(repo / 'rices/yin/mako')
    (config / 'rofi').unlink()
    (config / 'rofi').symlink_to(repo / 'rices/white-blue/rofi')
    doctor('yin zły link (do white-blue)' + mode, full=full, expected=1,
           contains=['Problem: missing, broken or wrong rice link: rofi', 'Problem: stale rice link (name withheld)'])
    (config / 'rofi').unlink()
    (config / 'rofi').symlink_to(repo / 'rices/yin/rofi')
    background = repo / 'config/hypr/hyprlock-background-yin.conf'
    background.unlink()
    doctor('yin bez tła hyprlock' + mode, full=full, expected=1, contains=['Problem: required hyprlock background missing'])
    background.touch()
link_rice('white-blue')

# ─── parytet Archa z rewizją ─────────────────────────────────────────────────
rev = os.environ.get('DOCTOR_PLATFORMS_REV')
if rev:
    print(f'\nParytet Archa z {rev}')
    base_script = repo / 'scripts/archenemy-doctor-base.sh'
    base_script.write_text(subprocess.run(['git', '-C', str(source), 'show', f'{rev}:scripts/archenemy-doctor.sh'],
                                          capture_output=True, text=True, check=True).stdout)
    # Rewizja oblicza repo z własnej ścieżki: ten sam katalog scripts/.
    new_only = ('  Platform: ', '  Package check: ', '  Missing: unknown')
    def strip_new(text):
        return '\n'.join(l for l in text.splitlines() if not l.startswith(new_only))
    real_gaming.write_text('#!/usr/bin/env bash\necho "diagnosis: complete"\nexit 0\n')
    def parity(label, fixes=None, **kw):
        old_out, old_rc, _ = doctor(f'(rewizja) {label}', script=base_script, **kw)
        kw.pop('expected', None)
        new_out, new_rc, _ = doctor(f'(HEAD) {label}', **kw)
        if fixes is None:
            same = strip_new(old_out) == strip_new(new_out) and old_rc == new_rc
            (ok if same else bad)(f'Arch = {rev}: {label}', '' if same else f'\n--- {rev}\n{old_out}\n--- HEAD\n{new_out}')
        else:
            problems = fixes(old_out, old_rc, new_out, new_rc)
            (ok if not problems else bad)(f'Arch {rev} → HEAD (poprawka): {label}', problems or '')
    os_release('ID=arch')
    parity('komplet')
    parity('komplet --full', full=True)
    parity('brak pakietu z repo', env={'DP_MISSING': 'waybar'})
    parity('błąd zapytania', env={'DP_PACMAN': 'fail'})
    link_rice('yin')
    parity('yin poprawny', full=True)
    (config / 'rofi').unlink()
    (config / 'rofi').symlink_to(repo / 'rices/white-blue/rofi')
    parity('yin zły link')
    link_rice('white-blue')
    os_release('ID=endeavouros', 'ID_LIKE=arch')
    parity('pochodna Archa')
    os_release('ID=arch')
    def fix_aur(o, orc, n, nrc):
        return '' if ('0 problems found' in o and orc == 0 and 'Problem: required package: brave-bin' in n
                      and '1 problems found' in n and nrc == 1) else f'{orc}/{nrc}'
    parity('brak wymaganego z AUR: dawniej „0 problems”', fix_aur, env={'DP_MISSING': 'brave-bin'})
    def fix_no_pacman(o, orc, n, nrc):
        return '' if ('  pacman not available' in o and orc == 0 and 'Problem: pacman not available' in n
                      and 'Missing: unknown' in n and nrc == 1) else f'{orc}/{nrc}'
    parity('brak pacmana: dawniej kod 0', fix_no_pacman, path=path_without('pacman'))
    def fix_empty(o, orc, n, nrc):
        n_pacman = N - len([e for e in aur_text.splitlines() if e.strip() and not e.startswith('#')])
        return '' if (f'Missing: {n_pacman}' in o and o.count('Problem: required package') == n_pacman
                      and 'Problem: package query returned no packages' in n
                      and 'Missing: unknown' in n and n.count('Problem:') == 1) else f'{orc}/{nrc}'
    parity('pusty wynik zapytania: dawniej wszystkie „brakujące”', fix_empty, env={'DP_PACMAN': 'empty'})
    aur.write_text('# empty\n')
    def fix_list(o, orc, n, nrc):
        return '' if ('0 problems found' in o and 'requirements-aur.txt' in n and nrc == 1) else f'{orc}/{nrc}'
    parity('pusta lista AUR: dawniej pominięta', fix_list)
    aur.write_text(aur_text)
    real_gaming.write_text(gaming_text)
    base_script.unlink()

print(f"\nWynik: {results['pass']} ✓ / {results['fail']} ✗")
sys.exit(1 if results['fail'] else 0)
PY
rc=$?
if escaped="$(test_escapes "$T")"; then echo "  ✓ zero zapisów poza \$T w: $(test_isolation_dirs)"
elif [[ $? == 2 ]]; then echo "  – izolacja niedostępna (unshare/overlay)"
else echo "  ✗ zapisy poza \$T: ${escaped//$'\n'/ }"; rc=1; fi
exit "$rc"
