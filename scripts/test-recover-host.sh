#!/usr/bin/env bash
# Prueba recover_host contra Supabase local. Requiere: supabase start + functions serve,
# y un JWT anónimo. Demuestra que se DIFERENCIA GAME_NOT_FOUND de INVALID_PIN y del éxito.
#   SUPABASE_URL=http://localhost:54321 ANON_KEY=... JWT=<jwt anon> PIN=482915 bash scripts/test-recover-host.sh
set -euo pipefail
: "${SUPABASE_URL:?}"; : "${ANON_KEY:?}"; : "${JWT:?}"; : "${PIN:?}"
H=(-H "apikey: $ANON_KEY" -H "Authorization: Bearer $JWT" -H "content-type: application/json")
fail=0; check(){ echo "$2" | grep -q "$3" && echo "PASS: $1" || { echo "FAIL: $1 -> $2"; fail=1; }; }

echo "1) Creando partida con create_game..."
CREATE=$(curl -s -X POST "$SUPABASE_URL/functions/v1/create_game" "${H[@]}" \
  -d "{\"name\":\"Recover Test\",\"host_name\":\"Daniel\",\"host_token\":\"delorean\",\"config\":{},\"request_id\":\"$(uuidgen)\",\"pin\":\"$PIN\"}")
CODE=$(echo "$CREATE" | sed -n 's/.*"code":"\([^"]*\)".*/\1/p')
echo "   code=$CODE"; [ -n "$CODE" ] || { echo "FAIL: no se creó la partida -> $CREATE"; exit 1; }

echo "2) Código inexistente -> GAME_NOT_FOUND"
R=$(curl -s -X POST "$SUPABASE_URL/functions/v1/recover_host" "${H[@]}" -d '{"code":"ZZZZZZ","pin":"'"$PIN"'"}')
check "código inexistente devuelve GAME_NOT_FOUND" "$R" '"GAME_NOT_FOUND"'

echo "3) Código real + PIN incorrecto -> INVALID_PIN (NO GAME_NOT_FOUND)"
R=$(curl -s -X POST "$SUPABASE_URL/functions/v1/recover_host" "${H[@]}" -d '{"code":"'"$CODE"'","pin":"000001"}')
check "PIN incorrecto devuelve INVALID_PIN" "$R" '"INVALID_PIN"'
echo "$R" | grep -q '"GAME_NOT_FOUND"' && { echo "FAIL: PIN incorrecto NO debe dar GAME_NOT_FOUND"; fail=1; } || true

echo "4) Código real con espacios + PIN correcto -> ok (normaliza trim+upper)"
R=$(curl -s -X POST "$SUPABASE_URL/functions/v1/recover_host" "${H[@]}" -d '{"code":"  '"$CODE"'  ","pin":"'"$PIN"'"}')
check "PIN correcto recupera el host" "$R" '"ok":true'

echo "5) Detección de configuración (si falta SERVICE_ROLE/pepper)"
echo "$R" | grep -q 'SERVER_MISCONFIGURED' && echo "AVISO: revisa SUPABASE_SERVICE_ROLE_KEY/HOST_PIN_PEPPER en el runtime" || true
exit $fail
