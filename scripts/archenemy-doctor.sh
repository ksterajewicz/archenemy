#!/bin/bash
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
full = bool(args)
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
                                   text=True, errors='replace', start_new_session=True,
                                   env={**os.environ, 'GIT_OPTIONAL_LOCKS': '0', 'LC_ALL': 'C'})
        try:
            output, _ = process.communicate(timeout=min(limit, remaining))
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate()
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
print('  Path: ' + safe(repo))
code, branch = git('rev-parse', '--abbrev-ref', 'HEAD')
if code == 0:
    branch = branch.strip()
    print('  Branch: ' + safe(branch))
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
    rice = (repo / '.current_rice').read_text().strip()
except OSError:
    rice = ''
# Nazwa musi być katalogiem śledzonego rice, nie dowolną ścieżką z pliku.
valid_rice = bool(re.fullmatch(r'[a-z0-9_-]+', rice)) and (repo / 'rices' / rice).is_dir()
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
canonical = (home / 'archenemy').resolve() == repo
if canonical:
    code, _ = run('bash', str(repo / 'scripts/hypr/machine-layer-check.sh'), '--doctor', limit=0.45)
    print('  machine-layer-check: ' + ('OK' if code == 0 else 'problems; rerun install.sh' if code == 1 else 'unavailable or timed out'))
    if code == 1:
        problem('machine layer check failed')
else:
    print('  machine-layer-check: skipped (checkout is outside ~/archenemy)')

section('Required packages')
if not shutil.which('pacman'):
    print('  pacman not available')
else:
    code, installed = run('pacman', '-Qq', limit=0.4)
    if code != 0:
        problem('package query unavailable')
    else:
        installed = set(installed.splitlines())
        required = [line.split('#', 1)[0].strip() for line in (repo / 'packages/requirements-pacman.txt').read_text().splitlines()]
        missing_packages = [p for p in required if p and p not in installed]
        print(f'  Missing: {len(missing_packages)}')
        for package in missing_packages:
            problem('required package: ' + safe(package))

section('Daemons (current user)')
for name, pattern in [('waybar', None), ('mako', None), ('hyprpaper', None), ('flux-wall', None), ('window-history', r'window-history\.sh daemon'), ('orphan guard', r'workspace-orphan-guard\.sh')]:
    code, _ = run('pgrep', '-u', str(os.getuid()), '-f' if pattern else '-x', pattern or name)
    print('  ' + name + ': ' + ('running' if code == 0 else 'not running' if code == 1 else 'unavailable'))

section('Shell')
print('  Login shell: ' + safe(identity.pw_shell))
for kind, rc in [('bash', home / '.bashrc'), ('zsh', Path(os.environ.get('ZDOTDIR', str(home))) / '.zshrc')]:
    try:
        text = rc.read_text()
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
    for label, script, extra, needs_session in [('workspace-diag', 'hypr/workspace-diag.sh', [], True), ('gaming-diag', 'hypr/gaming-diag.sh', [], False), ('flux-wall doctor', 'wallpapers/flux-wall.sh', ['doctor'], False)]:
        if not canonical:
            state = 'skipped (checkout is outside ~/archenemy)'
        elif needs_session and not running:
            state = 'not running'
        else:
            code, _ = run('bash', str(repo / 'scripts' / script), *extra, limit=0.35)
            state = 'completed' if code == 0 else 'reported unavailable components' if code is not None else 'timed out or unavailable'
        print('  ' + label + ': ' + state)
print(f'\n{problems} problems found')
sys.exit(1 if problems else 0)
PY
