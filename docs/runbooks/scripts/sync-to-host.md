# sync-to-host.ps1 — deploy do repo Windows → host

| | |
|---|---|
| Arquivo | `ops/deploy/sync-to-host.ps1` |
| Roda em | **Windows**, à mão |
| Transporte | espelha o repo para `davy-jones-hermes:/home/tlandskron/hermes-architect` |
| Termina com | CI (`hermes-ci --quiet`) |

## O que ele faz, em ordem

1. espelha a árvore (inclui `docs/`, `tests/`, `ops/`, `monitoring/`, `nginx/`, `hermes-data/`);
2. confere o **sha256 da suíte** no destino;
3. aplica permissões (`chmod -R a+rX monitoring` — o Grafana é uid 472);
4. instala scripts em `/usr/local/bin`, entradas em `/etc/cron.d` e units em `/etc/systemd/system`;
5. copia `daemon.json` (se mudou, reinicia o Docker) e reinstala o firewall;
6. copia `searxng/settings.yml` via `/tmp` + `sudo install` (diretório é do uid 977);
7. instala `hermes-data/config.yaml` em `~/.hermes/` e reinicia o gateway quando muda;
8. manda **SIGHUP** ao Prometheus (regras novas só são lidas assim);
9. roda o CI e reporta.

Cada bloco remoto é verificado com `Assert-Ok`: `ssh` chamado do PowerShell **não** propaga exit
code sozinho, então sem isso uma instalação falha passa batido.

## O que ele NÃO faz

- **não** aplica `docker compose`. Mudou compose/volume/bind-mount?
  ```bash
  ssh davy-jones-hermes 'cd /home/tlandskron/hermes-architect && docker compose up -d <serviço>'
  ```
- não apaga nada em `_legacy/` nem em `~/backups`.

## Se falhar

| Sintoma | Causa | Ação |
|---|---|---|
| termina "ok" mas nada mudou | bloco remoto falhou em silêncio | rodar com saída verbosa; conferir `Assert-Ok` |
| acentos quebrados em script `.ps1` | arquivo sem BOM UTF-8 | salvar como UTF-8 com BOM |
| CI valida código velho | o cron usa a cópia sincronizada | este script é obrigatório após mudar `tests/` |
| Grafana sem dashboards | permissão de `monitoring/` | `chmod -R a+rX monitoring` (o script faz) |

## Uso

```powershell
powershell -File ops\deploy\sync-to-host.ps1
```
