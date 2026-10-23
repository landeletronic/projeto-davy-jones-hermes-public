#!/usr/bin/env bash
# =============================================================================
# verify_qdrant_upgrade.sh — prova um upgrade do Qdrant ANTES de tocar em produção.
#
# POR QUE NÃO USA SNAPSHOT: o snapshot do 1.15.2 carrega índice de payload
# `rocks_db`, que as versões novas não sabem ler ("unknown variant `rocks_db`").
# Restaurar snapshot antigo numa versão nova NÃO é o caminho de upgrade; o
# caminho é o servidor novo **migrar o próprio volume** no boot.
#
# O que este script faz:
#   1. para o Qdrant por alguns segundos e CLONA o volume de produção;
#   2. sobe a versão candidata sobre a CÓPIA (volume novo, porta só no loopback);
#   3. compara coleções e contagens com a produção e testa o scroll do mem0;
#   4. derruba a cópia e garante a produção de volta no ar (trap).
#
# Produção nunca roda a candidata: quem migra, aqui, é a cópia.
#
# Uso (no host):
#   bash tools/verify_qdrant_upgrade.sh                       # v1.19.2
#   bash tools/verify_qdrant_upgrade.sh --image qdrant/qdrant:v1.20.0
#
# Saída: PASS/FAIL por coleção + exit 0 só se tudo bater.
# =============================================================================
set -euo pipefail

IMAGE="qdrant/qdrant:v1.19.2"
VIA=""
PORT=16333
PROD="qdrant"
NAME="qdrant-upgrade-test"
VOL="${NAME}-data"
HELPER="hermes-tools:local"

while [ $# -gt 0 ]; do
  case "$1" in
    --image) IMAGE="$2"; shift 2 ;;
    # Salto grande (ex.: 1.15 -> 1.19) não migra de uma vez: o índice de payload
    # `rocks_db` só é convertido por uma versão intermediária. `--via` sobe essa
    # versão primeiro, sobre a MESMA cópia, e só então a candidata.
    --via) VIA="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker volume rm "$VOL" >/dev/null 2>&1 || true
  # produção SEMPRE volta, mesmo se o teste falhar no meio.
  if [ "$(docker inspect -f '{{.State.Running}}' "$PROD" 2>/dev/null)" != "true" ]; then
    docker start "$PROD" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

prodvol=$(docker inspect "$PROD" --format '{{range .Mounts}}{{if eq .Destination "/qdrant/storage"}}{{.Name}}{{end}}{{end}}')
[ -n "$prodvol" ] || { echo "FAIL: volume de produção do Qdrant não encontrado"; exit 1; }

echo "== candidata: $IMAGE =="
docker image inspect "$IMAGE" >/dev/null 2>&1 || docker pull "$IMAGE"

echo "== clonando o volume de produção ($prodvol) =="
docker stop "$PROD" >/dev/null
docker volume create "$VOL" >/dev/null
docker run --rm -v "$prodvol":/from:ro -v "$VOL":/to --entrypoint sh "$HELPER" -c 'cp -a /from/. /to/' >/dev/null
docker start "$PROD" >/dev/null

# A produção volta a responder antes de qualquer conclusão.
for _ in $(seq 1 60); do
  curl -sf http://127.0.0.1:6333/readyz >/dev/null 2>&1 && break
  sleep 1
done
curl -sf http://127.0.0.1:6333/readyz >/dev/null 2>&1 || { echo "FAIL: produção não voltou"; exit 1; }

# Degrau intermediário: sobe a versão que sabe converter o formato antigo,
# espera ficar pronta, para — e a candidata assume a MESMA cópia já migrada.
if [ -n "$VIA" ]; then
  echo "== degrau: $VIA =="
  docker image inspect "$VIA" >/dev/null 2>&1 || docker pull "$VIA"
  docker run -d --name "${NAME}-via" -p "127.0.0.1:${PORT}:6333" \
    -v "$VOL":/qdrant/storage "$VIA" >/dev/null
  vok=0
  for _ in $(seq 1 90); do
    if curl -sf "http://127.0.0.1:${PORT}/readyz" >/dev/null 2>&1; then vok=1; break; fi
    [ "$(docker inspect -f '{{.State.Running}}' "${NAME}-via" 2>/dev/null)" = "true" ] || break
    sleep 1
  done
  if [ "$vok" -ne 1 ]; then
    echo "FAIL: o degrau $VIA não subiu sobre a cópia"
    docker logs "${NAME}-via" 2>&1 | tail -10
    exit 1
  fi
  docker stop "${NAME}-via" >/dev/null
  docker rm -f "${NAME}-via" >/dev/null
  echo "== degrau ok: volume convertido =="
fi

docker run -d --name "$NAME" -p "127.0.0.1:${PORT}:6333" \
  -v "$VOL":/qdrant/storage "$IMAGE" >/dev/null
ok=0
for _ in $(seq 1 90); do
  if curl -sf "http://127.0.0.1:${PORT}/readyz" >/dev/null 2>&1; then ok=1; break; fi
  # servidor que morre no boot (migração falhou) não vai ficar pronto nunca
  [ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" = "true" ] || break
  sleep 1
done
if [ "$ok" -ne 1 ]; then
  echo "FAIL: a candidata não subiu sobre o volume migrado"
  docker logs "$NAME" 2>&1 | tail -15
  exit 1
fi
ver=$(curl -s "http://127.0.0.1:${PORT}/" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("version"))' 2>/dev/null)
echo "== candidata no ar: $ver (migrou o volume) =="

fail=0
prodcols=$(curl -s http://127.0.0.1:6333/collections | python3 -c 'import sys,json;print(" ".join(sorted(c["name"] for c in json.load(sys.stdin)["result"]["collections"])))')
newcols=$(curl -s "http://127.0.0.1:${PORT}/collections" | python3 -c 'import sys,json;print(" ".join(sorted(c["name"] for c in json.load(sys.stdin)["result"]["collections"])))')
if [ "$prodcols" = "$newcols" ]; then
  echo "  PASS  coleções iguais: $newcols"
else
  echo "  FAIL  coleções divergem: produção=[$prodcols] candidata=[$newcols]"; fail=1
fi

for c in $prodcols; do
  p=$(curl -s -X POST "http://127.0.0.1:6333/collections/$c/points/count" \
      -H 'Content-Type: application/json' -d '{"exact":true}' \
      | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["count"])' 2>/dev/null || echo "?")
  n=$(curl -s -X POST "http://127.0.0.1:${PORT}/collections/$c/points/count" \
      -H 'Content-Type: application/json' -d '{"exact":true}' \
      | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["count"])' 2>/dev/null || echo "?")
  if [ "$p" = "$n" ]; then
    echo "  PASS  $c: $n pontos"
  else
    echo "  FAIL  $c: produção=$p candidata=$n"; fail=1
  fi
done

sc=$(curl -s --max-time 10 -X POST "http://127.0.0.1:${PORT}/collections/mem0_memories/points/scroll" \
  -H 'Content-Type: application/json' -d '{"limit":1,"with_payload":true}' -o /dev/null -w '%{http_code}')
if [ "$sc" = "200" ]; then
  echo "  PASS  mem0_memories: scroll responde"
else
  echo "  FAIL  mem0_memories: scroll -> $sc"; fail=1
fi

[ "$fail" -eq 0 ] && echo "== OK: $IMAGE migra o volume atual ==" || echo "== NÃO suba para $IMAGE =="
exit "$fail"
