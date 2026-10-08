#!/usr/bin/env python3
"""Hook PreToolUse(Bash): freno contra push/merge y lectura de secretos ACCIDENTALES.

No es una frontera de seguridad: eval, alias o un intérprete (python -c os.system)
lo evaden. Cubre las formas habituales que un agente usa sin querer.
Probado: `Bash(git push:*)` en permissions solo compara prefijo y `git -C . push`
lo evadía; `python3 -c "open('.env')"` evadía `Read(.env*)`.

Bloquea (exit 2):
  - git [opts globales] push|merge   (salvo --help/-h)
  - gh [opts] pr merge  /  gh api .../merge
  - argumentos que son rutas a secretos: .env*, *.pem, *.key, *.p12, *.pfx,
    id_rsa/id_ed25519/id_ecdsa (sin .pub), credentials[.json|.yml|...], .netrc
    Plantillas permitidas: .env.example/.sample/.template/.dist
No mira el texto de mensajes (-m "...") ni de echo/printf.
Errores internos -> exit 0 (nunca rompe la sesión).
"""
import json
import os
import re
import shlex
import sys

SEPARATORS = re.compile(r"&&|\|\||[;|&\n`(){}]|\$\(")
KEYWORDS = {"if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "!", "case", "esac", "in"}
WRAPPERS = {"sudo": {"-u", "-g", "-C", "-D", "-h", "-p", "-r", "-t", "-U"},
            "env": {"-u", "-C", "-S"}, "command": set(), "exec": {"-a"}, "nohup": set(),
            "time": {"-f", "-o"}, "nice": {"-n"}, "ionice": {"-c", "-n"},
            "timeout": {"-s", "-k", "--signal", "--kill-after"}, "xargs": {"-I", "-n", "-P", "-d", "-L", "-E"},
            "stdbuf": {"-i", "-o", "-e"}}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "fish", "busybox"}
GIT_OPTS_WITH_ARG = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}
TEXT_CMDS = {"echo", "printf"}
MSG_FLAGS = {"-m", "--message", "--body", "-b", "--title", "-t", "-F"}

SECRET_NAME = re.compile(
    r"^(\.env(?!.*(example|sample|template|dist))(\.[\w.-]+)?"
    r"|.+\.(pem|key|p12|pfx)"
    r"|id_(rsa|ed25519|ecdsa|dsa)"
    r"|credentials\.(json|ya?ml|ini|toml|txt|csv)"
    r"|\.netrc)$", re.IGNORECASE)


PROTECTED = re.compile(r"^(origin/)?(uat|prod|production|release/prod[\w./-]*)$", re.IGNORECASE)
WRITE_SUBS = {"commit", "reset", "rebase", "cherry-pick", "revert", "am", "pull", "stash", "restore", "rm", "mv"}
CWD = [None]


def current_branch(t, cwd):
    """Rama actual del repo donde corre el comando (respeta git -C)."""
    import subprocess
    d = cwd
    for i, a in enumerate(t[:-1]):
        if a == "-C":
            d = os.path.join(cwd or ".", t[i + 1])
    try:
        r = subprocess.run(["git", "-C", d or ".", "symbolic-ref", "--short", "-q", "HEAD"],
                           capture_output=True, text=True, timeout=3)
        return r.stdout.strip()
    except Exception:
        return ""


def strip_wrappers(t):
    while t:
        head = t[0].rsplit("/", 1)[-1]
        if re.match(r"^\w+=", t[0]) or head in KEYWORDS:
            t = t[1:]
        elif head in WRAPPERS:
            t, opts = t[1:], WRAPPERS[head]
            while t and t[0].startswith("-"):
                t = t[2:] if t[0] in opts else t[1:]
            if head == "timeout" and t and re.match(r"^[\d.]+[smhd]?$", t[0]):
                t = t[1:]
            if head == "env":
                while t and re.match(r"^\w+=", t[0]):
                    t = t[1:]
        else:
            return t
    return t


def git_sub(t):
    i = 1
    while i < len(t):
        if t[i] in GIT_OPTS_WITH_ARG:
            i += 2
        elif t[i].startswith("-"):
            i += 1
        else:
            return t[i], t[i + 1:]
    return None, []


def secret_args(t):
    if not t or t[0].rsplit("/", 1)[-1] in TEXT_CMDS:
        return None
    skip = False
    for a in t[1:]:
        if skip:
            skip = False
            continue
        if a in MSG_FLAGS:
            skip = True
            continue
        for piece in re.split(r"[=:,'\"()\s]", a):
            if piece.endswith("/"):
                continue
            name = piece.rsplit("/", 1)[-1]
            if name and (SECRET_NAME.match(name) or (name.lower() == "credentials" and "/" in piece)):
                return name
    return None


def check(cmd, depth=0):
    if depth > 3:
        return None
    try:
        lex = shlex.shlex(cmd, posix=True, punctuation_chars=";&|()<>{}")
        lex.whitespace_split = True
        lex.commenters = ""
        raw = list(lex)
    except ValueError:
        raw = cmd.split()
    parts, cur = [], []
    for tok in raw:
        if tok and all(c in ";&|()<>{}" for c in tok):
            if cur:
                parts.append(cur)
            cur = []
        else:
            cur.append(tok)
    if cur:
        parts.append(cur)
    for p in parts:
        t = strip_wrappers(p)
        if not t:
            continue
        exe = t[0].rsplit("/", 1)[-1]
        if exe in SHELLS:
            for i, a in enumerate(t[1:], 1):
                if re.match(r"^-\w*c\w*$", a) and i + 1 < len(t):
                    hit = check(t[i + 1], depth + 1)
                    if hit:
                        return hit
        if exe == "git":
            sub, rest = git_sub(t)
            if {"--help", "-h"} & set(rest):
                continue
            if sub in {"push", "merge"}:
                return f"git {sub}"
            # Regla 3: ramas protegidas (UAT/PROD) solo monitoreo.
            if sub in {"branch", "checkout", "switch"} and any(PROTECTED.match(a) for a in rest) \
                    and {"-D", "-d", "-f", "--force", "-B", "-C", "-M", "-m"} & set(rest):
                return f"git {sub} sobre rama protegida"
            if sub in WRITE_SUBS and PROTECTED.match(current_branch(t, CWD[0])):
                return f"git {sub} en rama protegida '{current_branch(t, CWD[0])}'"
        if exe == "gh":
            args, skip = [], False
            for a in t[1:]:
                if skip:
                    skip = False
                elif a in {"-R", "--repo", "-X", "--method", "-H", "--header", "-f", "-F"}:
                    skip = True
                elif not a.startswith("-"):
                    args.append(a)
            if args[:2] == ["pr", "merge"] or (args[:1] == ["api"] and any(a.rstrip("/").endswith("/merge") for a in args)):
                return "gh pr merge"
        s = secret_args(t)
        if s:
            return f"lectura de secreto '{s}'"
    return None


def main():
    data = json.load(sys.stdin)
    if data.get("tool_name") != "Bash":
        return 0
    CWD[0] = data.get("cwd")
    hit = check((data.get("tool_input") or {}).get("command", ""))
    if not hit:
        return 0
    sys.stderr.write(f"guard-bash: bloqueado ({hit}). Reglas duras 2/5 de CLAUDE.md: "
                     "pide confirmación al usuario; si procede, que lo ejecute él.\n")
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
