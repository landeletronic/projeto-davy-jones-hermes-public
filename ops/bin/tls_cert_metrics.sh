#!/usr/bin/env bash
# =============================================================================
# tls_cert_metrics.sh — publica a validade do certificado do nginx no textfile.
#
# Sem isso, o vencimento (2029) só apareceria no dia em que o HTTPS quebrasse.
# Lê o ARQUIVO (não a rede): o alerta é sobre o que será servido no próximo
# reload, e o check de fingerprint da suíte cobre a divergência arquivo x nginx.
#
# Métricas (hermes_tls_cert_*):
#   expiry_timestamp_seconds   epoch do notAfter
#   not_before_timestamp_seconds
#   days_left                  dias inteiros até expirar (pode ser negativo)
#   last_check_timestamp_seconds
#
# Uso: tls_cert_metrics.sh [caminho/do/server.crt]
# Cron: /etc/cron.d/tls-cert (03:20, antes do backup das 03:30)
# =============================================================================
set -uo pipefail

CRT="${1:-${TLS_CRT:-/home/tlandskron/hermes-architect/nginx/certs/server.crt}}"
TEXTFILE="${TLS_TEXTFILE:-/home/tlandskron/hermes-architect/ci/textfile}"

if [ ! -f "$CRT" ]; then
  echo "tls_cert_metrics: certificado ausente: $CRT" >&2
  exit 2
fi
if ! command -v openssl >/dev/null 2>&1; then
  echo "tls_cert_metrics: openssl não encontrado" >&2
  exit 2
fi

end=$(openssl x509 -in "$CRT" -noout -enddate 2>/dev/null | cut -d= -f2)
start=$(openssl x509 -in "$CRT" -noout -startdate 2>/dev/null | cut -d= -f2)
if [ -z "$end" ] || [ -z "$start" ]; then
  echo "tls_cert_metrics: não consegui ler as datas de $CRT" >&2
  exit 2
fi

end_ts=$(date -u -d "$end" +%s)
start_ts=$(date -u -d "$start" +%s)
now=$(date -u +%s)
days_left=$(( (end_ts - now) / 86400 ))

mkdir -p "$TEXTFILE"
out="$TEXTFILE/hermes_tls.prom"
tmp="$out.tmp.$$"
{
  echo '# HELP hermes_tls_cert_expiry_timestamp_seconds Epoch do notAfter do certificado do nginx'
  echo '# TYPE hermes_tls_cert_expiry_timestamp_seconds gauge'
  echo "hermes_tls_cert_expiry_timestamp_seconds $end_ts"
  echo '# HELP hermes_tls_cert_not_before_timestamp_seconds Epoch do notBefore'
  echo '# TYPE hermes_tls_cert_not_before_timestamp_seconds gauge'
  echo "hermes_tls_cert_not_before_timestamp_seconds $start_ts"
  echo '# HELP hermes_tls_cert_days_left Dias inteiros até o certificado expirar'
  echo '# TYPE hermes_tls_cert_days_left gauge'
  echo "hermes_tls_cert_days_left $days_left"
  echo '# HELP hermes_tls_cert_last_check_timestamp_seconds Epoch da última checagem'
  echo '# TYPE hermes_tls_cert_last_check_timestamp_seconds gauge'
  echo "hermes_tls_cert_last_check_timestamp_seconds $now"
} > "$tmp"
chmod 644 "$tmp"
mv "$tmp" "$out"

echo "tls: $CRT expira em $end ($days_left dias)"
