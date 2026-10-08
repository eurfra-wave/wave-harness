#!/bin/bash
# Tests de los hooks del arnés. Uso: bash tests/test-hooks.sh  (exit 0 = todo OK)
set -u
DIR="$(cd "$(dirname "$0")/.." && pwd)"
G="$DIR/hooks/guard-bash.py"; V="$DIR/hooks/verify-claims.py"
TMP="$(mktemp -d)"; FAIL=0; N=0
expect(){ N=$((N+1)); if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3 (esperado $1, obtuvo $2)"; FAIL=$((FAIL+1)); fi; }

echo "guard-bash (2 = bloquea, 0 = permite)"
g(){ printf '%s' "$2" | jq -Rs '{tool_name:"Bash",tool_input:{command:.}}' | python3 "$G" 2>/dev/null; expect "$1" "$?" "$2"; }
for c in "git push origin main" "git -C . push" "cd sub && git push" "git -c a=b merge dev" \
         "FOO=1 git push" "/usr/bin/git push" 'echo $(git push)' "(git push)" "{ git merge x; }" \
         'bash -c "git push"' "sudo git push" "gh pr merge 12"; do g 2 "$c"; done
for c in "git status" "git log --grep push" "echo 'git push es peligroso'" \
         "git commit -m 'merge notes'" "npm run push-docs" "git diff main"; do g 0 "$c"; done
for c in "cat .env" "python3 -c \"open('.env').read()\"" "cp sub/.env.local /tmp/x" "head server.pem" \
         "cat ~/.aws/credentials" "base64 id_rsa.key" "less config/.env.production"; do g 2 "$c"; done
for c in "cp .env.example .env.example.bak" "cat README.md" "npm run env:check" "ls environment/" \
         "grep -r apikey src/" "cat keyboard.txt"; do g 0 "$c"; done
# Casos de la revisión adversarial (evasiones comunes -> 2)
for c in "bash -lc 'git push'" "sh -ec 'git merge x'" "sudo -u root git push" "env -i git push" \
         "timeout 5 git push" "nice git push" "git push&" "if true; then git push; fi" "! git push" \
         "gh -R o/r pr merge 1" "gh api repos/o/r/pulls/1/merge -X PUT" "cat ~/.ssh/id_rsa" "cat ~/.netrc" \
         "cat secrets/credentials.json" "cat cert.p12"; do g 2 "$c"; done
# Falsos positivos de la revisión (legítimos -> 0)
for c in "git commit -m 'x; git push; y'" "git push --help" "cat src/credentials.py" "grep -rn credentials src/" \
         "pytest tests/test_credentials.py" "ls credentials/" "npm run build:credentials" \
         "git commit -m 'update .env handling'" "echo 'cp .env.example .env' >> README.md" "cat id_rsa.pub"; do g 0 "$c"; done
# Regla 3: ramas protegidas (repos reales temporales)
for b in uat feature; do git init -q -b "$b" "$TMP/repo-$b"; done
gc(){ jq -n --arg c "$2" --arg d "$3" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' | python3 "$G" 2>/dev/null; expect "$1" "$?" "[$(basename "$3")] $2"; }
gc 2 "git commit -m x" "$TMP/repo-uat";  gc 2 "git reset --hard HEAD~1" "$TMP/repo-uat"; gc 2 "git rebase main" "$TMP/repo-uat"
gc 2 "git -C ../repo-uat commit -m x" "$TMP/repo-feature"; gc 2 "git branch -D prod" "$TMP/repo-feature"
gc 0 "git commit -m x" "$TMP/repo-feature"; gc 0 "git log --oneline" "$TMP/repo-uat"; gc 0 "git status" "$TMP/repo-uat"
gc 0 "git diff uat" "$TMP/repo-feature"; gc 0 "git checkout uat" "$TMP/repo-feature"
echo '{"tool_name":"Read","tool_input":{}}' | python3 "$G"; expect 0 $? "otra herramienta no se toca"
echo '{roto' | python3 "$G" 2>/dev/null; expect 0 $? "JSON roto no rompe la sesión"

echo "verify-claims (2 = bloquea, 0 = permite)"
mk(){ { echo '{"type":"user","message":{"role":"user","content":"arregla el bug"}}'
        [ "$2" = 1 ] && echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{}}]}}' \
                     && echo '{"type":"user","message":{"content":[{"type":"tool_result"}]}}'
        echo "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"$3\"}]}}"; } > "$TMP/$1.jsonl"; }
v(){ echo "{\"transcript_path\":\"$TMP/$2.jsonl\",\"stop_hook_active\":$3}" | python3 "$V" 2>/dev/null; expect "$1" "$?" "$4"; }
mk a 0 "Listo, ya quedó arreglado y los tests pasan."
mk b 1 "Listo, ya quedó arreglado y los tests pasan."
mk c 0 "Te explico cómo funciona el módulo."
v 2 a false "afirma éxito sin ejecutar nada"
v 0 b false "afirma éxito con evidencia"
v 0 c false "no afirma éxito"
v 0 a true  "stop_hook_active evita bucle"
h(){ jq -n --arg p "$TMP/r0.jsonl" --arg m "$2" '{transcript_path:$p,stop_hook_active:false,last_assistant_message:$m}' | python3 "$V" 2>/dev/null; expect "$1" "$?" "msg: $2"; }
echo '{"type":"user","message":{"role":"user","content":"x"}}' > "$TMP/r0.jsonl"
for m in "Los tests están en verde." "Se corrigió el fallo." "Completado con éxito." "Everything works." "Ya funciona."; do h 2 "$m"; done
for m in "No pude verificar si los tests pasan; no ejecuté nada." "Si los tests pasan, avísame." \
         "El bug está arreglado según el PR (no lo probé)." "Te explico la arquitectura."; do h 0 "$m"; done
# Formato real (capturado en vivo): el transcript NO trae la respuesta final; llega en last_assistant_message
echo '{"type":"user","message":{"role":"user","content":"arregla"}}' > "$TMP/r.jsonl"
jq -n --arg p "$TMP/r.jsonl" '{transcript_path:$p,stop_hook_active:false,last_assistant_message:"Listo, los tests pasan."}' | python3 "$V" 2>/dev/null
expect 2 $? "formato real: éxito sin evidencia vía last_assistant_message"
echo '{roto' | python3 "$V"; expect 0 $? "JSON roto no rompe la sesión"

echo "guard-secrets-write (2 = bloquea, 0 = permite)"
W="$DIR/hooks/guard-secrets-write.py"
w(){ jq -n --arg t "$2" --arg c "$3" '{tool_name:$t,tool_input:{file_path:"x",content:$c,new_string:$c}}' | python3 "$W" 2>/dev/null; expect "$1" "$?" "$2: $4"; }
R16=$(printf 'Q%.0s' {1..16}); R36=$(printf 'a1%.0s' {1..18}); R40=$(printf 'b2%.0s' {1..20})
w 2 Write "aws_key = \"AK""IA$R16\"" "clave AWS real"
w 2 Edit  "token: gh""p_$R36" "token GitHub"
w 2 Write "-----BEGIN RSA PRIV""ATE KEY-----" "clave privada"
w 2 Write "ANTHROPIC=sk-an""t-$R40" "clave Anthropic"
w 0 Write "aws_key = \"AK""IAIOSFODNN7EXAMPLE\"" "ejemplo oficial AWS"
w 0 Write "token: \${GITHUB_TOKEN}" "variable de entorno"
w 0 Write "def suma(a, b): return a + b" "código normal"
jq -n '{tool_name:"Bash",tool_input:{command:"x"}}' | python3 "$W"; expect 0 $? "otra herramienta no se toca"

rm -rf "$TMP"
echo "Resultado: $((N-FAIL))/$N OK"; [ $FAIL -eq 0 ]
