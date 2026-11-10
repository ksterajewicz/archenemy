#!/bin/bash
# =============================================
#   archenemy - tests/rofi-inputbar.sh
#   Statyczna kontrola metryk paska wejścia we wszystkich motywach.
#   Bez rofi i serwera obrazu; nie zastępuje oceny na żywo.
# =============================================

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$REPO" <<'PY'
from pathlib import Path
import re
import sys

repo = Path(sys.argv[1])
passed = failed = 0
for path in sorted((repo / 'rices').glob('*/rofi/themes/*.rasi')):
    text = re.sub(r'/\*.*?\*/|//[^\n]*', '', path.read_text(), flags=re.S)
    blocks = {}
    for selector, body in re.findall(r'([^{}]+)\{([^{}]*)\}', text):
        for name in selector.split(','):
            props = blocks.setdefault(name.strip(), {})
            props.update((key.strip(), value.strip())
                         for key, value in re.findall(r'([\w-]+)\s*:\s*([^;]+);', body))
    errors = []
    widgets = [blocks.get(name, {}) for name in ('prompt', 'entry')]
    fonts = [props.get('font', blocks.get('*', {}).get('font')) for props in widgets]
    if not fonts[0] or fonts[0] != fonts[1]:
        errors.append(f'different fonts: {fonts}')
    if any(props.get('vertical-align') != '0.5' for props in widgets):
        errors.append('prompt/entry must both have vertical-align: 0.5')
    for key in ('padding', 'margin'):
        values = [props.get(key, blocks.get('*', {}).get(key, '0px')) for props in widgets]
        if values[0] != values[1]:
            errors.append(f'different {key}: {values}')
    bar = blocks.get('inputbar', {})
    children = re.sub(r'\s+', '', bar.get('children', ''))
    expected = '[entry]' if path.parts[-4] == 'white-blue_beta' else '[prompt,entry]'
    if children != expected or 'spacing' not in bar:
        errors.append('unexpected inputbar children or missing spacing')
    if errors:
        failed += 1
        print(f'  ✗ {path.relative_to(repo)}: {"; ".join(errors)}')
    else:
        passed += 1
        print(f'  ✓ {path.relative_to(repo)}')
if not passed and not failed:
    failed += 1
    print('  ✗ no themes found')
print(f'Wynik: {passed} ✓ / {failed} ✗')
sys.exit(bool(failed))
PY
