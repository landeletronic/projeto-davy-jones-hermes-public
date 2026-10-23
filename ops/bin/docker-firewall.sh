#!/bin/bash
# =============================================================================
# docker-firewall.sh — regras DOCKER-USER do lab davy-jones-hermes.
#
# POR QUE ESTE ARQUIVO EXISTE
#   O Docker publica portas via PREROUTING -> FORWARD -> DOCKER-USER, então o
#   tráfego para portas publicadas NÃO passa pelo INPUT do ufw. Sem regra nesta
#   cadeia, "fechei o firewall" não fecha nada. A cadeia DOCKER-USER é recriada
#   a cada restart do Docker, por isso o docker-firewall.service reaplica.
#
# O QUE BLOQUEIA
#   6333  Qdrant  — só os containers precisam
#   11434 Ollama  — só os containers precisam
#   8642  Hermes  — API com chave ESTÁTICA (sem auth por pessoa): só o OWUI
#                   (rede docker interna) precisa. O host continua acessando
#                   por 127.0.0.1 (tráfego do host não passa por FORWARD).
#   (SSH/OWUI/Grafana/dashboard continuam liberados — 80/443/3001/9119)
#
# ARMADILHA: `ufw allow 8642` NÃO abre nem fecha porta publicada pelo Docker —
# esse tráfego entra por FORWARD/DOCKER-USER, nunca por INPUT. Quem manda aqui é
# esta cadeia; o ufw-lab.sh cuida só do que é INPUT de verdade.
#
# Idempotente: pode rodar quantas vezes quiser (remove e reinsere).
# Instalado por ops/deploy/sync-to-host.ps1 em /usr/local/bin/docker-firewall.sh.
# =============================================================================
set -u

BLOCKED="6333 11434 8642"

if ! iptables -L DOCKER-USER -n >/dev/null 2>&1; then
  echo "[docker-firewall] ERRO: cadeia DOCKER-USER ausente (docker parado?)" >&2
  exit 1
fi

rc=0
for p in $BLOCKED; do
  iptables -D DOCKER-USER -p tcp --dport "$p" -j DROP 2>/dev/null || true
  iptables -I DOCKER-USER -p tcp --dport "$p" -j DROP || rc=1
done

echo "[docker-firewall] portas bloqueadas da LAN: $BLOCKED"
exit "$rc"
