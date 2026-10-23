# Diretórios do Host Medusa
## Inventário, função e criticidade de cada pasta do projeto

| Campo | Valor |
|---|---|
| **Documento** | `DIRETORIOS-HOST-MEDUSA-2026-10-20.md` |
| **Host** | `medusa` — Ubuntu 26.04.1 LTS, kernel 7.0.0-38 |
| **Escopo** | Diretórios do projeto Medusa / Davy-Jones no host |
| **Data da coleta** | 20/10/2026, 18:00–18:15 (-03:00) |
| **Método** | Inspeção somente leitura via SSH (`ls`, `find`, `du`, `stat`, `systemctl --user cat`, `docker inspect`) |
| **Conta operadora** | `usuario` (UID 1000), com *lingering* de systemd habilitado |
| **Armazenamento** | 735 GB no volume raiz, 79 GB usados (**12%**), 619 GB livres |
| **Segredos** | Nenhum token, senha ou chave é reproduzido neste documento |

---

## 1. Resumo executivo

O host Medusa não usa uma árvore de instalação tradicional (`/opt`, `/srv`, `/etc/medusa`).
**Todo o projeto vive no home do operador**, com dados de containers em `/var/lib/docker/volumes`.
São quatro camadas bem separadas:

| Camada | Onde está | Peso aproximado |
|---|---|---|
| **Aplicação** | `~/medusa`, `~/davy-jones` | 3,8 GB (3,0 GB são backups) |
| **Infraestrutura** | `~/infra-postgres`, `~/infra-redis`, `~/observability`, volumes Docker | ~29,4 GB (29 GB são modelos Ollama) |
| **Operação e evidências** | `~/log`, `~/txt`, `~/script`, `~/backups`, `~/.local/state` | ~1,4 GB |
| **Legado** | `~/medusa-ael`, `~/old`, `~/.hermes`, `~/.codex` | ~5,7 GB |

Números-chave da coleta:

- **3,0 GB** em `~/medusa/backups` — 31 backups operacionais completos + 1 diretório legado.
- **29 GB** em `/var/lib/docker/volumes/u0137-ollama_u0137_ollama_models` (modelos locais).
- **38 execuções** de experimentos M4.x/M5.x preservadas em `~/medusa/data` (126 MB).
- **5 revisões** imutáveis de workspace em `~/medusa/workspace/revisions`.
- **360 scripts** em `~/script`, **736 arquivos** em `~/log`, **611 relatórios** em `~/txt`.

O ponto mais relevante para manutenção: **a aplicação é pequena; o histórico é que ocupa espaço**. Código, configuração e documentos somam menos de 250 MB. Backups (3,0 GB), modelos (29 GB) e diretórios legados (`.codex`, `.hermes`, `old`, `medusa-ael`) concentram o consumo e são justamente os que não têm política de retenção automatizada.

---

## 2. Legenda

Tamanhos medidos com `du -sh` (inclui subdiretórios, links não seguidos). Criticidade:

| Símbolo | Significado |
|---|---|
| 🔴 | **Produção** — se sumir ou corromper, o serviço para ou perde prova |
| 🟠 | **Operacional** — necessário para operar, recuperar ou auditar |
| 🟡 | **Histórico** — evidência de etapas concluídas; consulta, não operação |
| ⚪ | **Legado** — substituído; pode ser arquivado após revisão |

---

## 3. Mapa geral do home

```
/home/usuario/
├── medusa/                      3,4G  🔴  Aplicação de recuperação de evidências
├── davy-jones/                  432M  🔴  Administração, filas e interface
├── observability/                80K  🟠  Prometheus + Grafana + node-exporter
├── infra-postgres/              4,0K  🟠  Compose e init do PostgreSQL/pgvector
├── infra-redis/                  84K  🟠  Compose, ACL e segredos do Redis
├── backups/                      60K  🟠  Snapshots de rollback (root)
├── log/                         194M  🟠  Logs e trilhas de atividade
├── txt/                          19M  🟡  Relatórios e estados JSON
├── script/                      5,1M  🟡  Scripts de implantação e experimentos
├── medusa-ael/                   79M  ⚪  Laboratório de agentes (encerrado)
├── old/                         344K  ⚪  Backups antigos de configuração
├── codex-migration-backup/       28K  ⚪  Migração do Codex (01/10)
├── medusa-davy-jones-autonomous/ 32K  ⚪  Execução autônoma única (01/10)
├── .config/                     132K  🔴  Units systemd, Caddy, backup remoto
├── .local/                      1,3G  🟠  Staging de replicação, Caddy, TLS, venv
├── .hermes/                     2,5G  ⚪  Runtime Hermes histórico
├── .codex/                      3,1G  ⚪  Runtime Codex histórico
└── .mem0/                        92K  🟠  Estado local do SDK Mem0
```

Volumes Docker fora do home (seção 5.5):

```
/var/lib/docker/volumes/
├── u0137-ollama_u0137_ollama_models/   29G
├── observability_prometheus_data/     232M
├── infra_postgres_data/                72M
├── qdrant_data/                        55M
├── observability_grafana_data/         50M
└── infra_redis_data/                   20K
```

---

## 4. Núcleo da aplicação

### 4.1 `~/medusa` — 3,4 GB 🔴

É o domínio de evidência jurídica: corpus canônico, ingestão incremental, índice vetorial e serviço de consulta. O `medusa-core.service` serve em `127.0.0.1:8765`.

| Subdiretório | Tam. | Dono | Função |
|---|---:|---|---|
| `core/` | 188K | usuario | Código do serviço `medusa_core` + testes |
| `config/` | 8K | usuario | `core.json` — coleção, modelo, dimensão, SHA do corpus |
| `compose/` | 8K | usuario | Compose do Docling Serve (GPU, porta 5001) |
| `documents/` | 12M | usuario | Inbox e arquivos de origem do fluxo de ingestão |
| `workspace/` | 14M | usuario | Registro publicado e revisões imutáveis |
| `rag-worker/` | 148K | usuario | Fila durável de ingestão (SQLite + thread única) |
| `searxng/` | 216K | usuario | Busca web interna (porta 8081) |
| `docling/` | 31M | usuario | Modelos OCR e scratch do conversor |
| `data/` | 126M | usuario | 38 execuções de experimentos M4.x/M5.x |
| `artifacts/` | 7,1M | **root** | Artefatos M5.11 / M5.12 (materialização e embeddings) |
| `recovery/` | 1,3M | usuario | Export pontual de recuperação (01/10) |
| `ops/` | 177M | usuario | `lab_ops.py`, verificação de browser, venv Playwright |
| `backups/` | **3,0G** | usuario | 31 backups operacionais completos |
| `logs/` | 8K | usuario | Reservado para Docling; vazio na prática |
| `scripts/` | 8K | usuario | `reset_password_usuario.py` (0600) |
| `README.md` | 4K | usuario | Visão geral e ponteiros para Core/Ops |

#### `core/` — o serviço de recuperação

- `medusa_core/` — pacote Python **somente biblioteca padrão**: servidor HTTP, recuperação, verificação de proveniência, drafts extrativos.
- `tests/` — testes do contrato de recuperação.
- `README.md` — contrato de API, limites legais e comandos (`medusa-core query`, `status`, `ingest`, `workspace-query`, `draft`).

Ele **não gera respostas jurídicas**: devolve trechos com citação e estado `REVIEW_REQUIRED` ou `ABSTAIN`. `generation_enabled` é sempre falso.

#### `config/` — contrato do índice canônico

Um único arquivo, `core.json` (432 bytes), com as chaves:
`backend_timeout_seconds`, `chunks_path`, `chunks_sha256`, `collection`, `embedding_model`, `expected_points`, `ollama_url`, `qdrant_url`, `vector_dimension`.

É o ponto que amarra o serviço ao corpus validado: alterar `expected_points`, `chunks_sha256` ou `vector_dimension` faz o `/ready` falhar de propósito (fail-closed).

#### `documents/` — o inbox controlado

| Pasta | Conteúdo atual | Função |
|---|---:|---|
| `incoming/` | 3 arquivos, 11M | **Único ponto de entrada** aceito pelo RAG Worker |
| `originals/` | 1 arquivo, 676K | Cópia do documento canônico de origem |
| `processed/` | vazio | Reservado para pós-processamento |
| `rejected/` | vazio | Rejeições explícitas |
| `temporary/` | vazio | Trabalho transitório |

Regras aplicadas pelo código: somente arquivo regular (symlink é rejeitado), PDF/TXT/Markdown, até 32 MiB e 5.000 chunks. Não há *watcher*: nada é ingerido sem solicitação explícita.

#### `workspace/` — revisões imutáveis

| Item | Função |
|---|---|
| `index.json` | Publicação corrente: quais revisões estão ativas |
| `index.previous.json` | Publicação anterior, para rollback lógico |
| `ingest.lock` | Serializa a ingestão (arquivo de lock) |
| `revisions/<sha256>/` | 5 revisões, cada uma com origem, extração, chunks e manifesto |

Cada revisão tem seu próprio collection Qdrant (`medusa_workspace_<revision>`). Nada é sobrescrito: uma nova versão do mesmo documento cria outra revisão. **Não existe coleta de lixo** — revisions antigas permanecem até remoção manual autorizada.

#### `rag-worker/` — a fila de ingestão

| Item | Função |
|---|---|
| `app/worker.py` | Servidor interno em `127.0.0.1:8767`; uma thread, um job por vez |
| `data/jobs.sqlite3` | Fila durável em WAL, até 100 ativos / 10.000 retidos |
| `data/worker.lock` | Garante instância única |
| `deploy/` | Unit systemd + `rollback-MEDUSA-DOC-RAG-01` |
| `tests/` | Testes do worker |

Fluxo: Davy-Jones → Worker → `medusa-core ingest` → Docling (PDF) → Ollama `qwen3-embedding:4b` (2560d) → Qdrant → publicação atômica.

#### `searxng/` — busca web isolada

`compose.yml`, `install.sh`, `verify.py`, `core-config/settings.yml` (0600) e `data/` (cache).
Publica apenas `127.0.0.1:8081`, roda como UID 1000, sem capabilities e com `no-new-privileges`.
Os JSONs `before-restart.json`, `after-restart.json`, `effective-container.json` e `effective-network.json` são **evidência de aceite**, não configuração.

#### `docling/` — conversão de PDF

| Pasta | Função |
|---|---|
| `models/RapidOcr/` | Pesos OCR persistidos (31 MB) |
| `scratch/` | Diretório de trabalho do Docling (montado em `/tmp/docling/scratch`) |

Sem esses modelos o container não converte PDF; sem o scratch ele não tem área de trabalho para a conversão.

#### `data/` — 126 MB de experimentos

38 diretórios de execução, um por rodada:

```
data/m4.3/20260922-213033/
├── input/          documento de teste
├── output/         document.md, document.json, response-body.raw
├── metadata/       metadados da rodada (r1, r2, r3a…)
└── raw_http_capture.txt
```

- `m4.3` a `m4.21` — pipeline de extração, tabelas, relações e verificadores de evidência.
- `m5.1` a `m5.7-r2` — representação estruturada, chunking, embeddings e validação de recuperação.
- Maiores: `m5.4` (53M) e `m5.5` (54M), com embeddings estruturados em JSON/JSONL.

É **histórico de pesquisa**, não caminho de produção. Nada em `data/` é lido pelo serviço em execução.

#### `artifacts/` — 7,1 MB, dono `root`

- `m5.11/c-flow-balanced/` — materialização do fluxo C balanceado.
- `m5.12/embeddings-2560/` — artefatos da validação de embeddings de 2560 dimensões.

São insumos congelados das etapas M5.11/M5.12. Pertencer a `root` é intencional (imutabilidade), mas isso significa que o operador **não os altera sem sudo**.

#### `recovery/` — 1,3 MB

`20261001T120853450836Z/` contém `chunks.jsonl`, `core.json`, `jobs.sqlite3` e um export JSON.
É um ponto de recuperação manual da virada de 01/10, anterior ao regime de backups diários. Serve para auditoria; **não é o backup vigente**.

#### `ops/` — 177 MB (quase todo venv)

| Item | Função |
|---|---|
| `lab_ops.py` | `backup`, `health`, `verify-backup` — chamado pelos services systemd |
| `browser_check.py` | Verificação funcional via navegador |
| `recovery_check.py` | Validação de restauração |
| `.venv-browser/` + `.browser-libs/` | Ambiente Playwright/Chromium (~175 MB) |
| `rollback-MEDUSA-REMOTE-BACKUP-01-R1/` | Rollback do backup remoto |
| `README.md` | Procedimento operacional, acesso e limites |

#### `backups/` — 3,0 GB, 31 backups

Cada `operational-YYYYMMDDThhmmssZ/` é um conjunto **completo e verificado**:

| Item | Conteúdo |
|---|---|
| `backup.json` | Manifesto: `state: COMPLETE`, arquivos, links, coleções, escopo. O `state` é o marcador durável, gravado só após o export |
| `medusa/` | `core/`, `workspace/`, `incoming/`, `ops/`, `rag-worker/`, `config/` |
| `davy-jones/` | `app/`, `deploy/`, `tests/`, `config/`, `mem0/` |
| `qdrant/` | Export de pontos/vetores de todas as revisões concluídas |
| `systemd-user/` | Units e symlinks |
| `canonical-chunks.jsonl` | Cópia do corpus canônico |

O diretório `20261001-085319/` é anterior a esse esquema e **não** segue o padrão `operational-*`.
A réplica remota é feita por SMB sobre Tailscale, de hora em hora, a partir dos backups concluídos.

#### `logs/` e `scripts/`

- `logs/docling/` — previsto para logs do conversor, mas **vazio**: a operação real concentra tudo em `~/log`.
- `scripts/reset_password_usuario.py` — redefinição de senha humana, modo 0600.

---

### 4.2 `~/davy-jones` — 432 MB 🔴

Administração autenticada, fila de jobs, interface web e memória operacional. Serve em `127.0.0.1:8766` e depende de `medusa-core` e do RAG Worker.

| Subdiretório | Tam. | Função |
|---|---:|---|
| `app/` | ~340K | Código da aplicação (17 arquivos) |
| `config/` | 20K | `admin.json`, `human_auth.json`, `mem0.json` (todos 0600) |
| `data/` | 17M | Filas, OCR, DOCX e estado do Mem0 (0700) |
| `deploy/` | ~1M | 14 rollbacks + unit + 5 arquivos de requirements |
| `tests/` | ~200K | 14 módulos de teste + checagens vivas |
| `templates/` | 12K | Template de procuração (`procuracao-v1.docx` + manifesto) |
| `honcho/` | 7,2M | **Somente backups históricos** do Honcho |
| `.venv-mem0/` | ~400M | Python 3.11 com SDK Mem0 2.2.1 |
| `README.md` | 52K | Contrato completo de API, persistência e limites |

#### `app/` — mapa dos módulos

| Arquivo | Função |
|---|---|
| `davy.py` (58K) | Núcleo HTTP, fila, admissão, retries, autenticação |
| `index.html` (82K) | Interface única (Medusa + Davy-Jones) |
| `registry.py` / `registry_views.py` | Cadastro Universal (C1/C2), pessoas, rótulos, vínculos |
| `human_auth.py` / `auth_views.py` / `auth_admin.py` | Login humano, sessões, administração de usuários |
| `grounding.py` | Grounding jurídico conservador |
| `legal_planner.py` | Plano de pesquisa após grounding |
| `legal_facts.py` | Extração de fatos |
| `legal_review.py` | Pacote de revisão |
| `document_ocr.py` | OCR local |
| `document_docx.py` | Geração determinística de DOCX |
| `memory_layer.py` | Integração Mem0 |
| `web_search.py` | Cliente SearXNG |
| `tool_registry.py` / `tool_orchestrator.py` | Seleção e execução de ferramentas |

#### `config/` — segredos operacionais (nunca versionar)

- `admin.json` (116 B) — token de administração; lido por Davy-Jones e pelo Worker.
- `human_auth.json` (475 B) — usuários humanos, *hashes* e estado.
- `mem0.json` (957 B) — coleção `davy_jones_mem0_v1`, modelo de embedding e de extração.

Todos em 0600. Não há cópia em git.

#### `data/` — estado persistente

| Item | Tam. | Função |
|---|---:|---|
| `jobs.sqlite3` | 15M | Histórico de jobs (WAL, até 10.000 registros) |
| `jobs.sqlite3-wal` / `-shm` | variável | Journal do SQLite |
| `worker.lock` | 0 | Instância única |
| `document_ocr/` | 2,2M | 21 execuções de OCR |
| `document_docx/` | 300K | Documentos gerados |
| `mem0/` | 28K | Estado local do SDK |

O `jobs.sqlite3` guarda **perguntas e evidências recuperadas**. É dado sensível: entra no backup diário e deve ser preservado em qualquer upgrade.

#### `deploy/` — 20 entradas

14 diretórios `*-rollback` (DAVY-SEARXNG-01, DAVY-TOOLS-01, MEDUSA-UI-01/02, MEDUSA-LEGAL-*, MEDUSA-DOC-OCR-01, MEDUSA-DOCX-01, MEM0-INTEGRATION-01 etc.),
mais `davy-jones.service` e cinco arquivos de dependências fixadas (`requirements-*.txt`/`.lock`).

É o **histórico de reversão** de cada entrega. Não é lido em runtime, mas é o que permite voltar atrás sem reconstruir.

#### `templates/` e `tests/`

- `templates/procuracao/` — modelo DOCX versionado + `manifest.json` com hash. Base da geração determinística.
- `tests/` — `test_rag_api`, `test_document_ocr`, `test_document_docx`, `test_legal_*`, `test_ui_access`, `test_human_auth`, `test_web_search`, `test_tools`, `test_memory`, além de checagens vivas (`facts_ui_live_check`, `planner_ui_agent_contract_check`).

#### `honcho/` — 7,2 MB ⚪

Somente `backups/` de versões antigas (U0.16.3.7.x, M3.3) e um `runtime.env.bak`.
**Não é o orquestrador ativo.** O README é explícito: é histórico preservado, não runtime.

---

## 5. Infraestrutura

### 5.1 `~/infra-postgres` — 4 KB 🟠

PostgreSQL 18 + pgvector. Contém `compose.yaml`, `secrets.env` (0600), `config/pg_hba.conf`, `init/10-init-databases.sh` e `backups/` com 28 snapshots de 19/09.

**Situação real:** os bancos `medusa` e `davy_jones` existem e a extensão `vector` está instalada, mas **nenhuma aplicação os utiliza hoje**. Qdrant é o vector store efetivo. O volume tem apenas 72 MB, compatível com bancos vazios.

### 5.2 `~/infra-redis` — 84 KB 🟠

`compose.yaml`, `config/redis.conf`, `config/users.acl`, `secrets/` (senhas separadas para Medusa e Davy) e `backups/` de 19/09.

**Situação real:** o Redis está saudável, mas não foi identificado uso direto pelas aplicações. O SearXNG usa cache próprio em disco e não depende dele.

### 5.3 `~/observability` — 80 KB 🟠

| Item | Função |
|---|---|
| `docker-compose.yml` | Prometheus 3.7.3, Grafana 12.3.1, node-exporter 1.9.1 |
| `prometheus/prometheus.yml` | Scrape de `node-exporter:9100` e `prometheus:9090` |
| `grafana/dashboards/medusa.json` | Dashboard de 11 painéis |
| `grafana/provisioning/` | Datasource e provider provisionados |
| `secrets/grafana_admin_password` | Senha do admin (montada como secret) |
| `OBSERVABILITY-MEDUSA.md` | Limitações conhecidas da stack |

O diretório é **pequeno porque o estado está em volumes**: 232 MB no Prometheus (série temporal) e 50 MB no Grafana (banco interno). Limitações registradas: sem Loki, sem Alertmanager, sem métricas de aplicação/container.

### 5.4 `~/backups` — 60 KB, dono `root` 🟠

Snapshots **por mudança**, não por agenda. 13 diretórios:

```
backups/
├── M3.2-R1/
├── net-harden-a01-20261014-125233/
├── pki-b2-20261014-131639/
├── port-5080-c-20261014-131757/
├── ui-login-r1-20261014-162729/
├── ui-design-r1..r3-20261014-*/
├── c1-c2-foundation-20261014-204210/
├── c2-doc-ux-r1-20261015-175306/
├── c2-doc-ux-r1-1-20261016-103829/
└── pre-upgrade-20261009-221550/ e -221556/
```

Cada um guarda o arquivo anterior e um `rollback.sh`. Exemplo: `ui-design-r3` contém `index.html.pre-r3` e o script de reversão.
São **rollbacks de configuração**, distintos dos backups de dados em `~/medusa/backups`. Pertencer a `root` protege contra alteração acidental pelo operador.

### 5.5 Volumes Docker

| Volume | Tam. | Serviço | Conteúdo |
|---|---:|---|---|
| `u0137-ollama_u0137_ollama_models` | **29G** | `u0137-ollama` | Pesos dos modelos locais |
| `observability_prometheus_data` | 232M | `obs-prometheus` | TSDB (retenção padrão) |
| `infra_postgres_data` | 72M | `infra-postgres` | PGDATA |
| `qdrant_data` | 55M | `infra-qdrant` | **1.850 pontos** em 12 coleções |
| `observability_grafana_data` | 50M | `obs-grafana` | Banco interno do Grafana |
| `infra_redis_data` | 20K | `infra-redis` | AOF/RDB |

Observação importante: `qdrant_data` (55 MB) é **menor** que um único backup (121 MB) porque o backup inclui exports JSON de vetores, mais volumosos que o armazenamento binário nativo.

---

## 6. Operação e evidências

### 6.1 `~/log` — 194 MB, 736 arquivos 🟠

Diretório **plano** (sem subpastas), com quatro famílias:

| Padrão | Exemplos | Função |
|---|---|---|
| `*-runtime.log` | `medusa-core-runtime.log`, `davy-jones-runtime.log`, `medusa-rag-worker-runtime.log`, `medusa-caddy-runtime.log` | Log contínuo dos serviços |
| `MEDUSA-DAVY-activity.jsonl` | 1,3 MB | Trilha de readiness a cada 5 min |
| `<ENTREGA>-<timestamp>.log` | `MEDUSA-C1-C2-FOUNDATION-01-…`, `MEDUSA-DOC-RAG-01-…` | Log de execução de cada entrega |
| `C*/H*/U*/M*` | `C11-R4-…`, `H28-R1-…`, `M5.24-D4-…` | Logs de experimentos e auditorias |

O `medusa-davy-ops.log` (1,7 MB) registra backup e health. É o diretório com maior rotatividade e **não tem rotação automática** — cresce por acúmulo.

### 6.2 `~/txt` — 19 MB, 611 arquivos 🟡

Relatórios e estados legíveis por humanos:

| Padrão | Função |
|---|---|
| `MEDUSA-DAVY-health.json` | Último readiness (4 dependências) |
| `MEDUSA-DAVY-latest-backup.json` | Estado do último backup |
| `MEDUSA-DAVY-final.json` | Evidência de release |
| `MEDUSA-*.md` | Relatórios de entrega |
| `*.txt` | Espelhos textuais dos logs |

É a **vitrine de auditoria**: o que se lê sem abrir banco, container ou venv.

### 6.3 `~/script` — 5,1 MB, 360 arquivos 🟡

Scripts de implantação, diagnóstico e experimentos, em ordem cronológica de campanha:

| Prefixo | Qtd. aprox. | Campanha |
|---|---:|---|
| `MEDUSA-*` | 44 | Entregas, backups, AEL, geração |
| `M5.24-*` | 19 | Etapa M5.24 (R1…D4) |
| `M5.10-*` | 19 | Auditoria e chunking do corpus |
| `U0.16.3.7.10.6.5-*` | 16 | Infra e hardening |
| `C1…C12-*` | ~40 | Gateway Calypso / Codex |
| `H1…H30-*` | ~45 | Hermes nativo, política ABC |
| `M4.*` / `M5.*` | ~60 | Experimentos de extração e RAG |

Nada aqui é chamado em runtime, **exceto** `MEDUSA-REMOTE-BACKUP-01-R1-v1.1.0.py`, que é o `ExecStart` do `medusa-remote-backup.service`. Ou seja: `~/script` é histórico, mas contém **um** script de produção.

### 6.4 `~/.config` e `~/.local` — configuração efetiva

| Caminho | Função |
|---|---|
| `.config/systemd/user/*.service` | 7 units: core, davy, caddy, rag-worker, backup, remote-backup, health |
| `.config/systemd/user/*.timer` | 3 timers: backup diário 03:30, health 5 min, replicação horária |
| `.config/systemd/user/*.wants/` | Symlinks de enable |
| `.config/medusa-caddy/Caddyfile` | Proxy LAN, portas 5080/3443/3000 |
| `.config/medusa-caddy/proxy.env` | Variáveis do proxy (0600) |
| `.config/medusa-caddy/caddy/` | Estado interno do Caddy |
| `.config/medusa-remote-backup/` | Senha SMB (0600) + `set-password.py` |
| `.local/share/medusa-tls/` | Autoridade certificadora local e certificados |
| `.local/share/medusa-remote-backup/venv/` | Venv do script de replicação |
| `.local/state/medusa-remote-backup/` | **Staging e histórico da replicação SMB (1,2 GB)** |
| `.local/share/caddy/` | Dados do Caddy |
| `.local/bin/medusa-core` | Executável instalado do Core |

O diretório `.local/state/medusa-remote-backup` merece atenção própria:

| Item | Função |
|---|---|
| `latest.json` | Relatório da última replicação (16 KB) |
| `report-<timestamp>.json` | Histórico horário de relatórios (462 arquivos) |
| `archives/<backup>-<sha256>/` | **28 pacotes `.tar.gz` + `manifest.json` + `.sha256`** |
| `R1-*.json`, `superseded.json` | Evidência de implantação e substituição |
| `run.lock` | Impede replicações concorrentes |

Cada `archives/<...>` é o pacote comprimido de um backup enviado ao destino SMB: `operational-*.tar.gz` (~41 MB), manifesto e checksum. É o **buffer local** entre a geração do backup e a cópia remota. Com 28 pacotes, soma 1,2 GB que **duplicam** parte dos 3,0 GB de `~/medusa/backups` em formato comprimido.

**Consequência prática:** as units em `~/.config/systemd/user` são a fonte da verdade dos serviços. As cópias em `deploy/` e em `rag-worker/deploy/` são artefatos de instalação e podem divergir — sempre comparar antes de reinstalar.

### 6.5 `.mem0`, `.hermes`, `.codex`

| Caminho | Tam. | Situação |
|---|---:|---|
| `.mem0/` | 92K | **Ativo** — `config.json`, `history.db`, `migrations_qdrant` |
| `.hermes/` | 2,5G | ⚪ Histórico — runtime, cache, backups, `hermes-agent/` |
| `.codex/` | 3,1G | ⚪ Histórico — `logs_2.sqlite` (38 MB), sessões, cache |

`.mem0` é estado do SDK, separado de `davy-jones/data/mem0`. Não confundir os dois: o primeiro é cache/histórico do SDK; o segundo é o diretório configurado por `MEM0_DIR`.

---

## 7. Histórico e legado

### 7.1 `~/medusa-ael` — 79 MB ⚪

Laboratório de agentes (AEL) com git próprio, `AGENTS.md` e `POLICY.md`. Contém `codex-home/`, `b5/`, `b6/`, `p1/`, `prod-01/`, `full-access-r1/`, `native-implementation/`, `reports/`, `runs/`, `tests/`, `tooling/`, `workspace/`.

O `AGENTS.md` é explícito: **trabalhar somente dentro desse diretório**, sem acesso a produção, Docker, Qdrant, Ollama, PostgreSQL, Redis ou aos diretórios `medusa`/`davy-jones`. É um sandbox encerrado. Pode ser arquivado em bloco.

### 7.2 `~/old` — 344 KB ⚪

Backups nomeados por versão (`U0.13.6`…`U0.14.2.2`, `H6`…`H30`, `u0.13.7-ollama`, `organizacao-20261002T182803Z`) e um `src/`.
São **cópias anteriores** de configuração, não o estado atual. Úteis para arqueologia; sem função operacional.

### 7.3 `~/codex-migration-backup` — 28 KB ⚪

`20261001-070124/` com `OLD_STATE.json`, `package.json`, `package-lock.json`, `npm-list.txt` e link para o home antigo do Codex. Registro da migração de 01/10.

### 7.4 `~/medusa-davy-jones-autonomous` — 32 KB ⚪

Uma única execução (`runs/20261001-085133/`) com `MISSION.md`, `PROJECTS.txt`, `CODEX_PATH.txt` e `CODEX_VERSION.txt`. É o rastro de uma campanha autônoma pontual, não um diretório de trabalho recorrente.

---

## 8. O que **não** existe no host

Verificado explicitamente — importante para não procurar no lugar errado:

| Caminho esperado | Situação |
|---|---|
| `/opt/medusa` | não existe — `/opt` não tem entrada do projeto |
| `/srv/medusa` | não existe (`/srv` vazio) |
| `/etc/medusa` | não existe |
| `/var/lib/medusa` | não existe |
| `/var/log/medusa` | não existe |
| `/usr/local/bin/medusa*` | não existe — o executável está em `~/.local/bin` |
| Open WebUI | não instalado |
| Nginx / porta 443 | não adotados; Caddy serve 5080/3443/3000 em LAN |

**Toda a instalação é de usuário.** Não há pacote de sistema, `/etc` ou serviço root para o Medusa. Isso simplifica limpeza e dificulta descoberta por quem procura o padrão FHS.

---

## 9. Fluxo de dados entre os diretórios

```
                    ┌──────────────────────────────────────┐
   PDF/TXT/MD  ───► │ medusa/documents/incoming/           │
                    └───────────────┬──────────────────────┘
                                    │ (seleção explícita, sem watcher)
                                    ▼
                    ┌──────────────────────────────────────┐
                    │ davy-jones  ──►  rag-worker          │
                    │ (job)            (fila SQLite)       │
                    └───────────────┬──────────────────────┘
                                    ▼
                    ┌──────────────────────────────────────┐
                    │ medusa-core ingest                   │
                    │  ├─ docling/  (conversão + OCR)      │
                    │  ├─ ollama    (embedding 2560d)      │
                    │  └─ qdrant    (collection por rev.)  │
                    └───────────────┬──────────────────────┘
                                    ▼
                    ┌──────────────────────────────────────┐
                    │ medusa/workspace/revisions/<sha>/    │
                    │ medusa/workspace/index.json          │
                    └───────────────┬──────────────────────┘
                                    ▼
        consulta ──► medusa-core :8765 ──► trechos + citação
                  └► davy-jones :8766 ──► jobs, drafts, registry

   Evidência:  log/  +  txt/  +  medusa/backups/  ──►  SMB remoto
```

Regra de ouro: **`documents/incoming` é entrada; `workspace/revisions` é saída imutável; `backups` é cópia; `data` e `artifacts` são laboratório.** Nenhum desses papéis se mistura no código.

---

## 10. Propriedade e permissões

| Caminho | Modo | Dono | Motivo |
|---|---|---|---|
| `~/medusa` | 775 | usuario | Operação normal |
| `~/medusa/documents/incoming` | 775 | usuario | Precisa aceitar arquivo do operador |
| `~/medusa/workspace` | **700** | usuario | Conteúdo jurídico e revisões |
| `~/medusa/rag-worker` | **700** | usuario | Fila e lock |
| `~/medusa/backups` | 755 | usuario | Leitura pelo verificador |
| `~/medusa/artifacts` | 755 | **root** | Imutabilidade dos artefatos M5 |
| `~/davy-jones` | 750 | usuario | App + config |
| `~/davy-jones/config` | **700** | usuario | Tokens e hashes |
| `~/davy-jones/data` | **700** | usuario | Perguntas, evidências, jobs |
| `~/backups` | 755 | **root** | Rollback resistente ao operador |
| `~/log`, `~/txt` | 775 | usuario | Leitura e escrita contínuas |

Os arquivos sensíveis seguem 0600: `admin.json`, `human_auth.json`, `mem0.json`, `core-config/settings.yml`, `proxy.env`, senha SMB, `reset_password_usuario.py`.

---

## 11. Observações e pendências identificadas

1. **Backups crescem sem retenção.** 31 conjuntos somam 3,0 GB (o mais recente tem 121 MB), com +1/dia. Não há política de expiração; o crescimento é linear. A isso soma-se o staging de replicação em `.local/state/medusa-remote-backup/archives` (28 pacotes `.tar.gz`, 1,2 GB), que também não tem poda visível.
2. **`data/` e `artifacts/` são laboratório puro.** 133 MB de execuções M4/M5 que não são lidas em runtime. Candidatas a arquivamento após autorização.
3. **Revisões de workspace não têm GC.** 5 revisões hoje; cada nova ingestão acrescenta uma. Sem coleta, o Qdrant e `workspace/revisions` crescem indefinidamente.
4. **`logs/` do medusa está vazio.** Toda a observabilidade textual foi centralizada em `~/log`. O diretório pode ser removido ou documentado como reservado.
5. **Legado pesa mais que produção.** `.codex` (3,1 GB) + `.hermes` (2,5 GB) + `old` + `medusa-ael` ≈ 5,7 GB, contra 3,8 GB de aplicação viva.
6. **PostgreSQL e Redis estão ociosos.** Mantidos saudáveis, sem uso identificado pelas aplicações. São dívida de infraestrutura, não de dados.
7. **Scripts de produção fora do lugar.** `~/script` é histórico, mas contém o `MEDUSA-REMOTE-BACKUP-01-R1-v1.1.0.py` que roda de hora em hora. Um diretório histórico não deveria ser `ExecStart` de serviço.
8. **Units duplicadas.** Cópias em `~/.config/systemd/user`, `davy-jones/deploy` e `medusa/rag-worker/deploy`. A fonte da verdade é a primeira; as outras podem divergir.

---

## 12. Quadro-resumo consolidado

| # | Caminho | Tam. | Papel | Crit. |
|---|---|---:|---|---|
| 1 | `~/medusa/core` | 188K | Serviço de recuperação | 🔴 |
| 2 | `~/medusa/config` | 8K | Contrato do índice canônico | 🔴 |
| 3 | `~/medusa/documents` | 12M | Inbox de ingestão | 🔴 |
| 4 | `~/medusa/workspace` | 14M | Revisões imutáveis publicadas | 🔴 |
| 5 | `~/medusa/rag-worker` | 148K | Fila durável de ingestão | 🔴 |
| 6 | `~/medusa/docling` | 31M | Modelos OCR + scratch | 🔴 |
| 7 | `~/medusa/backups` | 3,0G | 31 backups completos | 🟠 |
| 8 | `~/medusa/ops` | 177M | Backup, health, browser | 🟠 |
| 9 | `~/medusa/searxng` | 216K | Busca web interna | 🟠 |
| 10 | `~/medusa/data` | 126M | 38 execuções M4/M5 | 🟡 |
| 11 | `~/medusa/artifacts` | 7,1M | Artefatos M5.11/M5.12 | 🟡 |
| 12 | `~/medusa/recovery` | 1,3M | Export pontual 01/10 | 🟡 |
| 13 | `~/medusa/compose` | 8K | Compose Docling | 🟠 |
| 14 | `~/medusa/logs` | 8K | Reservado (vazio) | ⚪ |
| 15 | `~/medusa/scripts` | 8K | Reset de senha | 🟠 |
| 16 | `~/davy-jones/app` | 340K | Aplicação e interface | 🔴 |
| 17 | `~/davy-jones/config` | 20K | Tokens e credenciais | 🔴 |
| 18 | `~/davy-jones/data` | 17M | Filas, OCR, DOCX, Mem0 | 🔴 |
| 19 | `~/davy-jones/.venv-mem0` | 400M | Runtime Python 3.11 | 🔴 |
| 20 | `~/davy-jones/deploy` | 1M | 14 rollbacks + unit | 🟠 |
| 21 | `~/davy-jones/tests` | 200K | Regressão | 🟠 |
| 22 | `~/davy-jones/templates` | 12K | Template de procuração | 🟠 |
| 23 | `~/davy-jones/honcho` | 7,2M | Backups históricos | ⚪ |
| 24 | `~/observability` | 80K | Stack Prometheus/Grafana | 🟠 |
| 25 | `~/infra-postgres` | 4K | Compose + init (ocioso) | 🟠 |
| 26 | `~/infra-redis` | 84K | Compose + ACL (ocioso) | 🟠 |
| 27 | `~/backups` | 60K | Rollbacks por mudança | 🟠 |
| 28 | `~/log` | 194M | Logs e trilha de atividade | 🟠 |
| 29 | `~/txt` | 19M | Relatórios e estados | 🟡 |
| 30 | `~/script` | 5,1M | 360 scripts (1 em produção) | 🟡 |
| 31 | `~/medusa-ael` | 79M | Sandbox encerrado | ⚪ |
| 32 | `~/old` | 344K | Backups antigos | ⚪ |
| 33 | `~/codex-migration-backup` | 28K | Migração Codex | ⚪ |
| 34 | `~/medusa-davy-jones-autonomous` | 32K | Execução autônoma única | ⚪ |
| 35 | `~/.hermes` | 2,5G | Runtime histórico | ⚪ |
| 36 | `~/.codex` | 3,1G | Runtime histórico | ⚪ |
| 37 | `~/.local/state/medusa-remote-backup` | 1,2G | Staging da replicação SMB | 🟠 |
| 38 | `~/.mem0` | 92K | Estado do SDK Mem0 | 🟠 |
| 39 | Volumes Docker | ~29,4G | Modelos, Qdrant, TSDB | 🔴 |

---

## 13. O ponto mais importante

O host Medusa é **uma instalação de usuário, não uma instalação de sistema**. Não procure nada em `/opt`, `/etc` ou `/var/lib`: tudo o que importa está em `/home/usuario`, e o que parece "infraestrutura" (PostgreSQL, Redis, Qdrant, Prometheus) é composto por containers cujo estado vive em `/var/lib/docker/volumes`.

A árvore é menor do que o volume sugere. **Menos de 250 MB são código, configuração e documentos.** Os 3,4 GB de `~/medusa` são quase todos backup; os 5,7 GB de `.codex`/`.hermes` são runtime encerrado; os 29 GB de Ollama são modelos baixados. Quem for limpar espaço deve olhar primeiro para retenção de backup, modelos não usados e diretórios legados — nessa ordem — e **nunca** para `workspace/`, `documents/` ou `backups/` sem autorização explícita, porque são os três lugares onde a prova jurídica existe.

E a assimetria que merece decisão: **a aplicação tem backup testado, mas não tem política de retenção**, enquanto o legado tem 5,7 GB sem função. O risco não é falta de espaço — há 619 GB livres — é a dificuldade de distinguir, daqui a seis meses, o que é prova do que é rascunho.

---

*Documento gerado por inspeção somente leitura. Nenhuma configuração, serviço, container ou arquivo do host foi alterado.*
