#!/bin/bash
# =============================================================================
# ufw-lab.sh — política de exposição do lab davy-jones-hermes (idempotente).
#
# O que este script NÃO faz: `ufw reset`. Um reset apagaria regras que não são
# do lab; aqui só garantimos as regras esperadas, uma a uma.
#
# O QUE O UFW **NÃO** COBRE: portas publicadas pelo Docker (entram por FORWARD
# -> DOCKER-USER, nunca por INPUT). Isso é papel do ops/bin/docker-firewall.sh.
#
# Instalado por ops/deploy/sync-to-host.ps1 em /usr/local/bin/ufw-lab.sh.
# =============================================================================
set -eu

# porta:comentário, separados por | (os comentários têm espaços — não dividir em
# palavras, senão "Nginx HTTP" vira duas regras e o ufw acusa "Bad port").
#
# 8642 (Hermes API) NÃO entra aqui: porta publicada pelo Docker não passa pelo
# INPUT do ufw — quem a controla é a cadeia DOCKER-USER (ops/bin/docker-firewall.sh),
# que a bloqueia para a LAN. Aqui só ficam portas de INPUT (SSH) e as que devem
# mesmo ficar alcançáveis (80/443/3001/9119, com auth).
WANT="22:SSH|80:Nginx HTTP|443:Nginx HTTPS|3001:Grafana TLS|9119:Hermes dashboard"

ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null

# Regra antiga (quando se acreditava que o ufw governava portas do Docker):
# remove para não deixar a impressão de que a API está liberada na LAN.
if ufw status | grep -qE '^8642/tcp +ALLOW'; then
  ufw delete allow 8642/tcp >/dev/null 2>&1 || true
fi

OLDIFS=$IFS
IFS='|'
for item in $WANT; do
  port="${item%%:*}"
  label="${item#*:}"
  ufw allow "${port}/tcp" comment "$label" >/dev/null
done
IFS=$OLDIFS

# SMB (share "documentos"): 445 é INPUT de verdade, mas NÃO pode ser "Anywhere".
# O acesso é do lab, então a regra é restrita à sub-rede — e o smb.conf repete a
# restrição em `hosts allow` (duas camadas). Fora da sub-rede, nem chega no smbd.
ufw allow from 192.168.15.0/24 to any port 445 proto tcp comment "SMB documentos (LAN)" >/dev/null

# `enable` é idempotente: não derruba conexões existentes (o 22 já está liberado).
ufw --force enable >/dev/null

echo "[ufw-lab] política aplicada:"
ufw status | sed -n '1,14p' | sed 's/^/  /'
