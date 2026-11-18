#!/usr/bin/env python3
# =============================================
#   archenemy - tests/lib/nix_packages.py
#   Tekstowy parser i strażnik nix/packages.nix BEZ nix (D10): ewaluacja
#   `nix-instantiate --parse/--eval` przychodzi dopiero w D11/D12.
#   Rozumie tylko kształt, który pisze nix/generate-packages.sh:
#     { pkgs }: { core = [ pkgs.a … ]; fonts = [ … ]; build = [ … ];
#                 optional = { "a" = pkgs.a; … }; }
#   Sprawdza: zbalansowane nawiasy/cudzysłowy (tokeny poza komentarzami),
#   dokładnie ten kształt, tylko atrybuty pkgs.* (żadnych opcji
#   programs./services./hardware./networking./boot./virtualisation./…,
#   żadnego „-”), brak duplikatów, pokrycie listy oczekiwanych atrybutów
#   (--expect, plik: jeden atrybut na linię) i zgodność z mapą
#   (--map: wszystkie nixos=ok z packages/platform-map.tsv + --extra).
#   Wyjście: wiersze „ok <opis>” / „fail <opis>”; kod 0 = brak fail.
#   Uruchom: python3 tests/lib/nix_packages.py <packages.nix> [--expect F] [--map F] [--extra a,b]
# =============================================
import re
import sys

OPTION_PREFIXES = ("programs.", "services.", "hardware.", "networking.", "boot.",
                   "virtualisation.", "systemd.", "security.", "users.", "fonts.",
                   "xdg.", "i18n.", "environment.", "nix.", "nixpkgs.", "home.", "wayland.")
ATTR = re.compile(r"^[A-Za-z_][A-Za-z0-9_'-]*(\.[A-Za-z_][A-Za-z0-9_'-]*)*$")
GROUPS = ("core", "fonts", "build", "optional")

results = []


def ok(msg):
    results.append("ok " + msg)


def fail(msg):
    results.append("fail " + msg)


def tokenize(text):
    """Tokeny: ident (z kropkami/myślnikami), string, interpunkcja. Komentarze # i /* */ pomijane."""
    toks = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c in " \t\r\n":
            i += 1
        elif c == "#":
            while i < n and text[i] != "\n":
                i += 1
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            if j < 0:
                raise ValueError("unterminated /* comment")
            i = j + 2
        elif c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                if text[j] == "\\":
                    j += 1
                elif text.startswith("${", j):
                    raise ValueError("interpolation in string at %d" % j)
                j += 1
            if j >= n:
                raise ValueError("unterminated string")
            toks.append(("str", text[i + 1:j]))
            i = j + 1
        elif c in "{}[]=;:,":
            toks.append(("p", c))
            i += 1
        else:
            m = re.match(r"[A-Za-z0-9_'.\-]+", text[i:])
            if not m:
                raise ValueError("unexpected character %r at %d" % (c, i))
            toks.append(("id", m.group(0)))
            i += len(m.group(0))
    return toks


def balanced(toks):
    pairs = {"}": "{", "]": "["}
    stack = []
    for kind, v in toks:
        if kind != "p":
            continue
        if v in "{[":
            stack.append(v)
        elif v in "}]":
            if not stack or stack.pop() != pairs[v]:
                return False
    return not stack


class Parser:
    def __init__(self, toks):
        self.t = toks
        self.i = 0

    def peek(self):
        return self.t[self.i] if self.i < len(self.t) else (None, None)

    def eat(self, kind, val=None):
        k, v = self.peek()
        if k != kind or (val is not None and v != val):
            raise ValueError("expected %s %r, got %s %r (token %d)" % (kind, val, k, v, self.i))
        self.i += 1
        return v

    def pkg(self):
        v = self.eat("id")
        if not v.startswith("pkgs."):
            raise ValueError("list element is not pkgs.<attr>: %r" % v)
        return v[len("pkgs."):]

    def parse(self):
        self.eat("p", "{"); self.eat("id", "pkgs"); self.eat("p", "}"); self.eat("p", ":")
        self.eat("p", "{")
        groups = {}
        while self.peek() != ("p", "}"):
            name = self.eat("id")
            if name in groups:
                raise ValueError("group %s defined twice" % name)
            self.eat("p", "=")
            if name == "optional":
                self.eat("p", "{")
                items = []
                while self.peek() != ("p", "}"):
                    key = self.eat("str")
                    self.eat("p", "=")
                    items.append((key, self.pkg()))
                    self.eat("p", ";")
                self.eat("p", "}")
            else:
                self.eat("p", "[")
                items = []
                while self.peek() != ("p", "]"):
                    items.append(self.pkg())
                self.eat("p", "]")
            self.eat("p", ";")
            groups[name] = items
        self.eat("p", "}")
        if self.i != len(self.t):
            raise ValueError("trailing tokens after the attribute set")
        return groups


def map_attrs(path):
    attrs = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            cols = line.split("\t")
            if len(cols) != 10:
                raise ValueError("map row with %d columns: %s" % (len(cols), cols[0]))
            status = cols[8].split(";")
            if "nixos=ok" in status:
                attrs.extend(cols[5].split())
    return attrs


def main(argv):
    path = argv[1]
    opts = {}
    k = 2
    while k < len(argv):
        opts[argv[k]] = argv[k + 1]
        k += 2
    try:
        text = open(path, encoding="utf-8").read()
    except OSError as e:
        fail("cannot read %s: %s" % (path, e))
        return finish()
    try:
        toks = tokenize(text)
    except ValueError as e:
        fail("syntax (tokens): %s" % e)
        return finish()
    if balanced(toks):
        ok("balanced brackets and braces")
    else:
        fail("unbalanced brackets/braces")
        return finish()
    try:
        groups = Parser(toks).parse()
    except ValueError as e:
        fail("shape { pkgs }: { core/fonts/build/optional }: %s" % e)
        return finish()
    ok("shape { pkgs }: { core = [..]; fonts = [..]; build = [..]; optional = { .. }; }")
    if tuple(sorted(groups)) == tuple(sorted(GROUPS)):
        ok("exactly the groups core, fonts, build, optional")
    else:
        fail("groups %s, expected %s" % (sorted(groups), list(GROUPS)))
    every = []
    for g in GROUPS:
        for item in groups.get(g, []):
            if g == "optional":
                key, attr = item
                if key != attr:
                    fail("optional key %r differs from pkgs.%s" % (key, attr))
            else:
                attr = item
            every.append(attr)
    bad = [a for a in every if not ATTR.match(a) or a == "-"]
    opt = [a for a in every if a.startswith(OPTION_PREFIXES)]
    if bad:
        fail("not package attributes: %s" % bad)
    else:
        ok("%d entries, all pkgs.<attribute>" % len(every))
    if opt:
        fail("NixOS/home-manager options in the package list: %s" % opt)
    else:
        ok("no programs./services./hardware./networking./boot./virtualisation. options")
    dups = sorted({a for a in every if every.count(a) > 1})
    if dups:
        fail("duplicates: %s" % dups)
    else:
        ok("no duplicates")
    have = set(every)
    if "--expect" in opts:
        want = [w for w in open(opts["--expect"], encoding="utf-8").read().split() if w]
        missing = [w for w in want if w not in have]
        if missing:
            fail("missing expected attributes: %s" % missing)
        else:
            ok("all %d expected attributes present" % len(want))
    if "--map" in opts:
        try:
            from_map = map_attrs(opts["--map"])
        except (OSError, ValueError) as e:
            fail("map: %s" % e)
            return finish()
        extra = [e for e in opts.get("--extra", "").split(",") if e]
        want = set(from_map) | set(extra)
        if have == want:
            ok("matches the map: %d nixos=ok attributes + extras %s" % (len(set(from_map)), extra))
        else:
            fail("differs from the map: not in map %s, missing %s"
                 % (sorted(have - want), sorted(want - have)))
    return finish()


def finish():
    for r in results:
        print(r)
    return 0 if results and not any(r.startswith("fail") for r in results) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
