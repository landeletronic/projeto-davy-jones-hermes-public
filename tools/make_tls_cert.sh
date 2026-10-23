#!/usr/bin/env bash
# =============================================================================
# make_tls_cert.sh — cria ou RENOVA o certificado autoassinado do nginx.
#
# O certificado do lab é autoassinado (SAN com os hostnames + IP da LAN). Nada
# externo renova: ou este script roda, ou o HTTPS quebra no vencimento.
#
# Regras de segurança:
#   - sem --force e com um par válido, NÃO sobrescreve (renovar é decisão);
#   - ao renovar, guarda o par antigo (server.crt.bak-<data>) para poder voltar;
#   - a chave é sempre nova (não reaproveita material antigo);
#   - --reload só recarrega o nginx quando o destino é o de produção.
#
# Uso:
#   tools/make_tls_cert.sh                        # cria se não existir (825 dias)
#   tools/make_tls_cert.sh --force --reload       # renova agora e recarrega o nginx
#   tools/make_tls_cert.sh --renew-if-days 30     # renova só se faltar <= 30 dias
#   tools/make_tls_cert.sh --days 365 --out /var/tmp/teste
#   tools/make_tls_cert.sh --ip 192.168.15.231 --san "DNS:extra.lab"
#
# Depois de renovar: recarregue o nginx (--reload). O navegador volta a avisar
# "não confiável" se o certificado antigo estava importado na máquina.
# =============================================================================
set -euo pipefail

PROD_DIR=/home/usuario/hermes-architect/nginx/certs
DIR="$PROD_DIR"
DAYS=825
FORCE=0
RELOAD=0
RENEW_IF=0
CN=hermes-lab
EXTRA_SAN=""
IP=""

while [ $# -gt 0 ]; do
  case "$1" in
    --days)          DAYS="${2:?--days precisa de valor}"; shift 2 ;;
    --out)           DIR="${2:?--out precisa de valor}"; shift 2 ;;
    --cn)            CN="${2:?--cn precisa de valor}"; shift 2 ;;
    --ip)            IP="${2:?--ip precisa de valor}"; shift 2 ;;
    --san)           EXTRA_SAN="${2:?--san precisa de valor}"; shift 2 ;;
    --force)         FORCE=1; shift ;;
    --reload)        RELOAD=1; shift ;;
    --renew-if-days) RENEW_IF="${2:?--renew-if-days precisa de valor}"; shift 2 ;;
    -h|--help)       sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "arg desconhecido: $1" >&2; exit 2 ;;
  esac
done

mkdir -p "$DIR"
CRT="$DIR/server.crt"
KEY="$DIR/server.key"

# IP da LAN: o da rota default (não o primeiro de `hostname -I`, que pode ser
# uma bridge do Docker). `--ip` manda.
if [ -z "$IP" ]; then
  IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')
fi
[ -n "$IP" ] || IP=$(hostname -I 2>/dev/null | awk '{print $1}')
SAN="DNS:hermes-lab,DNS:davy-jones-hermes"
[ "$CN" != "hermes-lab" ] && SAN="$SAN,DNS:$CN"
[ -n "$IP" ] && SAN="$SAN,IP:$IP"
[ -n "$EXTRA_SAN" ] && SAN="$SAN,$EXTRA_SAN"

if [ -f "$CRT" ] && [ -f "$KEY" ] && [ "$FORCE" = "0" ]; then
  if [ "$RENEW_IF" -gt 0 ] && ! openssl x509 -in "$CRT" -noout -checkend $((RENEW_IF * 86400)) >/dev/null 2>&1; then
    FORCE=1   # dentro da janela de renovação: segue
  else
    echo "nada a fazer: $CRT já existe e está válido (use --force para renovar)"
    openssl x509 -in "$CRT" -noout -subject -dates -ext subjectAltName
    exit 0
  fi
fi

# Renovação: guarda o par antigo (nunca sobrescreve sem cópia).
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
if [ -f "$CRT" ] || [ -f "$KEY" ]; then
  [ -f "$CRT" ] && cp -p "$CRT" "$CRT.bak-$STAMP"
  [ -f "$KEY" ] && cp -p "$KEY" "$KEY.bak-$STAMP"
  chmod 600 "$KEY.bak-$STAMP" 2>/dev/null || true
  echo "par antigo guardado em *.bak-$STAMP"
fi

umask 077
# stderr do openssl traz o progresso da chave (..+....+): só mostramos em caso de erro.
if ! err=$(openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days "$DAYS" \
      -keyout "$KEY" -out "$CRT" \
      -subj "/C=BR/O=Hermes Lab/CN=$CN" \
      -addext "subjectAltName=$SAN" 2>&1 >/dev/null); then
  echo "ERRO ao gerar o certificado:" >&2
  echo "$err" >&2
  exit 1
fi
chmod 600 "$KEY"
chmod 644 "$CRT"

echo "certificado gravado: $CRT ($DAYS dias)"
openssl x509 -in "$CRT" -noout -subject -dates -ext subjectAltName
echo "sha256: $(openssl x509 -in "$CRT" -noout -fingerprint -sha256 | cut -d= -f2)"

if [ "$RELOAD" = "1" ]; then
  if [ "$DIR" != "$PROD_DIR" ]; then
    echo "AVISO: --reload ignorado (destino não é o de produção)" >&2
  elif docker exec nginx nginx -s reload >/dev/null 2>&1; then
    echo "nginx recarregado"
    # confere que o que está no ar é o arquivo novo (pega reload que não pegou)
    sleep 1
    served=$(echo | openssl s_client -connect 127.0.0.1:443 -servername "$CN" 2>/dev/null \
             | openssl x509 -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
    local_fp=$(openssl x509 -in "$CRT" -noout -fingerprint -sha256 | cut -d= -f2)
    if [ -n "$served" ] && [ "$served" = "$local_fp" ]; then
      echo "nginx serve o certificado novo (fingerprint confere)"
    else
      echo "ERRO: nginx NÃO está servindo o certificado novo — reinicie o container" >&2
      exit 1
    fi
  else
    echo "ERRO: falha ao recarregar o nginx" >&2
    exit 1
  fi
fi
