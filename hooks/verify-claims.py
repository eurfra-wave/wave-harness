#!/usr/bin/env python3
"""Hook Stop: bloquea afirmaciones de éxito sin evidencia en el mismo turno.

Regla dura nº 4 de CLAUDE.md ("evidencia antes de aseverar éxito") convertida
en mecanismo determinista. Si la respuesta final afirma éxito ("tests pasan",
"listo", "funciona"...) y en este turno no se ejecutó ningún comando (Bash),
devuelve exit 2 para que Claude verifique antes de terminar.

- stop_hook_active=true -> deja terminar (evita bucles infinitos).
- Cualquier error interno -> exit 0 (nunca rompe la sesión).
"""
import json
import os
import re
import sys

CLAIM = re.compile(
    r"\b(tests?\s+(pasan|pasaron|est[aá]n\s+en\s+verde|en\s+verde|ok)|suite\s+pas[oó]|"
    r"todo\s+(pasa|funciona|ok|listo|bien|correcto)|ya\s+funciona|funciona\s+(correctamente|bien|perfecto)|"
    r"(est[aá]|qued[oó]|fue|se)\s+(listo|arreglad[oa]|resuelt[oa]|funcionando|corregid[oa]|solucionad[oa])|"
    r"se\s+(resolvi[oó]|corrigi[oó]|arregl[oó]|solucion[oó])|(bug|error|fallo|problema)\s+(arreglado|corregido|resuelto|solucionado)|"
    r"implementado\s+y\s+verificado|completado\s+con\s+[eé]xito|compila\s+sin\s+errores|sin\s+errores|"
    r"all\s+tests\s+pass|tests?\s+(are\s+)?pass(ed|ing)?|(it\s+)?works\s+now|everything\s+(works|is\s+working)|"
    r"is\s+(fixed|resolved)|i\s+fixed\s+it|all\s+green)\b",
    re.IGNORECASE,
)
# Reformulación honesta o condicional: no bloquear (el propio hook la pide).
HONEST = re.compile(
    r"\b(no\s+(lo\s+)?(verifiqu[eé]|ejecut[eé]|prob[eé]|comprob[eé]|pude\s+verificar)|sin\s+verificar|"
    r"no\s+(est[aá]\s+)?verificado|aún\s+no|todav[ií]a\s+no|si\s+(los\s+)?tests|para\s+saber\s+si|"
    r"not\s+(yet\s+)?verified|unverified|didn'?t\s+(run|test|verify)|if\s+(the\s+)?tests|revise\s+si|avísame\s+si|para\s+revisar)\b",
    re.IGNORECASE,
)
EVIDENCE_TOOLS = {"Bash", "mcp__remote-devices__device_bash"}


def main() -> int:
    data = json.load(sys.stdin)
    if data.get("stop_hook_active"):
        return 0
    path = data.get("transcript_path")
    entries = []
    with open(path or os.devnull, encoding="utf-8") as fh:
        for line in fh:
            try:
                entries.append(json.loads(line))
            except ValueError:
                continue

    # Inicio del turno = último mensaje del usuario con texto (no tool_result).
    start = 0
    for i, e in enumerate(entries):
        if e.get("type") != "user":
            continue
        content = (e.get("message") or {}).get("content")
        if isinstance(content, str) or (
            isinstance(content, list)
            and any(isinstance(c, dict) and c.get("type") == "text" for c in content)
        ):
            start = i

    used_evidence = False
    final_text = ""
    for e in entries[start + 1:]:
        if e.get("type") != "assistant":
            continue
        for c in (e.get("message") or {}).get("content") or []:
            if not isinstance(c, dict):
                continue
            if c.get("type") == "tool_use" and c.get("name") in EVIDENCE_TOOLS:
                used_evidence = True
            elif c.get("type") == "text":
                final_text = c.get("text", "")

    # Hecho verificado: en Stop el transcript aún no trae la respuesta final;
    # llega en el campo last_assistant_message.
    final_text = data.get("last_assistant_message") or final_text
    if used_evidence or not CLAIM.search(final_text) or HONEST.search(final_text):
        return 0

    sys.stderr.write(
        "verification-gate: afirmaste éxito sin ejecutar ninguna verificación en este turno. "
        "Ejecuta el comando que lo demuestra (tests, build, script) y muestra su salida, "
        "o reformula diciendo explícitamente que NO está verificado.\n"
    )
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
