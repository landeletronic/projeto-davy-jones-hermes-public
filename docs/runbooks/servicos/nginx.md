# nginx — TLS e proxy reverso (é o que a LAN enxerga)

| | |
|---|---|
| Imagem | `nginx@sha256:892bb215…` (1.31.7-alpine) |
| Portas | `80` (redireciona para HTTPS), `443` (OWUI), `3001` (Grafana) |
| Config | `nginx/conf.d/` (versionada no repo, copiada pelo sync) |
| Certificado | `nginx/certs/server.crt` + `server.key` (autoassinado, SAN com os 2 hostnames) |
| Rede | precisa estar na `backend` para falar `open-webui:8080` e `grafana:3000` |

## Verificar

```bash
docker inspect -f '{{.State.Health.Status}}' nginx                    # healthy
curl -sk -o /dev/null -w '%{http_code}\n' https://192.168.15.231/       # 200
curl -sk -o /dev/null -w '%{http_code}\n' https://192.168.15.231:3001/  # 200
echo | openssl s_client -connect 192.168.15.231:443 2>/dev/null \
  | openssl x509 -noout -fingerprint -sha256          # = fingerprint do arquivo
nginx -t                                                              # dentro do container
```

O fingerprint acima é o check que pega o caso "renovei o `.crt` mas o nginx serve o antigo".

## Reiniciar / recarregar

```bash
docker compose restart nginx                  # troca de config
docker exec nginx nginx -s reload             # só recarrega o certificado
```

## Sintomas típicos

- **Navegador avisa "não seguro"** → é autoassinado. Depois de uma **renovação** o aviso volta
  para quem importou o antigo: é esperado (por isso a renovação é manual, alertada aos 30 dias).
- **502 Bad Gateway** → o upstream está fora. `docker logs --tail 30 nginx` diz qual
  (`open-webui` ou `grafana`).
- **Grafana não abre na 3001 mas abre dentro do container** → falta o nginx na rede `backend`,
  ou o Grafana subiu como uid 472 sem permissão em `monitoring/`.
- **Loop de redirect** → o `:80` só pode redirecionar; confira `X-Forwarded-Proto` no proxy.

## Renovar o certificado

```bash
ssh davy-jones-hermes 'bash /home/tlandskron/hermes-architect/tools/make_tls_cert.sh --force --reload'
```

Depois: reimporte o certificado nas máquinas da LAN e confirme o fingerprint servido.
