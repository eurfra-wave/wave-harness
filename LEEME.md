# Arnés Senior Cloudcode V3

Instalar en una sesión nueva en la nube:  `bash setup.sh`   (exit 0 = todo verificado)
Probar los hooks:                        `bash tests/test-hooks.sh`

| Archivo | Qué hace |
|---|---|
| CLAUDE.md | Reglas duras y flujo (se copia a ~/.claude) |
| settings.json | Permisos deny/allow + registro de hooks (se fusiona, no pisa lo tuyo) |
| hooks/guard-bash.py | PreToolUse: frena push/merge, ramas UAT/PROD y lectura de secretos por Bash |
| hooks/verify-claims.py | Stop: obliga a verificar antes de afirmar éxito |
| tests/test-hooks.sh | 83 pruebas de los hooks |
| templates/project-settings.json | Sandbox por proyecto (Linux/macOS/WSL; no en Windows nativo) |
| skills/ | context-budget, growth-log (ECC @ ef648e0), wrapper audit-prompt |

Decisiones y descartes: ver informe en la conversación del 2026-10-08.
