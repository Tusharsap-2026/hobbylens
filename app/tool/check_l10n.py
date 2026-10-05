"""Static checks for the bilingual UI, run in CI before `flutter analyze`.

1. Bangla and English ARB files have exactly the same keys and placeholders.
2. Every `l10n.someKey` used in lib/ exists, and is called with the right number of arguments.
3. No user-visible text is hard-coded in widgets (Text('...'), labelText: '...', and so on).
Exit code 1 on any problem.
"""
import json, os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
problems = []

def load(name):
    with open(os.path.join(ROOT, "lib", "l10n", name), encoding="utf-8") as f:
        return json.load(f)

en, bn = load("app_en.arb"), load("app_bn.arb")
keys_en = {k for k in en if not k.startswith("@")}
keys_bn = {k for k in bn if not k.startswith("@")}
for k in sorted(keys_en ^ keys_bn):
    problems.append(f"ARB key only in one language: {k}")

def placeholders_in(message):
    # Top-level {name} or {name, plural, ...}; nested {name} inside plural branches too.
    return set(re.findall(r"\{(\w+)(?:\}|,)", message))

def balanced(message):
    depth = 0
    for ch in message:
        depth += ch == "{"
        depth -= ch == "}"
        if depth < 0:
            return False
    return depth == 0

declared = {}
for k in keys_en:
    meta = en.get("@" + k, {}).get("placeholders", {})
    declared[k] = set(meta)
    for lang, data in (("en", en), ("bn", bn)):
        msg = data.get(k, "")
        if not balanced(msg):
            problems.append(f"{lang}:{k} has unbalanced braces")
        used = placeholders_in(msg) - {"other", "one", "few", "many", "two", "zero"}
        if used != declared[k]:
            problems.append(f"{lang}:{k} uses {sorted(used)} but declares {sorted(declared[k])}")

# Dart sources ------------------------------------------------------------------
dart_files = []
for d, _, files in os.walk(os.path.join(ROOT, "lib")):
    for f in files:
        if f.endswith(".dart") and not f.startswith("app_localizations"):
            dart_files.append(os.path.join(d, f))

used_keys = set()
call_re = re.compile(r"\bl10n\.(\w+)(\()?")
for path in dart_files:
    src = open(path, encoding="utf-8").read()
    rel = os.path.relpath(path, ROOT)
    for m in call_re.finditer(src):
        key, called = m.group(1), m.group(2)
        used_keys.add(key)
        if key not in keys_en:
            problems.append(f"{rel}: unknown string l10n.{key}")
            continue
        n = len(declared[key])
        if n and not called:
            problems.append(f"{rel}: l10n.{key} needs {n} argument(s)")
        if called and n == 0:
            problems.append(f"{rel}: l10n.{key} takes no arguments")
        if called and n:
            # Count top-level commas in the argument list.
            i, depth, args, quote = m.end(), 1, 1, None
            while i < len(src) and depth:
                c = src[i]
                if quote:
                    if c == "\\":
                        i += 2
                        continue
                    if c == quote:
                        quote = None
                    i += 1
                    continue
                if c in "'\"":
                    quote = c
                elif c in "([{":
                    depth += 1
                elif c in ")]}":
                    depth -= 1
                elif c == "," and depth == 1:
                    args += 1
                i += 1
            inner = src[m.end():i - 1].strip()
            if inner.endswith(","):
                args -= 1
            if inner == "":
                args = 0
            if args != n:
                problems.append(f"{rel}: l10n.{key} called with {args} argument(s), expects {n}")

    # Hard-coded text: a string literal with two or more letters in a user-facing position.
    for m in re.finditer(r"""(Text\(|labelText:\s*|hintText:\s*|tooltip:\s*|label:\s*Text\(|title:\s*Text\(|message:\s*)(['"])(.*?)\2""", src):
        literal = m.group(3)
        line = src.count("\n", 0, m.start()) + 1
        if "l10n-ok" in src.splitlines()[line - 1]:
            continue
        # Interpolations are computed values, not text: drop them before looking for words.
        text = re.sub(r"\$\{[^}]*\}|\$\w+|\\[nt]", "", literal)
        if re.search(r"[A-Za-zঀ-৿]{2,}", text):
            problems.append(f"{rel}:{line}: hard-coded text {literal!r}")

for k in sorted(keys_en - used_keys):
    print(f"note: string not used yet: {k}")

if problems:
    print("\n".join(problems))
    sys.exit(1)
print(f"l10n OK: {len(keys_en)} strings in Bangla and English, {len(used_keys)} used in {len(dart_files)} files")
