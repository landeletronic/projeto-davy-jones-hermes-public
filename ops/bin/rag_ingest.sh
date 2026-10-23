#!/usr/bin/env bash
# =============================================================================
# rag_ingest.sh — worker de ingestão do eixo de estudos (share -> RAG do OWUI).
#
# Instalado em /usr/local/bin/rag-ingest; agendado a cada 15 min por
# /etc/cron.d/rag-ingest. A lógica é do tools/rag_ingest.py (host, só stdlib) —
# este wrapper só cuida do que o cron precisa:
#
#   1. roda como tlandskron (dono do share e do ~/rag-state): como root,
#      _relatorio/ e _rejeitados/ nasceriam de root dentro do share;
#   2. flock -n: um lote grande passa dos 15 min (16 PDFs = 9m45s); a execução
#      seguinte não pode atropelar a anterior — ela registra "skip" e sai;
#   3. tudo vai para ~/rag-state/cron.log (o worker já escreve o ingest.log).
#
# Uso:
#   rag-ingest                # ingere o que é novo
#   rag-ingest --dry-run      # só mostra o que faria; não escreve nada
#   rag-ingest --remover SHA  # remove um documento (decisão explícita)
#   rag-ingest --retentar     # tenta de novo o que está em estado falhou
# =============================================================================
set -uo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=${HOME:-/home/tlandskron}

REPO=${HERMES_REPO:-/home/tlandskron/hermes-architect}
WORKER="$REPO/tools/rag_ingest.py"
STATE=${RAG_STATE:-/home/tlandskron/rag-state}
LOG="$STATE/cron.log"
LOCK="$STATE/ingest.lock"

# Chamado à mão como root? refaz como o dono do share (senão os arquivos de
# _rejeitados/ e _relatorio/ saem com dono root e o usuário não consegue mexer).
if [ "$(id -u)" = "0" ]; then
  exec sudo -u tlandskron -- "$0" "$@"
fi

mkdir -p "$STATE"

if [ ! -f "$WORKER" ]; then
  echo "ERRO: worker ausente em $WORKER (rode ops/deploy/sync-to-host.ps1)" >&2
  exit 2
fi

exec 9>"$LOCK" || exit 2
if ! flock -n 9; then
  echo "$(date +%Y-%m-%dT%H:%M:%S%:z)  [skip] execução anterior ainda rodando (lock)" >>"$LOG"
  exit 0
fi

# cron.log não pode crescer sem limite (roda 96x por dia)
if [ -f "$LOG" ] && [ "$(stat -c %s "$LOG" 2>/dev/null || echo 0)" -gt 5242880 ]; then
  mv -f "$LOG" "$LOG.1"
fi

echo "$(date +%Y-%m-%dT%H:%M:%S%:z)  == rag-ingest ${*:-(cron)}" >>"$LOG"
# Chamado à mão (terminal): a saída tem de aparecer. No cron não existe terminal,
# então vai só para o log — antes o `--dry-run` no SSH não mostrava nada.
if [ -t 1 ]; then
  python3 "$WORKER" "$@" 2>&1 | tee -a "$LOG"
  rc=${PIPESTATUS[0]}
else
  python3 "$WORKER" "$@" >>"$LOG" 2>&1
  rc=$?
fi
echo "$(date +%Y-%m-%dT%H:%M:%S%:z)  == fim rc=$rc" >>"$LOG"
exit $rc
