#!/usr/bin/env bash
# =============================================
#   archenemy - diagnostyka do publicznych zgłoszeń.
#   Tylko odczyt; Python (już wymagany) pilnuje wspólnego limitu czasu
#   i parsuje JSON bez uruchamiania danych jako kodu.
# =============================================
set -u
export PYTHONDONTWRITEBYTECODE=1
exec python - "$0" "$@" <<'PY'
import json
import os
from pathlib import Path
import pwd
import re
import shutil
import signal
import socket
import stat
import subprocess
import sys
import time

args = sys.argv[2:]
if args not in ([], ['--full'], ['--help']):
    print('Usage: archenemy doctor [--full]')
    sys.exit(1)
if args == ['--help']:
    print('Usage: archenemy doctor [--full]\nRead-only, offline diagnostics for public bug reports.')
    sys.exit(0)
# Osobny nadzorca obejmuje również odczyty plików i sprzątanie potomków.
sys.stdout.reconfigure(line_buffering=True)
started = time.monotonic()
worker = os.fork()
if worker:
    status = None
    while time.monotonic() - started < 4.5:
        done, status = os.waitpid(worker, os.WNOHANG)
        if done:
            break
        time.sleep(0.01)
    else:
        status = None
    try:
        os.killpg(worker, signal.SIGKILL)
    except ProcessLookupError:
        pass
    if status is None:
        print('  Problem: collection deadline exceeded\n\n1 problems found')
        sys.exit(1)
    sys.exit(os.waitstatus_to_exitcode(status))
os.setsid()
full = bool(args)

# O_NONBLOCK chroni także przed podmianą pliku na FIFO między stat i open.
def read_local(path, maximum=1024 * 1024):
    try:
        info = path.stat()
        if not stat.S_ISREG(info.st_mode) or info.st_size > maximum:
            return ''
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        with os.fdopen(fd, 'rb') as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_size > maximum:
                return ''
            data = stream.read(maximum + 1)
            return data.decode('utf-8', errors='replace') if len(data) <= maximum else ''
    except OSError:
        return ''
repo = Path(sys.argv[1]).resolve().parent.parent
home = Path.home()
config = Path(os.environ.get('XDG_CONFIG_HOME', str(home / '.config')))
deadline = time.monotonic() + 4.0
problems = 0
identity = pwd.getpwuid(os.getuid())
private = {str(home), identity.pw_name, socket.gethostname(),
           os.environ.get('USER', ''), os.environ.get('LOGNAME', '')}

def safe(value):
    text = str(value).replace(str(home), '~')
    for item in sorted(private - {str(home), ''}, key=len, reverse=True):
        text = text.replace(item, '~')
    text = re.sub(r'/home/[^/\s]+|/root(?=/|$)', '~', text)
    text = re.sub(r'(?i)(?:[0-9a-f]{2}:){5}[0-9a-f]{2}|(?:\d{1,3}\.){3}\d{1,3}|[0-9a-f]*:[0-9a-f:]+:[0-9a-f:]*', '[address]', text)
    text = re.sub(r'(?i)(?:token|secret|password|api[_-]?key)[^/\s]*|[a-z0-9_=-]{32,}', '[redacted]', text)
    return ''.join(c if c.isprintable() else '?' for c in text)[:200]

def section(name):
    print('\n' + name + ':')

def problem(text):
    global problems
    problems += 1
    print('  Problem: ' + text)

# Żadne surowe stdout/stderr narzędzi nie trafia do raportu. Swobodny tekst
# może zawierać dowolny sekret, więc publikujemy wyłącznie pola i liczniki.
def run(*cmd, limit=0.25):
    remaining = deadline - time.monotonic()
    if remaining <= 0 or not shutil.which(str(cmd[0])):
        return None, ''
    try:
        process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                   text=True, errors='replace', start_new_session=False,
                                   env={**os.environ, 'GIT_OPTIONAL_LOCKS': '0', 'LC_ALL': 'C'})
        try:
            output, _ = process.communicate(timeout=min(limit, remaining))
        except subprocess.TimeoutExpired:
            process.kill()
            try:
                process.communicate(timeout=0.05)
            except subprocess.TimeoutExpired:
                process.stdout.close()
            return None, ''
        return process.returncode, output
    except (OSError, subprocess.TimeoutExpired):
        return None, ''

def version(*cmd):
    code, output = run(*cmd)
    match = re.search(r'\b\d+\.\d+(?:\.\d+)?', output) if code == 0 else None
    return match.group() if match else 'unavailable'

def git(*cmd):
    return run('git', '-C', str(repo), *cmd)

print('archenemy doctor (public report; free-form output withheld for privacy)')
section('Repository')
print('  Path: ' + ('~/archenemy' if repo == home / 'archenemy' else '[checkout path withheld]'))
code, branch = git('rev-parse', '--abbrev-ref', 'HEAD')
if code == 0:
    branch = branch.strip()
    print('  Branch: ' + (branch if branch in {'dev', 'main', 'master', 'HEAD'} else '[custom branch withheld]'))
    _, commit = git('rev-parse', '--short=12', 'HEAD')
    print('  Commit: ' + (commit.strip() if re.fullmatch(r'[a-f0-9]{7,40}\n?', commit) else 'unknown'))
    code, status = git('status', '--porcelain', '--untracked-files=normal')
    print('  Working tree: ' + ('clean' if not status else 'dirty') if code == 0 else '  Working tree: unavailable')
    code, behind = git('rev-list', '--count', 'HEAD..refs/remotes/origin/' + branch)
    print('  Behind origin: ' + (behind.strip() + ' commits (cached; no fetch)' if code == 0 and behind.strip().isdigit() else 'unknown (no cached origin branch)'))
else:
    print('  Git metadata: unavailable')

section('Rice')
try:
    rice = read_local(repo / '.current_rice', 256).strip()
except OSError:
    rice = ''
# Nazwa musi być katalogiem śledzonego rice, nie dowolną ścieżką z pliku.
known_rices = {'white-blue', 'white-blue_beta', 'tron', 'asia-n-rice', 'dither-flux', 'crt', 'yin'}
valid_rice = (rice in known_rices and (repo / 'rices' / rice).is_dir()
              and (repo / 'rices' / rice).resolve().is_relative_to(repo / 'rices'))
print('  Active: ' + (safe(rice) if valid_rice else 'missing or invalid'))
if valid_rice:
    checked = 0
    for target in sorted((repo / 'rices' / rice).iterdir()):
        if not target.is_dir():
            continue
        link = config / target.name
        checked += 1
        if not link.is_symlink() or not link.exists() or link.resolve() != target.resolve():
            problem('missing, broken or wrong rice link: ' + safe(target.name))
        elif full:
            print('  Link OK: ' + safe(target.name))
    print(f'  Expected rice links checked: {checked}')
else:
    problem('active rice cannot be checked')
for link in sorted(config.glob('*')):
    if link.is_symlink() and not link.exists():
        # Nie ujawniamy nazw obcych konfiguracji.
        if not valid_rice or not (repo / 'rices' / rice / link.name).is_dir():
            problem('additional broken config symlink (name withheld)')
    elif link.is_symlink() and str(link.resolve()).startswith(str(repo / 'rices') + '/'):
        if valid_rice and not str(link.resolve()).startswith(str(repo / 'rices' / rice) + '/'):
            # Współdzielone katalogi beta i dowiązania per rice rozwiązujemy
            # względem celu oczekiwanego, nie surowej ścieżki.
            expected = repo / 'rices' / rice / link.name
            if not expected.exists() or expected.resolve() != link.resolve():
                problem('stale rice link (name withheld)')

section('Hyprland')
running = False
if os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'):
    code, output = run('hyprctl', 'version')
    running = code == 0 and 'Hyprland' in output
if not running:
    print('  not running')
else:
    print('  Version: ' + version('hyprctl', 'version'))
    code, errors = run('hyprctl', 'configerrors')
    if code != 0:
        problem('configerrors query unavailable')
    elif errors.strip() and errors.strip().lower() != 'ok':
        problem(f'configerrors: {len(errors.splitlines())} lines; contents withheld')
    else:
        print('  configerrors: none')
    code, binds = run('hyprctl', '-j', 'binds')
    try:
        binds = json.loads(binds) if code == 0 else None
        if not isinstance(binds, list):
            raise ValueError()
        appbinds = [b for b in binds if b.get('modmask') == 64 and str(b.get('key', '')).upper() == 'A' and not b.get('submap')]
        direct = any('appbinds' in str(b.get('arg', '')) for b in appbinds)
        lua = any(b.get('dispatcher') == '__lua' for b in appbinds)
        print(f'  Binds: {len(binds)}')
        print('  Super+A -> appbinds: ' + ('loaded' if direct else 'Super+A loaded; Lua target not exposed by hyprctl' if lua else 'not loaded'))
        if not direct and not lua and rice != 'white-blue_beta':
            problem('Super+A appbinds bind missing')
    except (ValueError, TypeError, AttributeError):
        problem('binds query unavailable')

section('Machine and personal layers')
files = ['hypr/' + name for name in ('monitorshyprl.lua', 'workspaces-monitors.lua', 'hardware-keys.lua', 'gpu-env.lua', 'autostartpersonalisation.lua', 'autostart-apps.lua', 'appbinds.lua', 'mouse.lua', 'keyboard-layouts.lua', 'hyprpaper.conf')]
files += ['shell/' + name for name in ('shellrc', 'keys.zsh', 'plugins.zsh', 'cli-tools.bash', 'cli-tools.zsh')]
files += ['mpd/output.conf', 'mpd/local.conf']
files += ['hypr/hyprlock-background-' + p.name + '.conf' for p in sorted((repo / 'rices').iterdir()) if p.is_dir() and p.name != 'white-blue_beta']
missing = [name for name in files if not (repo / 'config' / name).exists()]
print(f'  Generated files: {len(files) - len(missing)} present, {len(missing)} missing')
for name in missing:
    print('  Missing: config/' + safe(name))
if full:
    for name in files:
        if name not in missing:
            print('  Present: config/' + safe(name))
lock_rice = 'white-blue' if rice == 'white-blue_beta' else rice
if valid_rice and not (repo / 'config/hypr' / ('hyprlock-background-' + lock_rice + '.conf')).is_file():
    problem('required hyprlock background missing')
canonical = (home / 'archenemy').resolve() == repo
if canonical:
    code, _ = run('bash', str(repo / 'scripts/hypr/machine-layer-check.sh'), '--doctor', limit=0.45)
    print('  machine-layer-check: ' + ('OK' if code == 0 else 'problems; rerun install.sh' if code == 1 else 'unavailable or timed out'))
    if code == 1:
        problem('machine layer check failed')
else:
    print('  machine-layer-check: skipped (checkout is outside ~/archenemy)')

# Platforma jak pkg_route w install/lib/pkg.sh (os-release bez eval; pochodne
# Archa idą ścieżką Archa). Publikujemy tylko klasę, nie surowe os-release.
def platform_route():
    test = os.environ.get('ARCHENEMY_TEST') == '1'
    sources = [Path(os.environ['ARCHENEMY_OS_RELEASE'])] if test and os.environ.get('ARCHENEMY_OS_RELEASE') else [Path('/etc/os-release'), Path('/usr/lib/os-release')]
    text = ''
    for source in sources:
        text = read_local(source)
        if text:
            break
    values = {}
    for line in text.splitlines():
        if '=' in line:
            key, value = line.split('=', 1)
            if len(value) >= 2 and value[0] == value[-1] and value[0] in '"\'':
                value = value[1:-1]
            values.setdefault(key, value)
    os_id = values.get('ID', '')
    if not os_id:
        return 'unknown'
    if os_id == 'arch':
        return 'arch'
    if 'arch' in values.get('ID_LIKE', '').split():
        return 'arch-derivative'
    if os_id == 'nixos':
        return 'nixos'
    if os_id == 'fedora':
        marker = Path(os.environ['ARCHENEMY_OSTREE_MARKER']) if test and os.environ.get('ARCHENEMY_OSTREE_MARKER') else Path('/run/ostree-booted')
        variant = values.get('VARIANT_ID', '')
        if marker.exists() or 'atomic' in variant or variant in {'silverblue', 'kinoite', 'sericea', 'onyx'}:
            return 'unsupported'
        return 'fedora'
    return 'unsupported'

package_name = re.compile(r'[A-Za-z0-9][A-Za-z0-9+._-]*')
def required_list(name):
    entries = [line.split('#', 1)[0].strip() for line in read_local(repo / 'packages' / name).splitlines()]
    entries = [entry for entry in entries if entry]
    return entries if entries and all(package_name.fullmatch(e) for e in entries) else None

# Każdy wymagany pakiet ma jawny stan: checked | missing | unavailable | skipped.
# Brak backendu, błąd zapytania i pusta lista to błąd sondy, nigdy „Missing: 0”.
section('Required packages')
route = platform_route()
print('  Platform: ' + route)
required = []
broken_lists = 0
for name in ('requirements-pacman.txt', 'requirements-aur.txt'):
    entries = required_list(name)
    if entries is None:
        broken_lists += 1
        problem('required package list unreadable, empty or invalid: packages/' + name)
    else:
        required += [entry for entry in entries if entry not in required]
states = {}
reason = None
if route in ('arch', 'arch-derivative'):
    backend = 'pacman'
    if not shutil.which('pacman'):
        reason = 'pacman not available'
    else:
        code, installed = run('pacman', '-Qq', limit=0.4)
        installed = set(installed.splitlines()) - {''}
        if code != 0:
            reason = 'package query unavailable'
        elif not installed:
            reason = 'package query returned no packages'
    for package in required:
        states[package] = ('unavailable', reason) if reason else ('checked', '') if package in installed else ('missing', '')
elif route in ('fedora', 'nixos'):
    # Backend z install/lib/pkg.sh: jedno zapytanie rpm (Fedora) albo sondy
    # z mapy (NixOS, bez nix CLI); wyjście to tylko id ze stanem z kontrolowanego zbioru.
    backend = 'rpm' if route == 'fedora' else 'package map probes, no nix CLI'
    library = repo / 'install/lib/pkg.sh'
    code, output = (None, '') if not required or not library.is_file() else run(
        'bash', '-c', 'source "$1" && shift && pkg_check_ids "$@"', '_', str(library), *required, limit=1.0)
    detail_ok = re.compile(r'[A-Za-z0-9 .,:;()+_=/-]{0,160}')
    parsed = {}
    for line in output.splitlines() if code == 0 else []:
        fields = line.split('\t')
        if (len(fields) != 3 or fields[0] not in required or fields[0] in parsed
                or fields[1] not in ('checked', 'missing', 'unavailable', 'skipped')):
            parsed = None
            break
        parsed[fields[0]] = (fields[1], fields[2] if detail_ok.fullmatch(fields[2]) else 'details withheld')
    if parsed is not None and set(parsed) != set(required):
        parsed = None
    if not library.is_file():
        reason = 'package library install/lib/pkg.sh missing'
    elif code is None:
        reason = 'package query timed out or unavailable'
    elif code == 2:
        reason = 'package map unreadable or invalid'
    elif code != 0 or parsed is None:
        reason = 'package query output invalid'
    states = {p: ('unavailable', reason) for p in required} if reason else parsed
else:
    # Bez zgadywania: obcy pacman na nieznanym systemie nie jest pytany.
    backend = 'none'
    reason = 'unsupported or unknown distribution'
    states = {p: ('unavailable', reason) for p in required}
if not required:
    reason = 'no readable required package list'
counts = {s: sum(1 for state, _ in states.values() if state == s) for s in ('checked', 'missing', 'unavailable', 'skipped')}
coverage = ('unavailable' if reason or counts['unavailable'] == len(required) else
            'complete' if not counts['unavailable'] and not counts['skipped'] and not broken_lists else 'partial')
print(f'  Package check: {coverage} ({backend}; {len(required)} required: ' + ', '.join(f'{counts[s]} {s}' for s in counts) + ')')
if coverage == 'unavailable':
    print('  Missing: unknown')
    problem(reason or 'package check unavailable')
else:
    print(f'  Missing: {counts["missing"]}')
    for package in required:
        state, detail = states[package]
        if state == 'missing':
            # Arch jak dotąd: sama nazwa; Fedora/NixOS: brakujące RPM / sonda z mapy.
            problem('required package: ' + safe(package) + (' (' + safe(detail) + ')' if detail else ''))
    for package in required:
        state, detail = states[package]
        if state in ('unavailable', 'skipped'):
            print(f'  {state.capitalize()}: ' + safe(package) + (' (' + safe(detail) + ')' if detail else ''))
    for text in sorted({detail for state, detail in states.values() if state == 'unavailable'}):
        problem(f'package check incomplete: {sum(1 for s, d in states.values() if s == "unavailable" and d == text)} required packages not checked (' + safe(text) + ')')

section('Daemons (current user)')
for name, pattern in [('waybar', None), ('mako', None), ('hyprpaper', None), ('flux-wall', None), ('window-history', r'window-history\.sh daemon'), ('orphan guard', r'workspace-orphan-guard\.sh')]:
    code, _ = run('pgrep', '-u', str(os.getuid()), '-f' if pattern else '-x', pattern or name)
    print('  ' + name + ': ' + ('running' if code == 0 else 'not running' if code == 1 else 'unavailable'))

section('Shell')
print('  Login shell: ' + safe(identity.pw_shell))
for kind, rc in [('bash', home / '.bashrc'), ('zsh', Path(os.environ.get('ZDOTDIR', str(home))) / '.zshrc')]:
    try:
        text = read_local(rc)
    except OSError:
        text = ''
    start = text.find('# >>> archenemy shell >>>')
    end = text.find('# <<< archenemy shell <<<', start)
    print(f'  {kind} managed rc block: ' + ('present' if start >= 0 and end > start else 'missing or incomplete'))
    print(f'  {kind} version: ' + version(kind, '--version'))

section('Hardware')
code, pci = run('lspci', '-nnk')
if code == 0:
    # Tylko identyfikatory PCI i nazwa modułu, bez dowolnych etykiet sprzętu.
    gpu = re.findall(r'^.*(?:VGA|3D controller|Display controller).*?\[([0-9a-f]{4}:[0-9a-f]{4})\]', pci, re.M)
    print('  GPU PCI IDs: ' + (', '.join(gpu) or 'none detected'))
    drivers = re.findall(r'Kernel driver in use: ([a-zA-Z0-9_-]+)', pci)
    print('  PCI drivers: ' + (', '.join(sorted(set(drivers))) or 'unknown'))
else:
    print('  lspci: unavailable')
print('  NVIDIA driver: ' + version('nvidia-smi', '--query-gpu=driver_version', '--format=csv,noheader'))
print('  asusctl version: ' + version('asusctl', '--version'))
code, profile = run('asusctl', 'profile', 'get')
profiles = re.findall(r'\b(?:Quiet|Balanced|Performance)\b', profile) if code == 0 else []
print('  ASUS profile: ' + (profiles[-1] if profiles else 'unavailable'))

if full:
    section('Existing diagnostics (private contents withheld)')
    # gaming-diag --doctor: tylko sondy pakietów/sterownika, bez wyjścia poza
    # znacznikiem kompletności; publikujemy wyłącznie klucze z tej listy.
    gaming_keys = {'platform', 'packages', 'foreign', 'nvidia-32bit', 'owners', 'history', 'initramfs', 'vulkan-icd'}
    for label, script, extra, needs_session in [('workspace-diag', 'hypr/workspace-diag.sh', [], True), ('gaming-diag', 'hypr/gaming-diag.sh', ['--doctor'], False), ('flux-wall doctor', 'wallpapers/flux-wall.sh', ['doctor-safe'], False)]:
        if not canonical:
            state = 'skipped (checkout is outside ~/archenemy)'
        elif needs_session and not running:
            state = 'not running'
        else:
            code, output = run('bash', str(repo / 'scripts' / script), *extra, limit=0.35)
            state = 'completed' if code == 0 else 'reported unavailable components' if code is not None else 'timed out or unavailable'
            if label == 'gaming-diag' and code is not None:
                marker = re.fullmatch(r'diagnosis: (complete|partial; not checked: ([a-z0-9-]+(?:, [a-z0-9-]+)*))', output.strip())
                items = marker.group(2).split(', ') if marker and marker.group(2) else []
                if code == 0 and marker and not items:
                    state = 'completed'
                elif code == 2 and items and set(items) <= gaming_keys:
                    state = 'partial (not checked: ' + ', '.join(items) + ')'
                else:
                    state = 'reported unavailable components'
        print('  ' + label + ': ' + state)
print(f'\n{problems} problems found')
sys.exit(1 if problems else 0)
PY
