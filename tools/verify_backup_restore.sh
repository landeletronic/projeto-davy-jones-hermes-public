#!/usr/bin/env bash
# =============================================================================
# verify_backup_restore.sh — prova que o backup RESTAURA.
#
# A suíte (tests/verify_stack.sh) valida que o tar abre e que o conteúdo é
# íntegro. Este script vai além, sem tocar no stack em produção:
#
#   1. extrai o backup mais recente em /var/tmp (diretório isolado)
#   2. valida o webui.db restaurado (integrity_check, usuários, modelo, conexão)
#   3. valida o compose e a config do Hermes restaurados
#   4. restaura CADA snapshot do Qdrant numa coleção temporária
#      (`<colecao>__restore_test`), confere a contagem contra o manifest e apaga
#   5. remove o diretório temporário (trap — sempre, mesmo com erro)
#
# Uso (no host):  bash /tmp/verify_backup_restore.sh [arquivo.tar.gz]
# Exit: 0 = restore provado · 1 = falhou
# =============================================================================
set -uo pipefail

BACKUP="${1:-$(ls -1t /home/tlandskron/backups/hermes-*.tar.gz 2>/dev/null | head -1)}"
QDRANT="${QDRANT:-http://localhost:6333}"
PASS=0
FAIL=0
W=""

cleanup() {
  # Apaga qualquer coleção temporária que tenha sobrado (inclusive de falhas).
  for c in $(curl -s --max-time 5 "$QDRANT/collections" 2>/dev/null \
      | python3 -c 'import sys,json
try:
    print("\n".join(c["name"] for c in json.load(sys.stdin)["result"]["collections"]))
except Exception:
    pass' 2>/dev/null); do
    case "$c" in *__restore_test) curl -s -X DELETE "$QDRANT/collections/$c" >/dev/null 2>&1 ;; esac
  done
  [ -n "$W" ] && [ -d "$W" ] && rm -rf "$W"
}
trap cleanup EXIT

ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

[ -f "$BACKUP" ] || { echo "FAIL: backup não encontrado ($BACKUP)"; exit 1; }
echo "== RESTORE de $(basename "$BACKUP") =="

W=$(mktemp -d /var/tmp/restore-test.XXXXXX) || { echo "FAIL: mktemp"; exit 1; }
tar -xzf "$BACKUP" -C "$W" || { echo "FAIL: extração"; exit 1; }
ok "extrai o pacote ($(find "$W" -type f | wc -l) arquivos)"

# --- 1) webui.db -------------------------------------------------------------
if python3 - "$W/webui.db" <<'PY'
import sqlite3, sys
c = sqlite3.connect(f'file:{sys.argv[1]}?mode=ro', uri=True)
assert c.execute('pragma integrity_check').fetchone()[0] == 'ok', 'integrity'
users = c.execute('select count(*) from user').fetchone()[0]
assert users >= 1, 'sem usuários'
assert 'hermes-agent' in [r[0] for r in c.execute('select id from model')], 'sem hermes-agent'
assert any('hermes:8642' in str(r) for r in c.execute('select * from config')), 'sem conexão Hermes'
print(f'        integrity=ok users={users}')
PY
then ok "webui.db restaurado é consultável e tem a conexão Hermes"
else bad "webui.db restaurado inutilizável"
fi

# --- 2) compose --------------------------------------------------------------
mkdir -p "$W/cfg" "$W/hermes"
if tar -xzf "$W/project-config.tgz" -C "$W/cfg" 2>/dev/null \
   && python3 - "$W/cfg/docker-compose.yml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))
svcs = d.get('services') or {}
assert len(svcs) >= 10, f'{len(svcs)} serviços'
bad = [str(s.get('image')) for s in svcs.values()
       if any(x in str(s.get('image', '')) for x in (':latest', ':main', ':rocm'))]
assert not bad, bad
print(f'        services={len(svcs)} imagens=pinadas')
PY
then ok "compose restaurado é válido e pinado"
else bad "compose restaurado inválido"
fi

# --- 3) config do Hermes -----------------------------------------------------
if tar -xzf "$W/hermes-data.tgz" -C "$W/hermes" 2>/dev/null \
   && python3 - "$W/hermes/.hermes/config.yaml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))
assert d.get('memory', {}).get('provider') == 'mem0', 'memory.provider != mem0'
assert d.get('model', {}).get('default'), 'model.default vazio'
PY
then ok ".hermes/config.yaml restaurado (mem0 + modelo)"
else bad ".hermes/config.yaml restaurado inválido"
fi

# --- 4) snapshots Qdrant -> coleção temporária -------------------------------
declare -A EXPECTED=()
while IFS= read -r line; do
  case "$line" in
    points=*) n="${line#points=}"; EXPECTED["${n%%:*}"]="${n##*:}" ;;
  esac
done < "$W/README.txt"

shopt -s nullglob
for snap in "$W"/qdrant-*.snapshot; do
  col=$(basename "$snap" .snapshot); col="${col#qdrant-}"
  tmp="${col}__restore_test"
  exp="${EXPECTED[$col]:-?}"

  curl -s -X DELETE "$QDRANT/collections/$tmp" >/dev/null 2>&1
  res=$(curl -s --max-time 600 -X POST \
        "$QDRANT/collections/$tmp/snapshots/upload?priority=snapshot" \
        -F "snapshot=@$snap")
  case "$res" in
    *'"result":true'*) ;;
    *) bad "$col: upload recusado ($(printf '%s' "$res" | head -c 100))"; continue ;;
  esac

  st="?"
  for _ in $(seq 1 60); do
    st=$(curl -s "$QDRANT/collections/$tmp" \
         | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["status"])' 2>/dev/null || echo "?")
    [ "$st" = "green" ] && break
    sleep 1
  done

  got=$(curl -s -X POST "$QDRANT/collections/$tmp/points/count" \
        -H 'Content-Type: application/json' -d '{"exact":true}' \
        | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["count"])' 2>/dev/null || echo "-")

  if [ "$st" = "green" ] && [ "$got" = "$exp" ]; then
    ok "$col: restaurada (status=$st, pontos=$got)"
  else
    bad "$col: status=$st pontos=$got (esperado $exp)"
  fi

  curl -s -X DELETE "$QDRANT/collections/$tmp" >/dev/null 2>&1
done

# --- 5) prova de busca semântica (só se mem0_memories tiver dados) -----------
if [ "${EXPECTED[mem0_memories]:-0}" -gt 0 ] 2>/dev/null; then
  tmp="mem0_memories__restore_test"
  curl -s -X DELETE "$QDRANT/collections/$tmp" >/dev/null 2>&1
  curl -s --max-time 600 -X POST "$QDRANT/collections/$tmp/snapshots/upload?priority=snapshot" \
    -F "snapshot=@$W/qdrant-mem0_memories.snapshot" >/dev/null 2>&1
  for _ in $(seq 1 60); do
    st=$(curl -s "$QDRANT/collections/$tmp" \
         | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["status"])' 2>/dev/null || echo "?")
    [ "$st" = "green" ] && break
    sleep 1
  done
  curl -s -X POST "$QDRANT/collections/$tmp/points/scroll" \
       -H 'Content-Type: application/json' \
       -d '{"limit":1,"with_payload":true,"with_vector":true}' > "$W/probe.json"
  if python3 - "$W/probe.json" > "$W/qvec.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))['result']['points'][0]
json.dump({'vector': p['vector'], 'limit': 3, 'with_payload': True}, sys.stdout)
PY
  then
    hits=$(curl -s -X POST "$QDRANT/collections/$tmp/points/search" \
           -H 'Content-Type: application/json' -d @"$W/qvec.json" \
           | python3 -c 'import sys,json;print(len(json.load(sys.stdin).get("result",[])))' 2>/dev/null || echo 0)
    if [ "$hits" -ge 1 ]; then ok "vetores restaurados são pesquisáveis ($hits hits)"; else bad "busca no snapshot restaurado retornou 0 hits"; fi
  else
    bad "não foi possível extrair vetor de prova"
  fi
  curl -s -X DELETE "$QDRANT/collections/$tmp" >/dev/null 2>&1
fi

echo
printf '  RESULTADO: PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && echo "  >> RESTORE OK <<"
[ "$FAIL" -eq 0 ]
