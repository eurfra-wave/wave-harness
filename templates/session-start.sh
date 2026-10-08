#!/bin/bash
# Hook SessionStart para repos de WAVE: instala el arnés global en cada sesión de nube.
# Copiar a <repo>/.claude/hooks/session-start.sh y registrar con templates/repo-settings.json.
# Configurar UNA vez: WAVE_HARNESS_REPO (URL git del arnés) y WAVE_HARNESS_REF (tag o commit).
set -euo pipefail

[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0          # solo en la nube

REPO="${WAVE_HARNESS_REPO:-}"
REF="${WAVE_HARNESS_REF:-main}"
MARK="$HOME/.claude/.harness-ref"
LOG="$HOME/.claude/harness-setup.log"

if [ -z "$REPO" ]; then
  echo "arnés: WAVE_HARNESS_REPO no definido; no se instaló (ver LEEME.md)."
  exit 0
fi
if [ -f "$MARK" ] && [ "$(cat "$MARK")" = "$REPO@$REF" ]; then
  exit 0                                                   # ya instalado (contenedor cacheado)
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git clone -q "$REPO" "$TMP/h" && git -C "$TMP/h" checkout -q "$REF"
if bash "$TMP/h/setup.sh" >"$LOG" 2>&1; then
  echo "$REPO@$REF" > "$MARK"
  echo "arnés WAVE $REF instalado (detalle: $LOG)."
else
  echo "arnés WAVE: setup falló, se restauró el respaldo. Revisa $LOG." >&2
fi
exit 0                                                     # nunca bloquea el arranque
