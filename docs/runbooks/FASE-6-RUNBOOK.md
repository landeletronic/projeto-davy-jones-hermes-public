# FASE 6 — RAG jurídica + TLS + monitoramento + backup — RUNBOOK

> **Status: 6.1, 6.2, 6.3, 6.4 e 6.5 CONCLUÍDAS em 2026-10-18.** Suite: `PASS=88 / FAIL=0`.
> *Números são da época; o estado atual está no `README.md`/`AGENTS.md`.*
> Escopo: documentos da RAG com **citações**, 100% local, no mesmo Qdrant do mem0,
> acesso por **HTTPS**, **monitoramento** do host/containers, **backup** diário e
> Open WebUI atualizado (**v0.12.3**).

## 1. Arquitetura

```
                    ┌──────────── LAN ────────────┐
navegador ──HTTPS──►│ nginx :443 (TLS)  :3001 (TLS)
                    └───┬───────────────────┬─────
                        │ /                 │ /
                 open-webui:8080      grafana:3000
                        │
      PDF/DOCX ──► Docling Serve (CPU) ──► Markdown (layout/tabelas/OCR pt)
                        └─► OWUI Knowledge (chunk) ──► bge-m3 (Ollama) ──► Qdrant
                                                                           ├─ owui_knowledge
                                                                           ├─ owui_files
                                                                           └─ mem0_memories (mem0)

  Prometheus ◄── node-exporter (host) / cadvisor (containers) / qdrant:/metrics
  SearXNG (metabusca, interno) — usado só se ENABLE_WEB_SEARCH=true
```

- **Docling** novo no compose: `ghcr.io/docling-project/docling-serve-cpu:v1.37.0`.
- **OWUI** passa a usar Qdrant como vector DB (antes: Chroma, vazio → sem migração).
- Coleções fixas do OWUI (multitenancy mode, default): `owui_knowledge` e `owui_files`,
  isoladas por `tenant_id` no payload (`tenant_id` da base = id da knowledge base).
- `mem0_memories` **não** é tocada.

## 2. O que mudou

`docker-compose.yml` (host: `/home/usuario/hermes-architect/docker-compose.yml`):

### 6.1 — RAG
- serviço `docling` (porta `127.0.0.1:5001`, volume `docling_cache`, CPU, 8 threads);
- `open-webui` `depends_on` docling/qdrant e env:
  `VECTOR_DB=qdrant`, `QDRANT_URI=http://qdrant:6333`, `QDRANT_COLLECTION_PREFIX=owui`,
  `RAG_EMBEDDING_ENGINE=ollama`, `RAG_EMBEDDING_MODEL=bge-m3`,
  `RAG_OLLAMA_BASE_URL=http://ollama:11434`,
  `CONTENT_EXTRACTION_ENGINE=docling`, `DOCLING_SERVER_URL=http://docling:5001`.

Config efetiva (tabela `config` do `webui.db`, via `tools/set_owui_rag_config.py`):

| chave | valor |
|---|---|
| `rag.embedding_engine` | `ollama` |
| `rag.embedding_model` | `bge-m3` |
| `rag.content_extraction_engine` | `docling` |
| `rag.docling_server_url` | `http://docling:5001` |
| `rag.docling_params` | `{"to_formats":["md"],"do_ocr":true,"ocr_lang":["pt"],"table_mode":"accurate"}` |

### 6.2 — TLS (nginx) + SearXNG
- serviço `nginx` (`nginx@sha256:892b…`, 1.31.7-alpine): `80` (redirect) + `443` (TLS) +
  `3001` (Grafana via TLS). `client_max_body_size 512M`, `proxy_read_timeout 3600s`,
  WebSocket (`Upgrade`) para o chat do OWUI.
- certificado autoassinado com SAN `DNS:hermes-lab`, `DNS:davy-jones-hermes`,
  `IP:192.168.15.231` (`nginx/certs/`, gerado por `tools/make_tls_cert.sh`, válido até 2029).
- OWUI deixa de publicar `0.0.0.0:3000` → `127.0.0.1:3000` (LAN só por HTTPS).

#### 6.2.1 — Renovação do certificado (#10)

O cert é **autoassinado**: ninguém renova por você. Sem o caminho abaixo, o HTTPS
quebraria em 2029-01-20 sem aviso.

- **Monitoramento:** `tls-cert-metrics` (cron 03:20) publica `hermes_tls_cert_days_left`
  no textfile; alertas `LabTLSCertExpiring` (<30 dias) e `LabTLSCertExpired` (<0).
- **Renovar (um comando):**

  ```bash
  ssh davy-jones-hermes 'bash /home/usuario/hermes-architect/tools/make_tls_cert.sh --force --reload'
  ```

  O script guarda o par antigo (`*.bak-<data>`), gera chave nova, recarrega o nginx e
  **confere o fingerprint servido** contra o arquivo (reload que não pega = erro).
- **Sem `--force` ele não sobrescreve**; `--renew-if-days N` renova só se faltar ≤ N dias
  (para automação futura — hoje é manual de propósito: quem importou o cert antigo
  volta a ver "não confiável" até reimportar).
- **Mudou o IP da LAN?** `tools/make_tls_cert.sh --force --reload --ip <novo-ip>` (a suíte
  avisa com WARN quando o IP atual não está na SAN).
- A suíte prova a renovação **em diretório isolado** (nunca no cert de produção) e exige
  que o nginx sirva exatamente o arquivo.
- serviço `searxng` (`searxng/searxng@sha256:8bdd…`) **interno**, com `formats: [html, json]`.
  No OWUI: `ENABLE_WEB_SEARCH=false` (busca web é opcional e exige internet).

### 6.3 — Monitoramento (4 containers)
- `prometheus` (`v3.15.0`): scrape de `node-exporter`, `cadvisor`, `qdrant:/metrics`,
  ele mesmo; retenção 15d/2GB; **sem porta publicada**.
- `node-exporter` (`v1.12.1`) + `cadvisor` (`v0.55.1`, `--docker_only`): métricas do host
  e por container; interno.
- `grafana` (`13.2.4`): só na rede interna; sai para a LAN via nginx em
  **https://192.168.15.231:3001**. Admin = `admin` / senha em
  `/home/usuario/hermes-architect/.env` (`GRAFANA_ADMIN_PASSWORD`).
- provisioning: datasource Prometheus (uid `prometheus`) + dashboard
  **“Hermes Lab — Host & Containers”** (CPU/RAM/disco/load + top containers).

### 6.4 — Backup e pinagem
- **pinagem**: `open-webui` e `ollama` deixaram de usar tag flutuante e passaram a
  **digest** (`@sha256:…`); nginx/searxng/prometheus/grafana/node-exporter/cadvisor
  também por digest; qdrant e docling por versão fixa.
- `ops/bin/backup_stack.sh` → instalado em `/usr/local/bin/hermes-backup` (cron diário 03:30).
  > ⚠️ **Correção (Fase 7, 2026-10-18):** o pacote `cron` **não estava instalado** no host, então
  > esta entrada **não rodava** — os backups da 6.4 foram manuais. O cron foi instalado e
  > habilitado na Fase 7 (ver `FASE-7-RUNBOOK.md` §5.6), e a suíte agora checa o daemon.
  Gera `/home/usuario/backups/hermes-<UTC>.tar.gz` (600) com:
  1. `docker-compose.rendered.yml` (compose efetivo, com segredos);
  2. `project-config.tgz` (compose, `.env`, nginx, monitoring, searxng);
  3. `.hermes/` (config, mem0.json, plugins, skills — sem caches/runtime);
  4. `webui.db` (cópia consistente via `sqlite3 .backup`);
  5. snapshots de **todas** as coleções do Qdrant;
  6. `README.txt` (manifest: containers, digests, contagem de pontos).
- retenção: **7** no host; **8** no destino.
- `ops/windows/pull-backups.ps1` puxa para `\\localhost\backups\hermes-lab` no Windows
  (agendado como *Hermes Lab Backup Pull*, diário 12:00).

### 6.5 — Open WebUI 0.11.4 → 0.12.3
- imagem re-pinada para `ghcr.io/open-webui/open-webui@sha256:a537bbe1…` (**v0.12.3**);
  o digest antigo do `:main` estava defasado em 0.11.4 (origem do banner de atualização).
- **Breaking**: `/api/v1/auths/` agora exige **sessão humana** (JWT com `typ=session`).
  API key autentica o usuário, mas é recusada com `403 "A human session is required."`.
- `GET /api/v1/knowledge/list` virou `GET /api/v1/knowledge/`; `create`, `{id}/file/add`
  e `{id}/delete` não mudaram. Coleções `owui_knowledge`/`owui_files` idem.

## 3. Reprodução do zero

```bash
# 1) subir docling (primeiro boot precisa dos pesos — ver §5)
cd /home/usuario/hermes-architect
docker compose up -d docling
docker inspect -f '{{.State.Health.Status}}' docling     # healthy

# 2) aplicar config rag.* (PersistentConfig não aceita env depois do 1º boot)
docker cp tools/set_owui_rag_config.py open-webui:/tmp/
docker exec open-webui python /tmp/set_owui_rag_config.py

# 3) certificado TLS (uma vez) e subir tudo
bash tools/make_tls_cert.sh           # cria nginx/certs/server.{crt,key}
docker compose up -d

# 4) backup (instalar + agendar)
sudo install -m 755 ops/bin/backup_stack.sh /usr/local/bin/hermes-backup
echo '30 3 * * * usuario /usr/local/bin/hermes-backup >> /home/usuario/backups/backup.log 2>&1' \
  | sudo tee /etc/cron.d/hermes-backup

# 5) suíte
powershell -File tests/run-tests.ps1        # Windows
# ou: bash tests/verify_stack.sh             # host
```

## 4. Validação E2E (smoke)

```bash
scp tests/fixtures/contrato-teste.pdf davy-jones-hermes:/tmp/
scp tests/smoke_rag.py davy-jones-hermes:/tmp/
ssh davy-jones-hermes "docker cp /tmp/contrato-teste.pdf open-webui:/tmp/ && \
  docker cp /tmp/smoke_rag.py open-webui:/tmp/ && \
  docker exec open-webui python /tmp/smoke_rag.py"
```

Esperado (resumo):

```
auth: 200 admin@example.com
process status: completed
points em owui_knowledge (tenant <kb-id>): 2
answer: O contrato tem vigência de 24 meses ... multa ... 10% ... [1]
sources: [{"source": {"type": "collection", "id": "<kb-id>"}, ...}]
SMOKE OK
cleanup knowledge: 200 true
cleanup file: 200 {"message":"File deleted successfully"}
```

**Autenticação do smoke (mudou na v0.12.3):** o script assina um JWT HS256 com o
`WEBUI_SECRET_KEY` (lido de `/proc/1/environ` do processo uvicorn) + o `session_stamp`
da conta em `auth` — a mesma verificação que o login faz. Assim ele **não** liga
`auth.enable_api_keys` e não cria API keys temporárias. O script limpa tudo no `finally`
(knowledge e file).

## 5. Recuperação / pegadinhas

**Docling não sobe: `RapidOCR artifacts not found`**
`DOCLING_SERVE_ARTIFACTS_PATH` exige modelos já baixados. Prefetch (uma vez):

```bash
docker run --rm --user root -v hermes-architect_docling_cache:/opt/docling-cache \
  ghcr.io/docling-project/docling-serve-cpu:v1.37.0 chown -R 1001:0 /opt/docling-cache
docker run --rm -v hermes-architect_docling_cache:/opt/docling-cache \
  ghcr.io/docling-project/docling-serve-cpu:v1.37.0 \
  docling-tools models download -o /opt/docling-cache \
  --rapidocr-backend-lang onnxruntime:pt --rapidocr-backend-lang onnxruntime:en
```

**Mudou env de RAG e “não pega”**
`rag.*` são `PersistentConfig`: o valor do banco vence. Rode o script da §3 e reinicie.

**Upload fica `pending`**
Processamento é assíncrono. Espere `data.status == completed` (`GET /api/v1/files/{id}`)
antes de anexar/consultar.

**Coleção `owui_<uuid>` não existe**
Normal: com `ENABLE_QDRANT_MULTITENANCY_MODE=true` (default) as coleções são
`owui_knowledge`/`owui_files` e o escopo é `tenant_id`.

**Aviso `Qdrant client 1.18.0 is incompatible with server 1.15.2`**
> **Resolvido em 2026-10-20:** servidor subiu para **v1.19.2** (cadeia 1.15.2 → 1.16.3 → 1.19.2,
> provada em cópia do volume por `tools/verify_qdrant_upgrade.sh --via`). O salto direto não migra
> — ver `AGENTS.md` §5.

Benigno para as operações usadas. Upgrade do Qdrant é passo separado (afeta o mem0).

**Apagar documento = apagar vetores?**
`DELETE /api/v1/files/{id}` remove os pontos (`tenant_id` do arquivo) — validado no smoke.
Para LGPD, conferir contagem em `owui_knowledge`/`owui_files` após expurgo.

**`403 A human session is required.` (Open WebUI ≥ 0.12)**
`/api/v1/auths/` (e outras rotas de conta) só aceitam **JWT de sessão** (`typ=session`),
não API key. Para automação: assinar o JWT com o `WEBUI_SECRET_KEY` +
`session_stamp` da conta (ver `tests/smoke_rag.py`). API key continua valendo para
`/api/v1/files`, `/api/v1/knowledge`, `/api/chat/completions` etc.

**`SystemExit: WEBUI_SECRET_KEY is not set`** ao importar `open_webui.*` via `docker exec`
O segredo é gerado/exportado pelo script de start, então `docker exec` **não** o herda.
Leia de `/proc/1/environ` (processo uvicorn) ou passe `-e WEBUI_SECRET_KEY=...`.

**Navegador avisa “certificado não confiável”**
Esperado: é autoassinado (sem CA interna). O tráfego está criptografado. Para remover o
aviso, importar `nginx/certs/server.crt` como confiável nos PCs do escritório.

**Grafana não abre em :3001**
Ele não publica porta: quem atende é o nginx (`nginx/conf.d/grafana.conf`). Confira
`https://192.168.15.231:3001/api/health` e se o nginx está na rede `backend`.

**Backup falha com `Permission denied` em `.hermes`**
Há arquivos root (ex.: `.ssh`, caches). O script usa `sudo tar` e exclui caches —
`sudo -n` precisa estar habilitado (NOPASSWD).

**Restaurar um backup**

```bash
mkdir -p /tmp/restore && tar -xzf /home/usuario/backups/latest.tar.gz -C /tmp/restore
# webui.db  -> docker cp para open-webui:/app/backend/data/   (com o container parado)
# .hermes   -> /home/usuario/  (extrair hermes-data.tgz)
# snapshots -> POST /collections/<c>/snapshots/upload?priority=snapshot  (Qdrant)
# configs   -> extrair project-config.tgz em /home/usuario/hermes-architect/
```

## 6. Estado da Fase 6

**Concluído:** 6.1 (RAG + citações), 6.2 (TLS na LAN + SearXNG), 6.3 (Prometheus/Grafana),
6.4 (backup diário + pinagem), 6.5 (Open WebUI 0.12.3). **Suíte: PASS=88 / FAIL=0.**

**Pendências (próximas fases / decisões de escritório):**

- **Verificação de citação**: hoje o `[1]` aponta para os trechos recuperados, mas o modelo
  pode citar errado. Próximo passo = checar se o texto citado existe no chunk (pós-processador).
- **Política de retenção/expurgo (LGPD)**: prazo de guarda, anonimização e trilha de auditoria
  leve — decisão do escritório.
- **Backup off-site**: o destino atual (`\\localhost\backups`) é a mesma máquina do repositório;
  para DR real, replicar para mídia/nuvem externa.
- **Upgrade do Qdrant** (1.15.2 → atual) — **feito em 2026-10-20**: v1.19.2, por degrau (1.16.3).
- **Grafana**: TLS já ok; opcional publicar também atrás de `/grafana` no 443.
