#!/usr/bin/env bash
# =============================================================================
# drill_restore_clean.sh — restore em ambiente LIMPO (bare-metal drill).
#
# O `verify_backup_restore.sh` prova o restore DENTRO da stack em produção
# (coleção temporária no Qdrant vivo). Este drill vai além: sobe containers e
# volumes NOVOS, do zero, e restaura o backup neles — sem tocar em produção.
#
#   1. extrai o backup mais recente em /var/tmp
#   2. cria um Qdrant novo (volume novo, porta 16333 no loopback)
#   3. restaura TODOS os snapshots nas coleções reais e confere a contagem
#   4. cria um Open WebUI novo (volume novo, porta 13000), semeia o webui.db
#      restaurado e confere: /api/config = 200, usuários, conexão Hermes
#   5. derruba tudo (containers + volumes + diretório) — trap, sempre
#
# O que ele NÃO prova: instalação do SO, Docker, ufw, cron e GPU. Isso é o
# RUNBOOK/rebuild (passos manuais documentados). Aqui a prova é: "com o tar do
# backup e as imagens pinadas, uma máquina vazia volta a ter os dados".
#
# Uso (no host): bash tools/drill_restore_clean.sh [arquivo.tar.gz]
# Exit: 0 = drill ok · 1 = falhou
# =============================================================================
set -uo pipefail

BACKUP="${1:-$(ls -1t /home/usuario/backups/hermes-*.tar.gz 2>/dev/null | head -1)}"
REPO=/home/usuario/hermes-architect
QPORT=16333
OPORT=13000
QNAME=hermesdrill-qdrant
ONAME=hermesdrill-owui
QVOL=hermesdrill_qdrant
OVOL=hermesdrill_owui
Q=http://127.0.0.1:$QPORT
W=""
PASS=0
FAIL=0

ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

cleanup() {
  docker rm -f "$ONAME" "$QNAME" >/dev/null 2>&1
  docker volume rm "$OVOL" "$QVOL" >/dev/null 2>&1
  [ -n "$W" ] && [ -d "$W" ] && rm -rf "$W"
}
trap cleanup EXIT

img() { python3 -c "
import yaml, sys
d = yaml.safe_load(open('$REPO/docker-compose.yml', encoding='utf-8'))
print(d['services']['$1']['image'])
"; }

QIMAGE=$(img qdrant)
OIMAGE=$(img open-webui)
[ -n "$QIMAGE" ] && [ -n "$OIMAGE" ] || { echo "FAIL: não achei as imagens no compose"; exit 1; }
[ -f "$BACKUP" ] || { echo "FAIL: backup não encontrado ($BACKUP)"; exit 1; }

echo "== DRILL de restore limpo — $(basename "$BACKUP") =="
W=$(mktemp -d /var/tmp/drill.XXXXXX) || { echo "FAIL: mktemp"; exit 1; }
tar -xzf "$BACKUP" -C "$W" || { echo "FAIL: extração"; exit 1; }
ok "backup extraído em diretório isolado ($(find "$W" -type f | wc -l) arquivos)"

# Contagens esperadas do manifest
declare -A EXPECTED=()
while IFS= read -r line; do
  case "$line" in
    points=*) n="${line#points=}"; EXPECTED["${n%%:*}"]="${n##*:}" ;;
  esac
done < "$W/README.txt"

# --- 1) Qdrant do zero ---------------------------------------------------------
cleanup_containers() { docker rm -f "$ONAME" "$QNAME" >/dev/null 2>&1; }
cleanup_containers
docker volume rm "$QVOL" >/dev/null 2>&1

docker run -d --name "$QNAME" -p "127.0.0.1:$QPORT:6333" \
  -v "$QVOL:/qdrant/storage" "$QIMAGE" >/dev/null || { bad "subir o Qdrant novo"; exit 1; }

ready=0
for _ in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$Q/" 2>/dev/null)
  [ "$code" = "200" ] && { ready=1; break; }
  sleep 1
done
if [ "$ready" = "1" ]; then ok "Qdrant novo (volume vazio) respondeu em :$QPORT"; else bad "Qdrant novo não subiu"; exit 1; fi

before=$(curl -s "$Q/collections" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["result"]["collections"]))' 2>/dev/null || echo "-")
if [ "$before" = "0" ]; then ok "Qdrant novo começa vazio (0 coleções)"; else bad "Qdrant novo não está vazio ($before coleções)"; fi

# --- 2) restaura cada snapshot na coleção real --------------------------------
shopt -s nullglob
for snap in "$W"/qdrant-*.snapshot; do
  col=$(basename "$snap" .snapshot); col="${col#qdrant-}"
  exp="${EXPECTED[$col]:-?}"
  res=$(curl -s --max-time 900 -X POST \
        "$Q/collections/$col/snapshots/upload?priority=snapshot" \
        -F "snapshot=@$snap")
  case "$res" in
    *'"result":true'*) ;;
    *) bad "$col: upload recusado ($(printf '%s' "$res" | head -c 100))"; continue ;;
  esac

  st="?"
  for _ in $(seq 1 120); do
    st=$(curl -s "$Q/collections/$col" \
         | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["status"])' 2>/dev/null || echo "?")
    [ "$st" = "green" ] && break
    sleep 1
  done
  got=$(curl -s -X POST "$Q/collections/$col/points/count" \
        -H 'Content-Type: application/json' -d '{"exact":true}' \
        | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["count"])' 2>/dev/null || echo "-")

  if [ "$st" = "green" ] && [ "$got" = "$exp" ]; then
    ok "$col: restaurada em Qdrant limpo (pontos=$got)"
  else
    bad "$col: status=$st pontos=$got (esperado $exp)"
  fi
done

# --- 3) Open WebUI do zero ----------------------------------------------------
docker volume create "$OVOL" >/dev/null
# Semeia o volume ANTES do 1º boot. Copiar o banco por cima de um container que já
# subiu deixa um -wal/-shm antigo e o SQLite acusa "database disk image is malformed"
# (aconteceu na 1ª versão deste drill).
if docker run --rm -v "$OVOL:/data" -v "$W:/src:ro" --entrypoint sh "$OIMAGE" \
     -c 'cp /src/webui.db /data/webui.db && chmod 644 /data/webui.db' >/dev/null 2>&1; then
  ok "webui.db restaurado semeado no volume novo (antes do 1º boot)"
else
  bad "semear o webui.db no volume novo"
  exit 1
fi

docker run -d --name "$ONAME" -p "127.0.0.1:$OPORT:8080" \
  -v "$OVOL:/app/backend/data" \
  -e WEBUI_SECRET_KEY=drill-only \
  -e ENABLE_SIGNUP=false \
  "$OIMAGE" >/dev/null || { bad "subir o Open WebUI novo"; exit 1; }

restored=0
for _ in $(seq 1 150); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "http://127.0.0.1:$OPORT/api/config" 2>/dev/null)
  [ "$code" = "200" ] && { restored=1; break; }
  sleep 1
done
if [ "$restored" = "1" ]; then ok "Open WebUI novo sobe com o webui.db restaurado (/api/config=200)"; else bad "Open WebUI não sobe com o banco restaurado"; fi

dbcheck=$(docker exec "$ONAME" python -c "
import sqlite3
c = sqlite3.connect('/app/backend/data/webui.db')
users = c.execute('select count(*) from user').fetchone()[0]
models = [r[0] for r in c.execute('select id from model')]
conn = any('hermes:8642' in str(r) for r in c.execute('select * from config'))
print(str(users) + '|' + ','.join(models) + '|' + str(int(conn)))
" 2>/dev/null || echo "-")
users="${dbcheck%%|*}"
rest="${dbcheck#*|}"; conn="${rest##*|}"
if [ "${users:-0}" -ge 1 ] 2>/dev/null; then ok "usuários restaurados no OWUI limpo ($users)"; else bad "sem usuários no banco restaurado ($dbcheck)"; fi
if [ "$conn" = "1" ]; then ok "conexão Hermes (hermes:8642) restaurada no OWUI limpo"; else bad "conexão Hermes ausente no banco restaurado"; fi

echo
printf '  RESULTADO: PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
if [ "$FAIL" -eq 0 ]; then echo "  >> DRILL OK — um ambiente vazio volta com os dados do backup <<"; fi
[ "$FAIL" -eq 0 ]
