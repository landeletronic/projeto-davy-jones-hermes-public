# node-exporter — métricas do host + ponte do textfile

| | |
|---|---|
| Imagem | `prom/node-exporter@sha256:1b4e4438…` (v1.12.1) |
| Porta | **nenhuma publicada** (só rede interna, `:9100`) |
| Extra | `--collector.textfile.directory` apontando para `ci/textfile` (bind-mount) |
| Papel | CPU/RAM/disco/load do host **e** publicar as métricas de script |

## Verificar

```bash
docker inspect -f '{{.State.Health.Status}}' node-exporter
curl -s localhost:9100/metrics | head -c 200                       # se publicado; normalmente via prometheus
docker exec prometheus wget -qO- 'http://node-exporter:9100/metrics' \
  | grep -E '^hermes_(backup|mem0|tls|ci)_' | head
ls -l /home/tlandskron/hermes-architect/ci/textfile/
```

## Como o textfile funciona

Cada script escreve um `.prom` atômico (escreve em `.tmp` e renomeia) no diretório `ci/textfile`:
`hermes_backup`, `hermes_mem0`, `hermes_tls`, `hermes_ci`. O exporter só **lê** — se o `.prom`
não existe, a métrica não existe (e o alerta "métrica ausente" dispara de propósito).

## Sintomas típicos

- **`hermes_ci_*` sumiu** → o `hermes-ci` falhou antes de publicar, ou o `ci/textfile` perdeu
  permissão. O arquivo tem de ser legível pelo processo do exporter.
- **Disco do host errado** → o container monta `/` do host em `/host`; o alerta de disco >85%
  usa o mountpoint do host.
- **Métrica duplicada** → dois scripts escrevendo o mesmo `.prom`. Use nomes distintos.
- **Alerta de backup >48h** → veja `hermes_backup_last_success_timestamp_seconds`; o artefato em
  `~/backups` é a fonte (`hermes-backup --prune-dry-run` mostra a política).
