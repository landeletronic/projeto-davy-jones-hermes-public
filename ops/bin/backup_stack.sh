#!/usr/bin/env bash
# =============================================================================
# backup_stack.sh — backup consistente do lab (roda NO HOST, via cron)
#
# Gera /home/usuario/backups/hermes-<UTC>.tar.gz contendo:
#   - docker-compose.yml renderizado (docker compose config)
#   - .hermes/ (config, mem0.json, .env, plugins)
#   - webui.db e grafana.db (cópias consistentes via sqlite3 .backup)
#   - snapshots de TODAS as coleções do Qdrant
#   - documentos do eixo de estudos (~/documents, share SMB) e ~/rag-state
#   - manifest (data, containers, digests, contagens)
#
# Retenção local: 14 dias de diários + o backup mais recente de cada um dos
# últimos 6 meses (âncora mensal). `--prune-dry-run` só relata o que sairia —
# é o que a suíte usa para provar que a política está sendo aplicada.
# Permissão 600 (contém segredos).
# =============================================================================
set -euo pipefail

DEST=/home/usuario/backups
COMPOSE_DIR=/home/usuario/hermes-architect
HERMES_DIR=/home/usuario/.hermes
# Documentos do eixo de estudos (share SMB) e o estado do ingestão: ficam FORA
# do repo, mas precisam entrar no backup — é a segunda cópia (a primeira é o PC).
DOCS_DIR=${DOCS_DIR:-/home/usuario/documents}
RAG_STATE=${RAG_STATE:-/home/usuario/rag-state}
KEEP_DAYS=14
KEEP_MONTHS=6
TS=$(date -u +%Y%m%dT%H%M%SZ)
WORK=$(mktemp -d /tmp/hermes-backup.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

# Aplica (ou só simula) a retenção. Um arquivo sobrevive se:
#   (a) tem menos de KEEP_DAYS dias, ou
#   (b) é o mais recente do seu mês, dentre os últimos KEEP_MONTHS meses.
# O que não cai em nenhum dos dois é removido — e um link `latest.tar.gz`
# órfão é reapontado para o mais novo que sobrou.
prune() {
  local dry="${1:-0}" f cut i ym newest n=0 keep_monthly=""
  cut=$(date -u -d "-${KEEP_DAYS} days" +%s)
  i=0
  while [ "$i" -lt "$KEEP_MONTHS" ]; do
    ym=$(date -u -d "-$i month" +%Y-%m)
    # `ls` sem match sai != 0 e, com pipefail, mataria o script — daí o `||`.
    newest=$(ls -1 "$DEST"/hermes-"${ym//-/}"??T*.tar.gz 2>/dev/null | sort | tail -1) || newest=""
    [ -n "$newest" ] && keep_monthly="$keep_monthly $newest"
    i=$((i + 1))
  done
  for f in $(ls -1 "$DEST"/hermes-*.tar.gz 2>/dev/null | sort); do
    case " $keep_monthly " in *" $f "*) continue ;; esac
    if [ "$(stat -c %Y "$f")" -lt "$cut" ]; then
      n=$((n + 1))
      echo "PRUNE: $f"
      [ "$dry" -eq 1 ] || rm -f -- "$f"
    fi
  done
  if [ -L "$DEST/latest.tar.gz" ] && [ ! -e "$DEST/latest.tar.gz" ] && [ "$dry" -eq 0 ]; then
    newest=$(ls -1t "$DEST"/hermes-*.tar.gz 2>/dev/null | head -1) || newest=""
    [ -n "$newest" ] && ln -sfn "$(basename "$newest")" "$DEST/latest.tar.gz"
  fi
  echo "RETENTION: $n a remover (politica: ${KEEP_DAYS} dias + ${KEEP_MONTHS} mensais; no disco: $(ls -1 "$DEST"/hermes-*.tar.gz 2>/dev/null | wc -l))"
}

if [ "${1:-}" = "--prune-dry-run" ]; then
  prune 1
  exit 0
fi

mkdir -p "$DEST"
chmod 700 "$DEST"

echo "[1/9] compose renderizado"
(cd "$COMPOSE_DIR" && docker compose config > "$WORK/docker-compose.rendered.yml")

echo "[2/9] configs do projeto (compose, nginx, monitoring, searxng)"
tar -C "$COMPOSE_DIR" -czf "$WORK/project-config.tgz" \
  --exclude='*.bak*' \
  docker-compose.yml .env nginx monitoring searxng 2>/dev/null || true

echo "[3/9] .hermes (config/plugins/skills; runtime/caches fora)"
sudo tar -C "$(dirname "$HERMES_DIR")" -czf "$WORK/hermes-data.tgz" \
  --warning=no-file-changed \
  --exclude='.hermes/home/.cache' \
  --exclude='.hermes/bin' \
  --exclude='.hermes/cache' \
  --exclude='.hermes/lazy-packages' \
  --exclude='.hermes/installs' \
  --exclude='.hermes/audio_cache' \
  --exclude='.hermes/image_cache' \
  --exclude='.hermes/images' \
  --exclude='.hermes/sandboxes' \
  --exclude='.hermes/terminal-sessions' \
  --exclude='*.sock' \
  "$(basename "$HERMES_DIR")" || [ $? -eq 1 ]
sudo chown "$(id -u):$(id -g)" "$WORK/hermes-data.tgz"

echo "[4/9] documentos (share SMB) + estado do ingesto"
# Ficam fora do repo (o repo é código): esta é a SEGUNDA cópia — a primeira é o
# PC que gravou o arquivo. Sem isso, um disco perdido apagaria editais e provas.
if [ -d "$DOCS_DIR" ]; then
  tar -C "$(dirname "$DOCS_DIR")" -czf "$WORK/documents.tgz" \
    --exclude='*.tmp' --exclude='~$*' --exclude='.~lock*' \
    "$(basename "$DOCS_DIR")" 2>/dev/null || true
else
  echo "[4/9] AVISO: $DOCS_DIR ausente - backup segue sem documentos" >&2
fi
if [ -d "$RAG_STATE" ]; then
  tar -C "$(dirname "$RAG_STATE")" -czf "$WORK/rag-state.tgz" "$(basename "$RAG_STATE")" 2>/dev/null || true
fi

echo "[5/9] webui.db (sqlite .backup)"
docker exec -i open-webui python - <<'PY'
import sqlite3
src = sqlite3.connect('/app/backend/data/webui.db')
dst = sqlite3.connect('/tmp/webui-backup.db')
src.backup(dst)
dst.close()
src.close()
PY
docker cp open-webui:/tmp/webui-backup.db "$WORK/webui.db" >/dev/null
docker exec open-webui rm -f /tmp/webui-backup.db

# grafana.db: dashboards/datasources voltam por arquivo (provisioning), mas
# usuários, prefs e o histórico de alertas vivem no SQLite. Copiado pela API
# `.backup` (segura com WAL) a partir de um container com o volume montado:
# `docker cp` do arquivo vivo pode sair inconsistente.
echo "[6/9] grafana.db (sqlite .backup)"
gvol=$(docker inspect grafana --format '{{range .Mounts}}{{if eq .Destination "/var/lib/grafana"}}{{.Name}}{{end}}{{end}}' 2>/dev/null)
if [ -n "$gvol" ] && docker image inspect hermes-tools:local >/dev/null 2>&1; then
  docker run --rm -i --entrypoint python3 \
    -v "$gvol":/grafana-data -v "$WORK":/out hermes-tools:local - <<'PY'
import sqlite3
src = sqlite3.connect('/grafana-data/grafana.db')
dst = sqlite3.connect('/out/grafana.db')
src.backup(dst)
dst.close()
src.close()
PY
  chown "$(id -u):$(id -g)" "$WORK/grafana.db" 2>/dev/null || true
else
  echo "[6/9] AVISO: grafana_data não encontrado — backup segue sem grafana.db" >&2
fi

echo "[7/9] snapshots Qdrant"
collections=$(curl -s --max-time 10 http://localhost:6333/collections \
  | python3 -c 'import sys,json; [print(c["name"]) for c in json.load(sys.stdin)["result"]["collections"]]')
for c in $collections; do
  snap=$(curl -s --max-time 60 -X POST "http://localhost:6333/collections/$c/snapshots" \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["name"])')
  curl -s --max-time 600 -o "$WORK/qdrant-$c.snapshot" \
    "http://localhost:6333/collections/$c/snapshots/$snap"
  curl -s -X DELETE "http://localhost:6333/collections/$c/snapshots/$snap" >/dev/null || true
done

echo "[8/9] manifest"
{
  echo "backup_utc=$TS"
  echo "host=$(hostname)"
  docker ps --format 'container={{.Names}} status={{.Status}} image={{.Image}}'
  for i in $(docker ps --format '{{.Image}}' | sort -u); do
    echo "digest=$i $(docker image inspect "$i" --format '{{index .RepoDigests 0}}' 2>/dev/null || true)"
  done
  for c in $collections; do
    n=$(curl -s -X POST "http://localhost:6333/collections/$c/points/count" \
      -H 'Content-Type: application/json' -d '{"exact":true}' \
      | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["count"])')
    echo "points=$c:$n"
  done
} > "$WORK/README.txt"

echo "[9/9] empacotando"
OUT="$DEST/hermes-$TS.tar.gz"
tar -C "$WORK" -czf "$OUT" .
chmod 600 "$OUT"
ln -sfn "$(basename "$OUT")" "$DEST/latest.tar.gz"

# Métricas para o Prometheus (textfile do node-exporter): alimentam os alertas
# LabBackupStale e LabBackupMetricMissing. Falha aqui NÃO derruba o backup.
TEXTFILE="$COMPOSE_DIR/ci/textfile"
if [ -d "$TEXTFILE" ]; then
  {
    echo '# HELP hermes_backup_last_success_timestamp_seconds Epoch do último backup bem-sucedido'
    echo '# TYPE hermes_backup_last_success_timestamp_seconds gauge'
    echo "hermes_backup_last_success_timestamp_seconds $(date +%s)"
    echo '# HELP hermes_backup_size_bytes Tamanho do último backup'
    echo '# TYPE hermes_backup_size_bytes gauge'
    echo "hermes_backup_size_bytes $(stat -c %s "$OUT")"
  } > "$TEXTFILE/hermes_backup.prom.tmp" 2>/dev/null \
    && mv -f "$TEXTFILE/hermes_backup.prom.tmp" "$TEXTFILE/hermes_backup.prom" 2>/dev/null || true
fi

prune 0
echo "OK: $OUT ($(du -h "$OUT" | cut -f1))"
