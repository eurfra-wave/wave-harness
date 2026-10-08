---
name: audit-prompt
description: Auditoría de configuración Claude Code en 8 dimensiones (100 pts). Ejecutar /audit-prompt --include-global antes de decisiones high-stakes.
metadata:
  origin: external
  source: "github.com/FlorianBruniaux/claude-code-ultimate-guide"
  tags: [audit, compliance, governance]
---

# audit-prompt

## Propósito
Audita tu configuración Claude Code en 8 dimensiones (100 pts total). Valida que el harness esté bien cimentado antes de ejecutar decisiones de alto impacto.

## Ejecución
```bash
/audit-prompt                    # Solo proyecto actual
/audit-prompt --include-global   # Incluye ~/.claude/ también
```

## 8 Dimensiones
1. Memory & Context (20 pts)
2. Rules Hygiene (10 pts)
3. Skills Quality (10 pts)
4. Agents/Commands Quality (10 pts)
5. Security Posture (20 pts)
6. MCP Ecosystem (10 pts)
7. Workflow Commands (10 pts)
8. Freshness & Best Practices (10 pts)

## Thresholds
- 80-100: Optimized ✅
- 60-79: Established ⚠️
- 40-59: Growing ⚠️
- <40: Starter ❌

## Fuente
Florian BRUNIAUX, "The Ultimate Claude Code Guide"
