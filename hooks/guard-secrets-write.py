#!/usr/bin/env python3
"""Hook PreToolUse(Edit|Write|MultiEdit|NotebookEdit): impide escribir secretos en archivos.

Detecta formatos de credenciales públicamente documentados (prefijos fijos de
cada proveedor) en el contenido que Claude va a escribir. Exit 2 = bloqueo.
Valores de ejemplo evidentes (EXAMPLE, xxxx, <...>, ${VAR}) no bloquean.
Errores internos -> exit 0.
"""
import json
import re
import sys

PATTERNS = {
    "AWS access key": r"\b(AKIA|ASIA)[0-9A-Z]{16}\b",
    "GitHub token": r"\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36}\b|\bgithub_pat_[A-Za-z0-9_]{60,}\b",
    "Anthropic API key": r"\bsk-ant-[A-Za-z0-9_-]{30,}",
    "OpenAI API key": r"\bsk-(proj-)?[A-Za-z0-9]{32,}\b",
    "Google API key": r"\bAIza[0-9A-Za-z_-]{35}\b",
    "Slack token": r"\bxox[baprs]-[A-Za-z0-9-]{10,}\b",
    "Stripe live key": r"\b(sk|rk)_live_[A-Za-z0-9]{20,}\b",
    "Clave privada": r"-----BEGIN (RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----",
}
PLACEHOLDER = re.compile(r"EXAMPLE|x{6,}|X{6,}|<[^>]+>|\$\{[^}]+\}|0{12,}", re.IGNORECASE)


def texts(tool_input):
    for k in ("content", "new_string", "new_source"):
        if isinstance(tool_input.get(k), str):
            yield tool_input[k]
    for e in tool_input.get("edits") or []:
        if isinstance(e, dict) and isinstance(e.get("new_string"), str):
            yield e["new_string"]


def main():
    data = json.load(sys.stdin)
    if data.get("tool_name") not in {"Edit", "Write", "MultiEdit", "NotebookEdit"}:
        return 0
    for text in texts(data.get("tool_input") or {}):
        for name, pat in PATTERNS.items():
            for m in re.finditer(pat, text):
                line = text[max(0, text.rfind("\n", 0, m.start())):text.find("\n", m.end()) % (len(text) + 1)]
                if PLACEHOLDER.search(m.group(0)) or PLACEHOLDER.search(line):
                    continue
                sys.stderr.write(
                    f"guard-secrets-write: el contenido incluye un posible {name}. "
                    "No escribas secretos en archivos: usa una variable de entorno (${NOMBRE}) "
                    "y pide al usuario que la defina.\n")
                return 2
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
