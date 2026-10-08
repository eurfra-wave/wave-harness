# Arnés Senior Cloudcode V3

Instalar en una sesión nueva en la nube:  `bash setup.sh`   (exit 0 = todo verificado)
Probar los hooks:                        `bash tests/test-hooks.sh`

| Archivo | Qué hace |
|---|---|
| CLAUDE.md | Reglas duras y flujo (se copia a ~/.claude) |
| settings.json | Permisos deny/allow + registro de hooks (se fusiona, no pisa lo tuyo) |
| hooks/guard-bash.py | PreToolUse: frena push/merge, ramas UAT/PROD y lectura de secretos por Bash |
| hooks/verify-claims.py | Stop: obliga a verificar antes de afirmar éxito |
| hooks/guard-secrets-write.py | PreToolUse: impide escribir claves reales en archivos |
| tests/test-hooks.sh | 91 pruebas de los hooks |
| templates/session-start.sh + repo-settings.json | Auto-instalación en cada sesión de nube (copiar a cada repo de WAVE) |
| templates/project-settings.json | Sandbox por proyecto (Linux/macOS/WSL; no en Windows nativo) |
| skills/ | context-budget, growth-log (ECC @ ef648e0), wrapper audit-prompt |

Decisiones y descartes: ver informe en la conversación del 2026-10-08.

## Activar la instalación automática (una sola vez)
1. Sube esta carpeta a un repo de WAVE en GitHub (tú haces el push): `git clone harness-v3.bundle wave-harness` y luego `git remote add origin <url>` y `git push -u origin main --tags`.
2. En cada repo de trabajo: copia `templates/session-start.sh` a `.claude/hooks/` y fusiona `templates/repo-settings.json` en `.claude/settings.json`.
3. En el entorno de nube define `WAVE_HARNESS_REPO=<url del repo>` y `WAVE_HARNESS_REF=v3.1`.
