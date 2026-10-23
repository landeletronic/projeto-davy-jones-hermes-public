#!/usr/bin/env bash
# =============================================================================
# questoes.sh — banco de questões do eixo de estudos (share -> SQLite).
#
# Instalado em /usr/local/bin/questoes; agendado a cada 30 min por
# /etc/cron.d/questoes. A lógica é do tools/questoes.py (host, só stdlib) —
# este wrapper só cuida do que o cron precisa:
#
#   1. roda como tlandskron (dono do share e do ~/rag-state): o relatório
#      _relatorio/QUESTOES.md e o .md de estatísticas nascem DENTRO do share;
#      como root, o dono seria root e o usuário não conseguiria mexer;
#   2. flock -n: o import de 8 anos com OCR leva ~10 s, mas se uma execução
#      travar, a seguinte registra "skip" e sai em vez de atropelar;
#   3. tudo vai para ~/rag-state/questoes.log.
#
# Uso:
#   questoes                    # importa o que mudou (idempotente por SHA-256)
#   questoes importar --forcar  # reimporta mesmo sem mudança de arquivo
#   questoes conferir           # 50 questões/50 respostas por ano (sai != 0 se faltar)
#   questoes consultar --ano 2025 --disciplina matematica --numero 26
#   questoes estatisticas --publicar   # publica o .md citável no RAG
# =============================================================================
set -uo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=${HOME:-/home/tlandskron}

REPO=${HERMES_REPO:-/home/tlandskron/hermes-architect}
WORKER="$REPO/tools/questoes.py"
STATE=${RAG_STATE:-/home/tlandskron/rag-state}
LOG="$STATE/questoes.log"
LOCK="$STATE/questoes.lock"

# Chamado à mão como root? refaz como o dono do share.
if [ "$(id -u)" = "0" ]; then
  exec sudo -u tlandskron -- "$0" "$@"
fi

mkdir -p "$STATE"

if [ ! -f "$WORKER" ]; then
  echo "ERRO: banco ausente em $WORKER (rode ops/deploy/sync-to-host.ps1)" >&2
  exit 2
fi

exec 9>"$LOCK" || exit 2
if ! flock -n 9; then
  echo "$(date +%Y-%m-%dT%H:%M:%S%:z)  [skip] execução anterior ainda rodando (lock)" >>"$LOG"
  exit 0
fi

# questoes.log não pode crescer sem limite (roda 48x por dia)
if [ -f "$LOG" ] && [ "$(stat -c %s "$LOG" 2>/dev/null || echo 0)" -gt 5242880 ]; then
  mv -f "$LOG" "$LOG.1"
fi

echo "$(date +%Y-%m-%dT%H:%M:%S%:z)  == questoes ${*:-(cron)}" >>"$LOG"

rodar() {
  # Cron chama SEM argumentos: aí só o log. Chamado à mão (TTY ou `ssh host 'questoes conferir'`)
  # a saída tem de aparecer — senão o usuário não vê nada.
  if [ -t 1 ] || [ "$#" -gt 0 ]; then
    python3 "$WORKER" "$@" 2>&1 | tee -a "$LOG"
    return "${PIPESTATUS[0]}"
  fi
  python3 "$WORKER" "$@" >>"$LOG" 2>&1
}

rodar "$@"
rc=$?
# Depois de importar, publica o documento de estatísticas no share (o worker de
# ingestão o pega como qualquer .md): o chat de estudo passa a responder
# "quantas de matemática caíram em 2025" com citação.
if [ "$rc" = "0" ] && { [ "$#" = "0" ] || [ "${1:-}" = "importar" ]; }; then
  rodar estatisticas --publicar
  rc=$?
fi
echo "$(date +%Y-%m-%dT%H:%M:%S%:z)  == fim rc=$rc" >>"$LOG"
exit $rc
