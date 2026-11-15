#!/bin/bash
# =============================================
#   archenemy - tests/secrets.sh
#   Sekrety w publicznym repo (K14 z audytu bezpieczeństwa 2026-11-14):
#     1. zawsze: wzorce o wysokiej pewności (nagłówek klucza prywatnego,
#        także PGP „PRIVATE KEY BLOCK”, tokeny GitHuba, klucz AWS, token
#        Slacka) w plikach śledzonych — `git grep`, bez sieci i bez
#        dodatkowych narzędzi;
#     2. gitleaks (za `command -v`) na CAŁEJ historii gita — brak narzędzia
#        = „skip”, nigdy ✓.
#   Autotest: repo w mktemp z fałszywym kluczem musi dać ✗ (fałszywy klucz
#   składany w czasie biegu — ten plik sam nie zawiera wzorca).
#   Uruchom: bash tests/secrets.sh   (kod 0 = brak znalezisk; skip ≠ ✓)
# =============================================

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
skip() { SKIP=$((SKIP + 1)); echo "  ? skip: $1"; }

PATTERNS=(
    -e '-----BEGIN ([A-Z]+ )?PRIVATE KEY( BLOCK)?-----'   # BLOCK: pancerny klucz PGP
    -e 'gh[pousr]_[A-Za-z0-9]{36}'
    -e 'github_pat_[A-Za-z0-9_]{60,}'
    -e 'AKIA[0-9A-Z]{16}'
    -e 'xox[abprs]-[A-Za-z0-9-]{10,}'
)
# tracked_secrets <repo> — linie plik:nr z dopasowaniem (bez treści sekretu).
tracked_secrets() { git -C "$1" grep -nIE -l "${PATTERNS[@]}" 2>/dev/null; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid

echo "== autotest: repo z fałszywym kluczem"
F="$T/fake"; git init -q "$F"
printf '%s\n' "-----BEGIN ""OPENSSH PRIVATE KEY-----" "b3BlbnNzaC1rZXktdjEAAAAA" "-----END ""OPENSSH PRIVATE KEY-----" > "$F/id_test"
printf 'token=%s%s\n' "ghp_" "abcdefghijklmnopqrstuvwxyz0123456789" > "$F/conf"
# Pancerny klucz PGP ma w nagłówku „BLOCK” (R1 C4); publiczny nie jest sekretem.
printf '%s\n' "-----BEGIN ""PGP PRIVATE KEY BLOCK-----" "TESTnotakey" "-----END ""PGP PRIVATE KEY BLOCK-----" > "$F/key_test.asc"
printf '%s\n' "-----BEGIN ""PGP PUBLIC KEY BLOCK-----" "TESTnotakey" "-----END ""PGP PUBLIC KEY BLOCK-----" > "$F/pub_test.asc"
git -C "$F" add -A; git -C "$F" commit -qm fake
found="$(tracked_secrets "$F")"
if [[ "$found" == *id_test* && "$found" == *conf* ]]; then ok "wzorce łapią klucz prywatny i token GitHuba"; else fail "wzorce przepuszczają fałszywy klucz/token"; fi
if [[ "$found" == *key_test.asc* ]]; then ok "wzorce łapią prywatny klucz PGP (PRIVATE KEY BLOCK)"; else fail "wzorce przepuszczają prywatny klucz PGP (PRIVATE KEY BLOCK)"; fi
if [[ "$found" != *pub_test.asc* ]]; then ok "publiczny klucz PGP nie jest zgłaszany"; else fail "publiczny klucz PGP zgłoszony jako sekret"; fi

echo "== pliki śledzone archenemy"
found="$(tracked_secrets "$REPO")"
if [[ -z "$found" ]]; then ok "brak kluczy prywatnych i tokenów w plikach śledzonych"
else while IFS= read -r f; do fail "możliwy sekret w $f (treść celowo niewypisana)"; done <<< "$found"
fi

echo "== gitleaks (cała historia)"
if ! command -v gitleaks >/dev/null 2>&1; then
    skip "gitleaks is not installed (sudo pacman -S gitleaks) — history not scanned"
else
    # `gitleaks git` (v8.19+) skanuje historię; starsze wersje mają `detect`.
    gl() { if gitleaks git --help >/dev/null 2>&1; then gitleaks git --no-banner --redact "$@"; else gitleaks detect --no-banner --redact --source "$@"; fi; }
    if gl "$F" >/dev/null 2>&1; then fail "gitleaks nie znalazł fałszywego klucza (autotest)"; else ok "gitleaks łapie fałszywy klucz (autotest)"; fi
    if out="$(gl "$REPO" 2>&1)"; then ok "gitleaks: historia bez sekretów"
    else fail "gitleaks zgłasza znaleziska (wynik zredagowany):"; sed 's/^/      /' <<< "$out" | tail -n 20
    fi
fi

echo ""
echo "Result: $PASS passed / $FAIL failed / $SKIP skipped"
((FAIL == 0))
