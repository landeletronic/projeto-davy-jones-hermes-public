# prometheus — coleta e avaliação dos alertas

| | |
|---|---|
| Imagem | `prom/prometheus@sha256:efd719c9…` (v3.15.0) |
| Porta | **nenhuma publicada** (só rede interna, `:9090`) |
| Config | `monitoring/prometheus.yml` + `monitoring/alert-rules.yml` (bind-mount, versionados) |
| Métricas próprias | `hermes_backup_*`, `hermes_mem0_*`, `hermes_tls_*`, `hermes_ci_*` via textfile |

## Verificar

```bash
docker inspect -f '{{.State.Health.Status}}' prometheus      # healthy
docker exec prometheus promtool check config /etc/prometheus/prometheus.yml
# alvos no ar (esperado: >= 4)
docker exec prometheus wget -qO- 'http://127.0.0.1:9090/api/v1/targets?state=active' | head -c 400
# regras carregadas x arquivo (tem de bater)
docker exec prometheus wget -qO- 'http://127.0.0.1:9090/api/v1/rules' | grep -c '"name"'
docker exec prometheus sh -c 'grep -c "alert:" /etc/prometheus/alert-rules.yml'
# alertas disparando
docker exec prometheus wget -qO- 'http://127.0.0.1:9090/api/v1/alerts' | head -c 300
```

## Recarregar (o detalhe que morde)

```bash
docker kill -s HUP prometheus     # relê prometheus.yml e alert-rules.yml
```

**Regra nova não aparece sem isso**: o Prometheus só lê os arquivos no start ou em SIGHUP. O
`sync-to-host.ps1` já manda o HUP; se você editou à mão, mande você.

Mudou **bind-mount** (novo arquivo/diretório)? Aí não basta HUP: `docker compose up -d prometheus`.

## Sintomas típicos

- **Alvo `down`** → o serviço alvo caiu ou mudou de porta; veja `Status → Targets` (via túnel SSH)
  ou a API `/api/v1/targets`.
- **`hermes_backup_*` ausente** → o node-exporter não está lendo o diretório `ci/textfile`, ou o
  runner não escreveu. Sem a métrica, o alerta de "backup ausente" dispara.
- **Total de regras menor que o arquivo** → ninguém mandou HUP depois do deploy.
- **Alerta disparado** → é **WARN** na suíte, não FAIL: é estado do ambiente, não regressão.
