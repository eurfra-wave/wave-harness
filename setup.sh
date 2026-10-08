#!/bin/bash
# setup.sh — Arnés Senior Cloudcode V3 (configuración GLOBAL en ~/.claude)
# Uso: bash setup.sh        Idempotente. Falla (exit ≠ 0) si algo falla.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
C="$HOME/.claude"
TS="$(date +%Y%m%d-%H%M%S)"

# Versiones fijadas (cadena de suministro reproducible)
ARENA_REPO="https://github.com/Jakeschincariol/arena-skill"; ARENA_SHA="df07b8e518e10cdecd8cd7712d9958b6f396250e"
AUDIT_SHA="585c2030cd590e991d84dae4d6614cd449f245b1"
GRAPHIFY_VER="0.9.80"; UV_VER="0.11.32"
PLUGINS=(superpowers code-review commit-commands context7 claude-code-setup playwright)
PAPERCLIP_MCP="@paperclipai/mcp-server@2026.1005.0"; STITCH_MCP="@_davideast/stitch-mcp@0.9.0"

paso(){ echo; echo "=== $* ==="; }
ok(){ echo "  ✓ $*"; }
die(){ echo "  ✗ $*" >&2; declare -F restaurar >/dev/null && restaurar; exit 1; }

paso "0. Requisitos"
for b in claude git python3 jq curl; do command -v "$b" >/dev/null || die "falta $b"; done
export PATH="$HOME/.local/bin:$PATH"
command -v uv >/dev/null || curl -LsSf "https://astral.sh/uv/$UV_VER/install.sh" | sh
ok "requisitos presentes"

restaurar(){ echo "  ↩ fallo: restaurando respaldo $TS" >&2; for f in settings.json CLAUDE.md; do [ -f "$C/backups/$TS/$f" ] && cp "$C/backups/$TS/$f" "$C/$f"; done; }
trap 'restaurar' ERR
paso "1. Respaldo"
mkdir -p "$C/backups/$TS" "$C/hooks" "$C/skills"
for f in settings.json CLAUDE.md; do [ -f "$C/$f" ] && cp "$C/$f" "$C/backups/$TS/"; done
ok "respaldo en $C/backups/$TS"

paso "2. Hooks + tests"
cp "$HERE/hooks/"*.py "$C/hooks/"
bash "$HERE/tests/test-hooks.sh" >/dev/null || die "tests de hooks fallaron (bash tests/test-hooks.sh)"
ok "hooks instalados, tests OK"

paso "3. CLAUDE.md + settings.json (fusiona, conserva plugins/marketplaces existentes)"
cp "$HERE/CLAUDE.md" "$C/CLAUDE.md"
[ -f "$C/settings.json" ] || echo '{}' > "$C/settings.json"
# Fusión: conserva todo lo del usuario; une listas de permisos; sustituye solo NUESTROS hooks.
jq -s '
  .[0] as $o | .[1] as $n
  | ($o * ($n | del(.hooks, .permissions)))
  | .permissions.allow = ((($o.permissions.allow // []) + ($n.permissions.allow // [])) | unique)
  | .permissions.deny  = ((($o.permissions.deny  // []) + ($n.permissions.deny  // [])) | unique)
  | .hooks = (($o.hooks // {}) | with_entries(.value |= map(select((tostring | test("guard-bash|guard-git|guard-secrets-write|verify-claims")) | not))))
  | reduce ($n.hooks | to_entries[]) as $e (.; .hooks[$e.key] = ((.hooks[$e.key] // []) + $e.value))
' "$C/settings.json" "$HERE/settings.json" > "$C/settings.json.new"
jq -e '.hooks.PreToolUse and .hooks.Stop and .permissions.deny' "$C/settings.json.new" >/dev/null || die "settings inválido"
mv "$C/settings.json.new" "$C/settings.json"
ok "configuración aplicada"

paso "4. Marketplace oficial + plugins"
claude plugin marketplace list 2>/dev/null | grep -q claude-plugins-official \
  || claude plugin marketplace add anthropics/claude-plugins-official >/dev/null
for p in "${PLUGINS[@]}"; do
  out=$(claude plugin install "$p@claude-plugins-official" 2>&1) || die "plugin $p: $(echo "$out" | tail -2)"
  ok "plugin $p"
done

paso "5. Skills de terceros (fijadas)"
rm -rf "$C/skills/context-budget" "$C/skills/growth-log"
cp -r "$HERE/skills/context-budget" "$HERE/skills/growth-log" "$C/skills/"
ok "context-budget, growth-log (ECC ef648e0)"

[ -d "$C/skills/arena-skill" ] && [ ! -d "$C/skills/arena-skill/.git" ] && rm -rf "$C/skills/arena-skill"
if [ ! -d "$C/skills/arena-skill/.git" ]; then git clone -q "$ARENA_REPO" "$C/skills/arena-skill"; fi
git -C "$C/skills/arena-skill" fetch -q origin "$ARENA_SHA" 2>/dev/null || true
git -C "$C/skills/arena-skill" checkout -q "$ARENA_SHA" || die "arena: commit $ARENA_SHA no disponible"
ok "arena @ ${ARENA_SHA:0:7}"

mkdir -p "$C/skills/audit-prompt"
curl -fsSL "https://raw.githubusercontent.com/FlorianBruniaux/claude-code-ultimate-guide/$AUDIT_SHA/tools/audit-prompt.md" \
  -o "$C/skills/audit-prompt/audit-prompt.md" || die "descarga audit-prompt"
cp "$HERE/skills/audit-prompt/SKILL.md" "$C/skills/audit-prompt/SKILL.md"
ok "audit-prompt @ ${AUDIT_SHA:0:7}"

uv tool install -q "graphifyy==$GRAPHIFY_VER" 2>/dev/null || uv tool install -q --force "graphifyy==$GRAPHIFY_VER"
graphify install --platform claude >/dev/null || die "graphify install"
ok "graphify $GRAPHIFY_VER"

paso "5b. MCP de usuario (credenciales SOLO por variables de entorno)"
claude mcp remove -s user paperclip >/dev/null 2>&1 || true
claude mcp add -s user paperclip -e 'PAPERCLIP_API_URL=${PAPERCLIP_API_URL:-http://localhost:3100}' \
  -e 'PAPERCLIP_API_KEY=${PAPERCLIP_API_KEY:-}' -e 'PAPERCLIP_COMPANY_ID=${PAPERCLIP_COMPANY_ID:-}' \
  -- npx -y "$PAPERCLIP_MCP" >/dev/null || die "mcp paperclip"
claude mcp remove -s user stitch >/dev/null 2>&1 || true
claude mcp add -s user stitch -e 'STITCH_API_KEY=${STITCH_API_KEY:-}' -- npx -y "$STITCH_MCP" proxy >/dev/null || die "mcp stitch"
ok "paperclip, stitch (Claude Design es nativo: /design-login)"
[ -n "${PAPERCLIP_API_KEY:-}" ] || echo "  ⚠ falta PAPERCLIP_API_KEY: paperclip no conectará hasta definirla"
[ -n "${STITCH_API_KEY:-}" ]    || echo "  ⚠ falta STITCH_API_KEY: stitch no conectará hasta definirla"

paso "6. Limpieza de duplicados (superpowers los reemplaza)"
for s in verification-before-completion systematic-debugging delivery-gate arena; do
  if [ -e "$C/skills/$s" ]; then mv "$C/skills/$s" "$C/backups/$TS/skill-$s"; ok "movida $s a respaldo"; fi
done

paso "7. Verificación real"
jq -e '[.hooks.PreToolUse[].hooks[].command] | any(test("guard-bash"))' "$C/settings.json" >/dev/null || die "hook guard-bash no registrado"
jq -e '[.hooks.Stop[].hooks[].command] | any(test("verify-claims"))' "$C/settings.json" >/dev/null || die "hook verify-claims no registrado"
jq -e '[.hooks.PreToolUse[].hooks[].command] | any(test("guard-secrets-write"))' "$C/settings.json" >/dev/null || die "hook guard-secrets-write no registrado"
for s in context-budget growth-log audit-prompt graphify; do [ -f "$C/skills/$s/SKILL.md" ] || die "falta skill $s"; done
[ -f "$C/skills/arena-skill/skills/arena/SKILL.md" ] || die "falta arena"
n=$(claude plugin list 2>/dev/null | grep -c "@claude-plugins-official" || true)
[ "$n" -ge "${#PLUGINS[@]}" ] || die "plugins instalados: $n de ${#PLUGINS[@]}"
jq -e '.mcpServers.paperclip and .mcpServers.stitch' "$HOME/.claude.json" >/dev/null || die "MCP no registrados"
ok "todo verificado ($n plugins oficiales, MCP paperclip+stitch registrados)"
echo; echo "Listo. Abre una sesión nueva de Claude Code para que cargue la configuración."
