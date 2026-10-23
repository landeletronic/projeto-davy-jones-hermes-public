#!/usr/bin/env bash
# =============================================================================
# ci_run.sh — roda o ORÁCULO (tests/verify_stack.sh) e publica o resultado.
#
# Faz:
#   1. executa a suíte de regressão no host
#   2. grava log completo em ~/ci/logs/ci-<UTC>.log (+ ~/ci/last.log)
#   3. grava um resumo legível por máquina em ~/ci/last-run.json
#   4. publica métricas hermes_ci_* no textfile do node-exporter → Prometheus/Grafana
#
# Instalado em /usr/local/bin/hermes-ci (cron diário, ver /etc/cron.d/hermes-ci).
# Exit code = exit code da suíte (0 = tudo verde).
#
# Uso:  hermes-ci            (roda e publica)
#       hermes-ci --quiet    (só a última linha)
# =============================================================================
set -uo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

REPO=${HERMES_REPO:-/home/usuario/hermes-architect}
SUITE="$REPO/tests/verify_stack.sh"
CI_DIR=/home/usuario/ci
LOG_DIR="$CI_DIR/logs"
TEXTFILE_DIR="$REPO/ci/textfile"
KEEP_LOGS=30
QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

mkdir -p "$CI_DIR" "$LOG_DIR" "$TEXTFILE_DIR" 2>/dev/null

TS=$(date -u +%Y%m%dT%H%M%SZ)
LOG="$LOG_DIR/ci-$TS.log"

if [ ! -f "$SUITE" ]; then
  echo "ERRO: suíte não encontrada em $SUITE (rode ops/deploy/sync-to-host.ps1)" | tee "$LOG" >&2
  exit 2
fi

SHA=$(sha256sum "$SUITE" | cut -d' ' -f1)
START=$(date +%s)

bash "$SUITE" > "$LOG" 2>&1
RC=$?

END=$(date +%s)
DUR=$((END - START))

PASS=$(grep -oE 'PASS=[0-9]+' "$LOG" | head -1 | cut -d= -f2); PASS=${PASS:-0}
FAIL=$(grep -oE 'FAIL=[0-9]+' "$LOG" | head -1 | cut -d= -f2); FAIL=${FAIL:-0}
WARN=$(grep -oE 'WARN=[0-9]+' "$LOG" | head -1 | cut -d= -f2); WARN=${WARN:-0}
if [ "$RC" -eq 0 ]; then OK=1; else OK=0; fi

cat > "$CI_DIR/last-run.json" <<JSON
{
  "timestamp_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "success": $([ "$OK" -eq 1 ] && echo true || echo false),
  "exit_code": $RC,
  "pass": $PASS,
  "fail": $FAIL,
  "warn": $WARN,
  "duration_seconds": $DUR,
  "suite_sha256": "$SHA",
  "log": "$LOG"
}
JSON

# métricas para o Prometheus (textfile collector do node-exporter)
TMP="$TEXTFILE_DIR/hermes_ci.prom.tmp"
{
  echo '# HELP hermes_ci_last_run_success Última execução do oráculo (1=verde, 0=vermelho)'
  echo '# TYPE hermes_ci_last_run_success gauge'
  echo "hermes_ci_last_run_success $OK"
  echo '# HELP hermes_ci_last_run_timestamp_seconds Timestamp (epoch) da última execução'
  echo '# TYPE hermes_ci_last_run_timestamp_seconds gauge'
  echo "hermes_ci_last_run_timestamp_seconds $(date +%s)"
  echo '# HELP hermes_ci_duration_seconds Duração da última execução'
  echo '# TYPE hermes_ci_duration_seconds gauge'
  echo "hermes_ci_duration_seconds $DUR"
  echo '# HELP hermes_ci_checks_total Checks executados'
  echo '# TYPE hermes_ci_checks_total gauge'
  echo "hermes_ci_checks_total $((PASS + FAIL))"
  echo '# HELP hermes_ci_checks_failed Checks com falha'
  echo '# TYPE hermes_ci_checks_failed gauge'
  echo "hermes_ci_checks_failed $FAIL"
  echo '# HELP hermes_ci_checks_warned Checks em aviso (não derrubam o CI)'
  echo '# TYPE hermes_ci_checks_warned gauge'
  echo "hermes_ci_checks_warned $WARN"
  echo '# HELP hermes_ci_suite_info Hash da suíte executada'
  echo '# TYPE hermes_ci_suite_info gauge'
  echo "hermes_ci_suite_info{sha256=\"$SHA\"} 1"
} > "$TMP"
mv -f "$TMP" "$TEXTFILE_DIR/hermes_ci.prom"

# histórico: mantém os N logs mais recentes
ls -1t "$LOG_DIR"/ci-*.log 2>/dev/null | tail -n +$((KEEP_LOGS + 1)) | xargs -r rm -f
ln -sfn "logs/$(basename "$LOG")" "$CI_DIR/last.log"

if [ "$QUIET" -eq 1 ]; then
  echo "CI $( [ "$OK" -eq 1 ] && echo OK || echo FALHOU ): PASS=$PASS FAIL=$FAIL WARN=$WARN em ${DUR}s"
else
  echo "=== CI $( [ "$OK" -eq 1 ] && echo OK || echo FALHOU ) ==="
  echo "PASS=$PASS FAIL=$FAIL WARN=$WARN duração=${DUR}s suíte=${SHA:0:12}"
  echo "log: $LOG"
  echo "json: $CI_DIR/last-run.json"
  grep -E '^  FAIL' "$LOG" 2>/dev/null || true
  grep -E '^  WARN' "$LOG" 2>/dev/null || true
fi
exit $RC
