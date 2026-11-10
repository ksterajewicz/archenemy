#!/bin/bash
# =============================================
#   Diagnostyka na atrapach: prywatność, kody, odczyt i limit czasu.
# =============================================
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
test_environment_init "$T"
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

root = Path(os.environ['DOCTOR_TEST_TREE'])
source = Path(os.environ['DOCTOR_SOURCE'])
home = Path(os.environ['HOME'])
repo = home / 'archenemy'
bin_dir = root / 'bin'
bin_dir.mkdir()
for name in ['scripts/archenemy-doctor.sh', 'scripts/appbinds/appbinds.sh',
             'scripts/hypr/machine-layer-check.sh', 'scripts/hypr/lib/monitor-id.sh',
             'scripts/wallpapers/flux-wall.sh']:
    path = repo / name
    path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / name, path)
(repo / 'packages').mkdir()
(repo / 'packages/requirements-pacman.txt').write_text('# fixture\nhyprland\nwaybar\n')
(repo / 'rices/white-blue/hypr').mkdir(parents=True)
(home / '.config').mkdir()
(home / '.config/hypr').symlink_to(repo / 'rices/white-blue/hypr')
(repo / '.current_rice').write_text('white-blue\n')
for name in ['monitorshyprl.lua', 'workspaces-monitors.lua', 'hardware-keys.lua',
             'gpu-env.lua', 'autostartpersonalisation.lua', 'appbinds.lua', 'hyprpaper.conf',
             'hyprlock-background-white-blue.conf']:
    path = repo / 'config/hypr' / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.touch()
(home / '.bashrc').write_text('# >>> archenemy shell >>>\n# <<< archenemy shell <<<\n')

# Atrapy odrzucają każde nieznane wywołanie; żadnych mutacji gita/pacmana/IPC.
mocks = {
'git': '''#!/bin/bash
[[ "$GIT_OPTIONAL_LOCKS" == 0 ]] || exit 90
shift 2
case "$*" in
 'rev-parse --abbrev-ref HEAD') echo "${DOCTOR_BRANCH:-dev}" ;;
 'rev-parse --short=12 HEAD'|'rev-parse HEAD') echo 0123456789ab ;;
 'status --porcelain --untracked-files=normal') : ;;
 'rev-list --count HEAD..refs/remotes/origin/'*) echo 2 ;;
 *) exit 91 ;;
esac
''',
'pacman': '''#!/bin/bash
[[ "$*" == -Qq ]] || exit 92
printf 'hyprland\\n'
[[ "${DOCTOR_CASE:-}" == packages ]] || echo waybar
''',
'hyprctl': '''#!/bin/bash
[[ "${DOCTOR_CASE:-}" == hung ]] && { sleep 10; exit; }
case "$*" in
 version) echo 'Hyprland 0.57.0' ;;
 configerrors) [[ "${DOCTOR_CASE:-}" == errors ]] && printf '%s\\n' "$DOCTOR_SECRETS"; exit 0 ;;
 '-j binds')
 if [[ "${DOCTOR_CASE:-}" == wrong-bind ]]; then
 echo '[{"modmask":64,"key":"B","arg":"appbinds.sh"}]'
 elif [[ "${DOCTOR_CASE:-}" == lua ]]; then
 echo '[{"modmask":64,"key":"A","dispatcher":"__lua"}]'
 else
 echo '[{"modmask":64,"key":"A","arg":"appbinds.sh"}]'
 fi ;;
 monitors) : ;;
 *) exit 93 ;;
esac
''',
'pgrep': '#!/bin/bash\nexit 1\n',
'lspci': '#!/bin/bash\nprintf "%s\\n" "$DOCTOR_SECRETS"\necho "00:02.0 VGA compatible controller [0300]: example [1234:5678]"\necho "  Kernel driver in use: testdriver"\n',
'nvidia-smi': '#!/bin/bash\necho 555.12.3\n',
'asusctl': '#!/bin/bash\ncase "$*" in --version) echo "asusctl 6.3.8";; "profile get") echo Balanced;; *) exit 94;; esac\n',
'notify-send': '#!/bin/bash\necho forbidden-notification > "$HOME/NOTIFIED"\nexit 95\n',
'zsh': '#!/bin/bash\necho "zsh 5.9"\n',
}
for name, text in mocks.items():
    path = bin_dir / name
    text = text.replace('#!/bin/bash\n', '#!/bin/bash\n[[ "${DOCTOR_CASE:-}" == slow ]] && sleep 10\n', 1)
    path.write_text(text)
    path.chmod(0o755)
# Istniejące duże diagnostyki mają atrapy z jawnymi danymi prywatnymi.
for name in ['hypr/workspace-diag.sh', 'hypr/gaming-diag.sh']:
    path = repo / 'scripts' / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('#!/bin/bash\nprintf "%s\\n" "$DOCTOR_SECRETS"\n')
secrets = [str(home), 'fixture-user-private', socket.gethostname(),
           'SERIAL-EDID-PRIVATE-123', '192.0.2.81', 'aa:bb:cc:dd:ee:ff',
           '2001:db8::1234', 'token=PRIVATE-CREDENTIAL-123', 'ARBITRARY_OPAQUE_SECRET']
env = {**os.environ, 'PATH': str(bin_dir) + ':' + os.environ['PATH'],
       'USER': 'fixture-user-private', 'LOGNAME': 'fixture-user-private',
       'DOCTOR_SECRETS': ' '.join(secrets)}

def snapshot():
    return {str(p): ('link', os.readlink(p)) if p.is_symlink() else
            ('file', hashlib.sha256(p.read_bytes()).hexdigest())
            for p in root.rglob('*') if p.is_file() or p.is_symlink()}

def check(case='', full=False, running=True, expected=0, entry=False):
    before = snapshot()
    current_env = {**env, 'DOCTOR_CASE': case}
    if running:
        current_env['HYPRLAND_INSTANCE_SIGNATURE'] = 'fixture'
    else:
        current_env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
    cmd = ['bash', str(repo / ('scripts/appbinds/appbinds.sh' if entry else 'scripts/archenemy-doctor.sh'))]
    if entry:
        cmd.append('doctor')
    if full:
        cmd.append('--full')
    start = time.monotonic()
    result = subprocess.run(cmd, env=current_env, capture_output=True, text=True, timeout=5)
    assert time.monotonic() - start < 5, 'deadline exceeded'
    assert result.returncode == expected, (case, result.returncode, result.stdout, result.stderr)
    assert not result.stderr, result.stderr
    assert snapshot() == before, 'diagnostics wrote to the isolated tree'
    assert result.stdout.rstrip().endswith('problems found'), result.stdout
    for secret in secrets:
        assert secret not in result.stdout, ('privacy leak', secret, result.stdout)
    print('  ✓ ' + (case or 'healthy') + (' full' if full else '') + (' no Hyprland' if not running else ''))
    return result.stdout

assert 'not running' in check(running=False)
assert 'loaded' in check(entry=True)
assert '2 commits (cached; no fetch)' in check()
assert 'contents withheld' in check('errors', full=True, expected=1)
assert 'required package: waybar' in check('packages', expected=1)
assert 'not loaded' in check('wrong-bind', expected=1)
assert 'Lua target not exposed' in check('lua')
assert 'not running' in check('hung')
check(full=True, running=False)
check('slow', full=True, expected=1)
env['DOCTOR_BRANCH'] = 'fix/SERIAL-EDID-PRIVATE-123'
assert 'Branch: [custom branch withheld]' in check('branch-privacy')
env.pop('DOCTOR_BRANCH')
# Kontrolowana ścieżka bez pacmana, niezależnie od pakietów hosta.
(bin_dir / 'python').symlink_to(sys.executable)
(bin_dir / 'bash').symlink_to(shutil.which('bash'))
(bin_dir / 'pacman').rename(bin_dir / 'pacman.disabled')
old_path = env['PATH']
env['PATH'] = str(bin_dir)
assert 'pacman not available' in check('no-pacman', running=False)
env['PATH'] = old_path
(bin_dir / 'pacman.disabled').rename(bin_dir / 'pacman')
(home / '.config/hypr').unlink()
(home / '.config/hypr').symlink_to(repo / 'rices/missing/hypr')
assert 'wrong rice link: hypr' in check('broken-link', expected=1)
(home / '.config/hypr').unlink()
(home / '.config/hypr').symlink_to(repo / 'rices/white-blue/hypr')
assert 'machine-layer-check: OK' in check()
# Prawdziwy helper w trybie --doctor nie może wysyłać powiadomień.
(repo / 'config/hypr/gpu-env.lua').unlink()
assert 'machine-layer-check: problems; rerun install.sh' in check('machine-layer', full=True, expected=1)
(repo / 'config/hypr/gpu-env.lua').touch()
assert 'machine-layer-check: OK' in check()
background = repo / 'config/hypr/hyprlock-background-white-blue.conf'
background.unlink()
out = check('missing-lock-background', expected=1)
assert 'machine-layer-check: problems; rerun install.sh' in out
assert 'required hyprlock background missing' in out
background.touch()
assert '0 problems found' in check()
# Beta współdzieli tło white-blue, tron ma własne; opcjonalne pliki pozostają nieobecne.
for active, missing in [('white-blue_beta', False), ('tron', True)]:
    (repo / '.current_rice').write_text(active + '\n')
    result = subprocess.run(['bash', str(repo / 'scripts/hypr/machine-layer-check.sh'), '--doctor'],
                            env=env, capture_output=True, text=True, timeout=2)
    assert result.returncode == int(missing), (active, result)
    assert not result.stdout and not result.stderr
(repo / '.current_rice').write_text('white-blue\n')
assert not (home / 'NOTIFIED').exists()
# Nie-UTF-8 i FIFO nie przerywają raportu ani nie blokują open().
rc = home / '.bashrc'
rc.write_bytes(b'\xff\n# >>> archenemy shell >>>\n# <<< archenemy shell <<<\n')
assert 'bash managed rc block: present' in check('non-utf8')
rc.unlink()
os.mkfifo(rc)
assert 'bash managed rc block: missing or incomplete' in check('fifo', full=True)
rc.unlink()
rc.write_text('')
rc.write_bytes(b'x' * (1024 * 1024 + 1))
assert 'bash managed rc block: missing or incomplete' in check('oversized-rc')
rc.write_text('')

# Rzeczywisty helper; wartownik poza repo i snapshot całego HOME.
payload = home / 'payload'
payload.mkdir()
sentinel = home / 'DOCTOR_MUTATION'
conf = payload / 'flux-wall.conf'
conf.write_text('printf mutated > "$HOME/DOCTOR_MUTATION"\n')
(repo / '.current_rice').write_text('../../payload\n')
assert 'flux-wall doctor: reported unavailable components' in check('traversal', full=True, expected=1)
assert not sentinel.exists()
(repo / '.current_rice').write_text('white-blue\n')
local_conf = repo / 'rices/white-blue/flux-wall.conf'
local_conf.symlink_to(conf)
assert 'flux-wall doctor: reported unavailable components' in check('external-conf-link', full=True)
assert not sentinel.exists()
local_conf.unlink()
os.mkfifo(local_conf)
assert 'flux-wall doctor: reported unavailable components' in check('fifo-rice-conf', full=True)
local_conf.unlink()
local_conf.write_text(conf.read_text())
assert 'flux-wall doctor: completed' in check('local-conf-not-executed', full=True)
assert not sentinel.exists()
# Cel samego katalogu rice także nie może wyjść poza repo.
(repo / 'rices/escape').symlink_to(payload, target_is_directory=True)
(repo / '.current_rice').write_text('escape\n')
assert 'flux-wall doctor: reported unavailable components' in check('external-rice-link', full=True, expected=1)
assert not sentinel.exists()
(repo / 'rices/escape').unlink()
(repo / '.current_rice').write_text('white-blue\n')

# Prywatne segmenty ścieżki checkoutu są ukryte również poza ~/archenemy.
private_repo = home / 'SERIAL-EDID-PRIVATE-123' / 'checkout'
shutil.copytree(repo, private_repo, symlinks=True)
result = subprocess.run(['bash', str(private_repo / 'scripts/archenemy-doctor.sh')],
                        env=env, capture_output=True, text=True, timeout=5)
assert not result.stderr and 'Path: [checkout path withheld]' in result.stdout
assert 'SERIAL-EDID-PRIVATE-123' not in result.stdout
print('Doctor: all isolated checks passed')
PY
