# cadvisor — métricas por container

| | |
|---|---|
| Imagem | `gcr.io/cadvisor/cadvisor@sha256:3de2bd52…` (v0.55.1) |
| Porta | **nenhuma publicada** (só rede interna, `:8080`) |
| Mounts | `/`, `/var/run`, `/sys`, `/var/lib/docker` (somente leitura) |
| Papel | CPU/RAM/rede por container, para os painéis do Grafana |

## Verificar

```bash
docker inspect -f '{{.State.Health.Status}}' cadvisor
docker exec prometheus wget -qO- 'http://cadvisor:8080/metrics' | head -c 200
docker exec prometheus wget -qO- 'http://cadvisor:8080/api/v1.3/containers' | head -c 200
```

## Sintomas típicos

- **`/metrics` vazio ou 500** → o cgroup do host mudou de versão (v1/v2) ou o container perdeu um
  dos mounts. `docker logs cadvisor | grep -i error`.
- **Só aparece o próprio cadvisor** → `/var/lib/docker` não está montado (ou está montado em
  caminho diferente, ex.: `/snap/docker`).
- **Painel do Grafana sem dados e alvo `up`** → consulta com label errada; confira em
  `Status → Targets` qual jobs está publicando.

> cadvisor é **leitura**: não interfere em nada. Se ele cair, o lab continua funcionando; só os
> painéis de container ficam sem dados.
