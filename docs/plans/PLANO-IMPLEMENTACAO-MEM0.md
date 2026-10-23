# Plano de Implementação — Hermes × Mem0 (lab davy-jones-hermes)

> Host: `davy-jones-hermes` (192.168.15.231) · Ubuntu 26.04.1 LTS · Docker limpo · GPU AMD RX 6600
> Data: 2026-10-09 · Status: **EM EXECUÇÃO**

## 0. Decisões consolidadas (brainstorm)

| # | Decisão | Escolha |
|---|---------|---------|
| A | Mem0 onde roda | OSS **in-process** no Hermes (`mode: "oss"`) — 0 containers novos |
| B | Vector store | **Qdrant compartilhado** (RAG + coleção `mem0_memories`, dims 1024) |
| C | Multiusuário + senha | Login e-mail+senha no **Open WebUI**; `user_id` = e-mail do login |
| D | LLM extração | Ollama local (`qwen3:8b`) |
| E | Embeddings | Ollama `bge-m3` (1024 dims) |
| F | Honcho | **REMOVIDO** (api/db/redis já destruídos) |

## 1. Inventário: o que existe / o que refazer

**Recuperável (não apagado):**
- `_archive/docker-compose-hermes.yml.archived-20260914-202534` — spec do hermes gateway + ollama
- `honcho-rebuild-backup-*/compose.*.rendered.yml` — renders do stack completo
- `ops/docker/hermes-tools/Dockerfile` — base da imagem `hermes-tools:local` (**trocar honcho-ai → mem0ai**)
- `.hermes-dashboard.env` — credenciais basic-auth do dashboard (admin)
- `install-hermes-agent.sh`, `02-docker-compose-setup.sh`, `add-hermes-to-openwebui.sh`
- Spec do ollama: `ollama/ollama:rocm` + `HSA_OVERRIDE_GFX_VERSION=10.3.0` (RX 6600 / gfx1032)

**Perdido (refazer):**
- `docker-compose.yml` principal (open-webui, hermes, dashboard) — reconstruir dos renders + specs
- Modelos Ollama (volume `v_ollama` apagado) — re-baixar
- Todas as imagens Docker (pruned) — re-baixar/rebuild
- Dados de memória Honcho — descartados por decisão

## 2. Ordem de subida (grafo de dependências)

```
1. Redes + volumes          (frontend, backend, data)
2. Qdrant  :6333            ← mem0 e RAG dependem
3. Ollama  :11434  (GPU)    ← extração mem0 + embeddings + chat dependem
4. Open WebUI :3000          ← interface / auth (depende ollama)
5. Hermes gateway :8642      ← agente (depende qdrant+ollama+openwebui)
6. mem0 (config no Hermes)   ← mode:oss apontando p/ qdrant+ollama
7. Validação multiusuário    ← o risco #1 (identidade)
```

Por que essa ordem: cada fase só é testável com a anterior de pé; mem0 é só config dentro do Hermes (fase 6), não um serviço.

## 3. Fases com validação

### Fase 0 — Preparação
1. Atualizar `ops/docker/hermes-tools/Dockerfile`:
   ```dockerfile
   FROM nousresearch/hermes-agent:latest
   RUN apt-get update && apt-get install -y --no-install-recommends \
         openssh-client git jq curl wget ripgrep rsync zip unzip \
         procps iputils-ping dnsutils ffmpeg ca-certificates python3-pip \
       && rm -rf /var/lib/apt/lists/*
   # deps do modo OSS do mem0 (oficial: instalar na venv do Hermes)
   RUN python3 -m pip install --no-cache-dir mem0ai qdrant-client ollama
   ```
2. `docker build -t hermes-tools:local ops/docker/hermes-tools/`
3. Criar `docker-compose.yml` novo (redes `frontend`, `backend`, `data`; volumes `v_qdrant`, `v_ollama`, `v_openwebui`, `v_hermes`)
4. Criar `.env` com senhas novas (não reaproveitar as do honcho)

**✅ Validação:** `docker images | grep hermes-tools` · `docker network ls`

### Fase 1 — Qdrant
- Service: `qdrant/qdrant` · porta `6333:6333` · volume `v_qdrant:/qdrant/storage` · redes `data`+`backend`

**✅ Validação:** `curl http://192.168.15.231:6333/collections` → `{"result":{"collections":[]}}`
> Coleção `mem0_memories` é criada automaticamente pelo mem0 no primeiro write (não criar na mão — dims erradas quebram tudo).

### Fase 2 — Ollama (GPU)
- Service: `ollama/ollama:rocm` · `devices: /dev/kfd, /dev/dri` · `HSA_OVERRIDE_GFX_VERSION=10.3.0` · volume `v_ollama`
- Models (re-baixar): `bge-m3` (~1,3 GB) · `qwen3:8b` (~5,4 GB) · modelo de chat do Hermes (a definir — backups sugerem qwen3-8b/qwen3-4b)

**✅ Validação:**
```bash
curl -s localhost:11434/api/tags                      # modelos listados
curl -s localhost:11434/api/embed -d '{"model":"bge-m3","input":"teste"}' | jq '.embeddings[0]|length'   # deve ser 1024
```

### Fase 3 — Open WebUI (auth e-mail+senha)
- Service: `ghcr.io/open-webui/open-webui:main` · `3000:8080` · volume `v_openwebui` · redes `frontend`+`backend`

**✅ Validação:**
1. Abrir `http://192.168.15.231:3000` → criar admin **`admin@example.com`** + senha
2. Criar 2º usuário de teste (ex. `teste@example.com`)
3. Ambos logam, cada um vê sua própria conversa

### Fase 4 — Hermes gateway
- Service (do `_archive`, migrado para imagem nova):
  ```yaml
  hermes:
    image: hermes-tools:local          # era nousresearch/hermes-agent:latest
    container_name: hermes-agent
    restart: unless-stopped
    command: gateway run
    ports: ["8642:8642", "9119:9119"]  # gateway + dashboard
    volumes:
      - ./hermes-data:/opt/data        # mem0.json, config.yaml, .env
      - /var/run/docker.sock:/var/run/docker.sock
    extra_hosts: ["host.docker.internal:host-gateway"]
    networks: [frontend, backend, data]
    depends_on: [ollama, qdrant]
  ```
- `hermes-data/config.yaml`: `memory.provider: mem0` + provider do chat (ollama)
- `hermes-data/mem0.json`:
  ```json
  {
    "mode": "oss",
    "agent_id": "hermes",
    "sync_max_chars": 6000,
    "oss": {
      "llm":      {"provider": "ollama", "config": {"model": "qwen3:8b", "ollama_base_url": "http://ollama:11434"}},
      "embedder": {"provider": "ollama", "config": {"model": "bge-m3",   "ollama_base_url": "http://ollama:11434"}},
      "vector_store": {"provider": "qdrant", "config": {"url": "http://qdrant:6333", "collection_name": "mem0_memories", "embedding_model_dims": 1024}}
    }
  }
  ```
- `hermes-data/.env`: `MEM0_MODE=oss` (sem MEM0_USER_ID fixo — senão todos caem no mesmo balde!)

**✅ Validação:**
```bash
docker exec hermes-agent hermes memory status   # → Mode: OSS (self-hosted)
docker exec hermes-agent hermes plugins list     # mem0 instalado
curl -s localhost:8642/health                    # gateway de pé
```

**✅ CONCLUÍDA (2026-10-09).** Notas reais que surgiram na execução:

- O plugin mem0 **não** vem no catálogo instalado: `docker exec hermes-agent hermes plugins install mem0 --yes-deps --enable` (sem `--yes-deps` ele recusa em modo não-interativo).
- **Armadilha grave (Hermes v0.21.6):** `plugins install --yes-deps` dispara o *dependency environment* (PM). No boot seguinte o Hermes passa a rodar com o `site-packages` da geração commitada em `/opt/data/installs/<key>/environments/<gen>/venv` **no lugar** do venv da imagem — e a geração é instalada com `extras: []`, ou seja, **sem `aiohttp`** → o API server não sobe ("API Server: aiohttp not installed") e sem `mem0ai`/`qdrant-client`/`ollama`.
  - Sintoma: gateway `unhealthy`, porta 8642 fechada, mas `import aiohttp` funcionando no shell.
  - Diagnóstico: `sys.path` perde `/opt/hermes/.venv/lib/python3.14/site-packages` (ver `pm/environments.py`, bloco `activate()`).
  - Correção adotada: `mv /opt/data/installs /opt/data/installs.disabled-<data>` → o gateway volta ao venv da imagem (`[stage2] dependency environment: base`). O `hermes pm install` **não** serve: ele só aceita pacotes do registry de tools, não PyPI.
- `mem0ai>=2` mudou a API: `search()` exige `filters={"user_id": ...}` (o `user_id` top-level foi depreciado).

### Fase 5 — Validação E2E mem0 + multiusuário (RISCO #1)
1. Usuário A (`admin@example.com`) chama o chat e diz: *"prefiro café coado"*
2. Nova sessão do A → pergunta *"que café eu gosto?"* → deve responder (mem0 sync + search)
3. Usuário B (`teste@example.com`) → pergunta *"o que o outro usuário gosta de beber?"* → **não deve saber**
4. Conferir isolamento no dado:
   ```bash
   curl -s localhost:6333/collections/mem0_memories/points/scroll \
     -X POST -H 'Content-Type: application/json' -d '{"limit":20,"with_payload":true}' | jq '.result.points[].payload.user_id'
   # deve mostrar user_ids = emails distintos por memória
   ```

**⚠️ RISCO #1 CONFIRMADO NO CÓDIGO (2026-10-09)** — o `user_id` **não** chega como e-mail sozinho:
- O caminho OpenAI (`gateway/platforms/api_server.py → _create_agent`) monta o agente com `platform="api_server"` e `gateway_session_key`, mas **nunca define `user_id`** → `agent._user_id = None`.
- O plugin mem0 (`__init__.py:initialize`) faz `user_id = mem0.json || kwargs["user_id"] || "hermes-user"` → **tudo cairia no mesmo balde `hermes-user`**.
- O campo `author` do corpo (`turn_author`) também não salva: o `sync_turn` do plugin mem0 não o aceita.

**Solução aplicada (2 peças, ambas nativas):**
1. **Open WebUI → header por usuário.** Conexões OpenAI do OWUI aceitam headers customizados com placeholders (`{{USER_EMAIL}}`, `{{USER_ID}}`, `{{USER_NAME}}` — ver `open_webui/utils/headers.py`). O Hermes já define `X-Hermes-Session-Key` como *"per-channel memory scope"* e o repassa ao provider como `gateway_session_key`.
2. **Patch de 1 linha no plugin** (`/opt/data/plugins/mem0/__init__.py`, dentro do volume de dados):
   ```python
   native_id = kwargs.get("user_id") or kwargs.get("gateway_session_key")
   self._user_id = (None if configured == _DEFAULT_USER_ID else configured) or native_id or _DEFAULT_USER_ID
   ```
   Backup: `__init__.py.bak-labpatch-20261009`. **Se rodar `hermes plugins update mem0`, reaplicar.**

Resultado: `platform="api_server"` + `X-Hermes-Session-Key: <e-mail>` → `user_id = <e-mail>`. Sem header (ex.: CLI) → continua `hermes-user`.

**Outro bloqueio descoberto no caminho (piso de contexto):** o Hermes v0.21.6 rejeita janelas < 64.000 tokens (`_enforce_minimum_context`). Numa RX 6600 (8 GB):
- `qwen3:8b` + 64K → KV não cabe; o llama.cpp reduz a janela para 40.960 (rejeitado). Com `OLLAMA_KV_CACHE_TYPE=q4_0` até cabe, mas a geração desaba para ~0,35 tok/s.
- **Adotado: `qwen3:4b-64k`** (`num_ctx 65536`, `OLLAMA_KV_CACHE_TYPE=q8_0`) → 65.536 tokens reais, 87% GPU, ~15 tok/s.

**Extração de fatos (importante):** o mem0 chama o Ollama com `format="json"` mas **sem `think=false`**; o `qwen3` gasta os `max_tokens` pensando e devolve `content` vazio → `results: []` silenciosamente (extração falhando ~metade das vezes, ~110 s por tentativa).
- Criado `qwen3:8b-extract`: `FROM qwen3:8b` + template **sem thinking** (`PARAMETER think false` não existe nesta versão do Ollama). O `thinking` continua no campo separado, mas o `content` volta com JSON válido.
- `mem0.json` → `oss.llm.config.model: qwen3:8b-extract` (chat continua em `qwen3:4b-64k`).

**✅ Validação final (checklist):**
- [x] `hermes memory status` → OSS mode (plugin `mem0` installed ✓ / available ✓ / active ✓)
- [x] Escrita automática (sync em background) funcionando — via gateway, grava em `mem0_memories`
- [x] `mem0_search` / recall devolve fato da sessão anterior
- [x] Isolamento A/B confirmado — `payload.user_id = alice@lab.test`; Bob recebeu *"I don't have information"*
- [x] Qdrant compartilhado: coleções RAG futuras + `mem0_memories` no mesmo servidor
- [x] Host reinicia → `restart: unless-stopped` sobe tudo

### Fase 5b — Conexão do Hermes no Open WebUI ✅ **CONCLUÍDA** (2026-10-17)

> **Conferido no host:** a conexão **já existe e funciona**. Correção de rumo do plano: neste
> Open WebUI **não** há tabela `connection` — as conexões vivem na tabela `config` (chaves `openai.*`):
> - `openai.enable = true`
> - `openai.api_base_urls[1] = http://hermes:8642/v1`
> - `openai.api_configs["1"].headers = {"X-Hermes-Session-Key": "{{USER_EMAIL}}"}`
> - gateway `/v1/models` → `hermes-agent` OK

Para criar/recriar, a referência é:
`http://192.168.15.231:3000` → ⚙️ *Admin Settings* → *Connections* → *OpenAI API*:

| Campo | Valor |
|---|---|
| Base URL | `http://hermes:8642/v1` (rede interna; testado: 200) |
| API Key | `$API_SERVER_KEY` (no `.env` do host; nunca no repo) |
| **Headers** | `{"X-Hermes-Session-Key": "{{USER_EMAIL}}"}` |

Sem o header, todo mundo cai no balde `hermes-user`. Depois disso, repetir o teste A/B **no navegador**
(`admin@example.com` × `teste@example.com`) — o mechanical já foi validado por API.

> Nota: no caminho `/v1/chat/completions` a session key **não** funde conversas: o `session_id` continua
> derivado por fingerprint da conversa (a resolução por chave declarada só existe na rota `/v1/responses`).

### Fase 5c — Ponte de tools desligada (obrigatório p/ modelo pequeno) ✅ CONCLUÍDA (2026-10-17)

> Conferido em `/home/usuario/.hermes/config.yaml`: `tools.tool_search.enabled: "off"` já está aplicado.

Sintoma no navegador: o chat "trava" e o Ollama fica gerando sem parar (uma task com 992+ tokens).
Causa: com `tools.tool_search` no padrão (`enabled: auto`), as tools ficam **deferred** atrás da ponte
`tool_call`/`tool_search`, e o `qwen3:4b` não monta o array `calls` → loop de tentativas inválidas.

```yaml
tools:
  tool_search:
    enabled: "off"   # "off" = pass-through: todas as tools diretas, sem ponte
```

> `defer: []` **não** resolve: tools de *plugin* (mem0) continuam adiados por definição
> (`is_deferrable_tool_name` → toolset fora de `_DIRECT_SURFACE_TOOLSETS` ⇒ deferrable).

Após a correção: turno fecha em ~2–3 min, `mem0_add` chamado direto, zero erros de tool_call.
Ainda é lento por dois motivos: *thinking* do qwen3 (default) a ~15 tok/s na RX 6600 + prompt com
todas as schemas de tools. Se incomodar, criar variante do chat **sem thinking** (mesmo truque do
`qwen3:8b-extract`) ou aceitar o trade-off.

### Fase 5d — Acesso aos modelos no Open WebUI 0.11.4 ✅ CONCLUÍDA (2026-10-17)

> **Conferido no host (SQLite do Open WebUI):** as duas coisas já estão feitas e **validadas**:
> - `model`: linha `hermes-agent` (is_active=1) ✓
> - `access_grant`: `('model','hermes-agent','user','*','read')` ✓
> - Verificação server-side (`get_filtered_models` com o usuário **não-admin** `teste@example.com`) →
>   `VISIBLE_IDS = ['hermes-agent']` ✓

Nesta versão **todo modelo de conexão nasce privado**: só o dono/admin o vê. Sinoma no log do servidor:
`GET /api/v1/models/model/profile/image?id=undefined` para o usuário comum e `id=hermes-agent` para o admin.

São **duas** coisas necessárias (a segunda é a que costuma faltar):

**1) O modelo precisa estar registrado na tabela `model`** (`open_webui.utils.models.get_filtered_models`):
```python
elif user.role == 'admin':
    # No DB entry means no access control configured yet;
    # only admins can see unconfigured models.
```
Sem linha na tabela `model`, o modelo **não tem `info`** e é filtrado para qualquer usuário comum —
**nenhum grant resolve**. Na UI é o botão de salvar/editar em *Workspace → Models*. Registro equivalente
para um modelo de conexão (aplica override com o **mesmo id**, `base_model_id=NULL`):

```sql
INSERT INTO model (id, user_id, base_model_id, name, params, meta, is_active, updated_at, created_at)
VALUES ('hermes-agent', '<admin_user_id>', NULL, 'hermes-agent', '{}', '{}', 1, <epoch>, <epoch>);
```

**2) Liberar leitura via `access_grant`:**

```sql
INSERT INTO access_grant (id, resource_type, resource_id, principal_type, principal_id, permission, created_at)
VALUES (<uuid4>, 'model', 'hermes-agent', 'user', '*', 'read', <epoch>);
```

⚠️ **Pegadinha:** o "público" é `principal_type='user'` + `principal_id='*'` — **não** `'anyone'`.
A constante `PRINCIPAL_TYPE_ANYONE` existe, mas só na conversão de ACL legado; `has_access()` consulta
literalmente `user` + `*`, então um grant `'anyone'` é silenciosamente ignorado.

Verificação server-side (mesma função do router):
```python
# simula o filtro da listagem com o usuário comum
user  = await Users.get_user_by_id(<id_teste>)
rows  = await Models.get_models_by_ids(['hermes-agent'])
out   = await get_filtered_models([{'id':'hermes-agent','info':rows[0].model_dump()}], user)
# precisa de WEBUI_SECRET_KEY (ler de /app/backend/.webui_secret_key) e sys.path com /app/backend
```
`MODELS_CACHE_TTL` default é **1 s** — vale na próxima requisição, sem reiniciar o container.
Alternativa global: `BYPASS_MODEL_ACCESS_CONTROL=true` (ignora ACL de modelos para todos).

### Fase 6 — RAG jurídica + TLS + monitoramento + backup (2026-10-18) — CONCLUÍDA (6.1–6.4)

**Arquitetura escolhida (nativa do Open WebUI, sem RAG worker próprio):**

```
PDF/DOCX → Docling Serve (CPU) → Markdown (layout + tabelas + OCR pt)
        → Open WebUI Knowledge (chunk) → bge-m3 (Ollama, 1024d)
        → Qdrant: owui_knowledge / owui_files   (≠ mem0_memories)
        → chat com citações [1] (rag.template do OWUI)
```

- `docling` no compose: `docling-serve-cpu:v1.37.0`, porta só em `127.0.0.1:5001`,
  volume `docling_cache` (pesos), `DOCLING_DEVICE=cpu`, 8 threads, `MAX_SYNC_WAIT=600`.
- OWUI: `VECTOR_DB=qdrant`, `QDRANT_COLLECTION_PREFIX=owui`,
  `RAG_EMBEDDING_ENGINE=ollama`, `RAG_EMBEDDING_MODEL=bge-m3`,
  `CONTENT_EXTRACTION_ENGINE=docling`.
- Config efetiva em `rag.*` (PersistentConfig): `embedding_engine=ollama`,
  `embedding_model=bge-m3`, `content_extraction_engine=docling`,
  `docling_params={"to_formats":["md"],"do_ocr":true,"ocr_lang":["pt"],"table_mode":"accurate"}`.

**Pegadinhas (custaram tempo):**
1. `DOCLING_SERVE_ARTIFACTS_PATH` **não baixa** modelos: sem prefetch o boot falha
   (`RapidOCR artifacts not found`). Prefetch (uma vez):
   `docker run --rm -v hermes-architect_docling_cache:/opt/docling-cache <img> docling-tools models download -o /opt/docling-cache --rapidocr-backend-lang onnxruntime:pt --rapidocr-backend-lang onnxruntime:en`
   O volume nasce root; rodar `chown -R 1001:0` antes (imagem roda uid 1001).
2. `rag.*` são **PersistentConfig**: env só vale no 1º boot. Depois, atualizar a
   tabela `config` (script `tools/set_owui_rag_config.py`) e reiniciar.
3. OWUI com `ENABLE_QDRANT_MULTITENANCY_MODE=true` (default) usa **duas coleções fixas**
   (`owui_knowledge`, `owui_files`) com filtro `tenant_id` — **não** `owui_<knowledge_id>`.
   `tenant_id` da base = id da knowledge base.
4. Upload em OWUI processa **em background**: `data.status` começa `pending`;
   espere `completed` antes de anexar/consultar (senão o arquivo pode ser apagado no meio).
5. Aviso benigno: client qdrant 1.18 × server 1.15.2 (diferença > 1 minor).
   Funciona; upgrade do Qdrant é passo separado (mexe no mem0 também).

**Validação E2E (`tests/smoke_rag.py`, roda dentro do OWUI):**
upload do `tests/fixtures/contrato-teste.pdf` → 2 chunks → `owui_knowledge` (tenant=kb)
→ pergunta → resposta *"vigência de 24 meses ... multa de 10% ... [1]"* + `sources`.
Limpa tudo ao final (knowledge, file, api key, flag `auth.enable_api_keys`).

> **Limite importante (uso jurídico):** `[1]` aponta para o(s) trecho(s) recuperado(s), mas o
> modelo ainda pode citar errado ou misturar cláusulas. Citação **verificável de verdade**
> (checar se o texto citado existe no chunk) é um passo futuro; por ora, revisão humana obrigatória.

**6.2 — TLS na LAN (nginx) + SearXNG (2026-10-18):**

- `nginx` (`1.31.7-alpine`, pinado por digest): `:443` → `open-webui:8080` (com WebSocket,
  `client_max_body_size 512M`, `proxy_read_timeout 3600s`), `:80` → redirect 301,
  `:3001` → `grafana:3000` (TLS). Certificado **autoassinado** com SAN do IP/hostnames
  (`nginx/certs/`, `tools/make_tls_cert.sh`).
- OWUI deixa de publicar `0.0.0.0:3000` → **`127.0.0.1:3000`** (LAN só por HTTPS).
- `searxng` interno com `search.formats: [html, json]` e `server.method: GET`;
  OWUI com `ENABLE_WEB_SEARCH=false` (busca web é opcional e exige internet — o lab segue
  100% local por padrão). `WEB_SEARCH_ENGINE=searxng`, `SEARXNG_QUERY_URL=http://searxng:8080/search?q=<query>`.
- ufw: `80`, `443`, `3001` liberados; regra de `3000` removida.

**6.3 — Monitoramento (2026-10-18):**

- `prometheus` v3.15.0 (retenção 15d/2GB, **sem** porta publicada) scrapeando
  `node-exporter:9100`, `cadvisor:8080`, `qdrant:6333/metrics` — **4 alvos `up`**.
- `node-exporter` v1.12.1 (host: CPU/RAM/disco/rede/load) e `cadvisor` v0.55.1
  (`--docker_only=true`: CPU/RAM/rede por container).
- `grafana` 13.2.4 **sem** porta publicada; sai pela LAN via `nginx :3001` (TLS).
  Provisioning: datasource `prometheus` (uid fixo) + dashboard **“Hermes Lab — Host & Containers”**
  (`monitoring/grafana/dashboards/hermes-lab.json`). Admin `admin`; senha em `.env`
  (`GRAFANA_ADMIN_PASSWORD`).
- Ollama **não** expõe `/metrics` (404) → fora do scrape.

**6.4 — Backup + pinagem (2026-10-18):**

- **Pinagem**: `open-webui` e `ollama` (tags flutuantes `main`/`rocm`) passam a **digest**;
  nginx/searxng/prometheus/grafana/node-exporter/cadvisor por digest; qdrant/docling por versão.
  A suíte **falha** se voltar `:main`/`:rocm`/`:latest`.
- `ops/bin/backup_stack.sh` → `/usr/local/bin/hermes-backup`; cron `/etc/cron.d/hermes-backup`
  diário às 03:30. Artefato `~/backups/hermes-<UTC>.tar.gz` (600) = compose renderizado +
  `project-config.tgz` (compose/.env/nginx/monitoring/searxng) + `.hermes` (sem caches) +
  `webui.db` (sqlite `.backup`) + snapshots de **todas** as coleções do Qdrant + manifest.
  Retenção 7 no host.
- `ops/windows/pull-backups.ps1` (Windows) puxa para `\\localhost\backups\hermes-lab`, retenção 8,
  agendado como tarefa **Hermes Lab Backup Pull** (diário 12:00).
- Pegadinhas: `.hermes` tem arquivos de root → `sudo tar` + excluir caches (senão ~150 MB);
  `docker exec -i` é obrigatório para heredoc no sqlite backup.

**6.5 — Upgrade do Open WebUI 0.11.4 → 0.12.3 (2026-10-18):**

- O digest pinado do `:main` estava defasado (0.11.4) → banner "nova versão disponível".
  Re-pinado para **v0.12.3** (`ghcr.io/open-webui/open-webui@sha256:a537bbe1…`).
- **Breaking change**: 0.12+ exige **sessão humana** (JWT `typ=session`) em `/api/v1/auths/`;
  API key resolve o usuário mas é rejeitada com `403 {"detail":"A human session is required."}`.
- Consequência prática: o smoke (`tests/smoke_rag.py`) deixou de usar API key. Agora ele
  assina um JWT HS256 com o `WEBUI_SECRET_KEY` (lido de `/proc/1/environ`) + o
  `session_stamp` da conta em `auth` — exatamente o que o login valida — e **não** liga
  mais `auth.enable_api_keys` (fecha a janela de segurança que existia no teste).
- Rotas de Knowledge: `GET /api/v1/knowledge/list` → agora `GET /api/v1/knowledge/`;
  `create`, `{id}/file/add`, `{id}/delete` seguem iguais. Coleções `owui_*` inalteradas.
- E2E revalidado: upload → Docling → bge-m3 → 2 pontos em `owui_knowledge` (tenant=kb) →
  resposta *"vigência de 24 meses ... multa de 10% ... [1]"* → cleanup ok.
- Novos checks na suíte (84 → **88**): versão do OWUI, sessão humana aceita,
  API key **não** vale como sessão, PyJWT presente.

**Pendências (decisão do escritório / fases seguintes):** verificação de citação
(texto-citado-existe-no-chunk), política de retenção/expurgo LGPD, backup **off-site**
(o destino atual é a mesma máquina do repositório) e upgrade do Qdrant (1.15.2 → atual).

### Fase 7 — CI do oráculo (N2) + correções de Grafana (2026-10-18) — CONCLUÍDA

**Objetivo:** o oráculo deixa de depender de alguém digitando `bash tests/verify_stack.sh`
— fecha o **N2** do mapa mental ("teste automatizado **+ CI**") e torna o resultado
visível **sem SSH**.

**Como funciona:**

```
cron 04:10 (após o backup 03:30)
   └─ /usr/local/bin/hermes-ci   (ops/bin/ci_run.sh)
        ├─ roda tests/verify_stack.sh            → ~/ci/logs/ci-<UTC>.log (retenção 30)
        ├─ grava resumo                          → ~/ci/last-run.json  (+ last.log)
        └─ escreve ci/textfile/hermes_ci.prom    → node-exporter (textfile collector)
                                                    → Prometheus → Grafana
```

- **Métricas** (7): `hermes_ci_last_run_success`, `_last_run_timestamp_seconds`,
  `_duration_seconds`, `_checks_total`, `_checks_failed`, `_checks_warned`,
  `_suite_info{sha256}` — o hash da suíte executada fica auditável.
- `node-exporter` ganhou `--collector.textfile.directory=/textfile` + bind `./ci/textfile`.
- **Dashboard** `Hermes Lab — Host & Containers`: 4 painéis novos no topo
  (*Oráculo (CI)*, *Checks com falha*, *Última execução (atrás)*, *Duração*) → 11 painéis.
- `ops/deploy/sync-to-host.ps1`: espelha o repositório para o host, **confere o sha256 da suíte
  nos dois lados** (drift = erro), aplica permissões, (re)instala runner+cron e rodou o CI.
  É o "deploy" do lab: editar aqui → sincronizar.
- Suíte: 88 → **99 checks**. Novo helper **`warn()`**: aviso **não** derruba o CI. Motivo:
  o estado do próprio CI é auto-referente — se fosse `FAIL`, a suíte ficaria **travada em
  vermelho para sempre** (todo run verde reportaria o vermelho do run anterior).

**Bug encontrado (existia desde a 6.3) — dashboard nunca foi provisionado:**
`monitoring/` estava `700` (umask do host) e o Grafana roda como **uid 472** → log
`provisioning.dashboard ... failed to walk provisioned dashboards: permission denied`.
O Grafana subia e respondia `/api/health`, mas **o dashboard não existia** — o check antigo
só olhava o arquivo no disco, não o que o Grafana carregou. Correção: `chmod -R a+rX
monitoring/` (o sync agora força) + checks que perguntam à **API do Grafana**.

**Bug 2 — credencial documentada errada:** `GF_SECURITY_ADMIN_PASSWORD` só é aplicada na
**primeira** criação do admin no volume; a senha do `.env` não era a do banco. Resetada com
`grafana cli --homepath /usr/share/grafana admin reset-admin-password "$PW"` (só vale após
**reiniciar**) e verificada de duas formas: pbkdf2 do banco == senha do `.env` e `GET /api/user` = 200.

**Pegadinhas (novas, anotadas para não repetir):**
1. **Brute-force do Grafana é persistente:** 5 logins errados gravam em `login_attempt` e o
   usuário fica *"temporarily blocked"* — **sobrevive a restart**. Desbloquear: `docker stop grafana`,
   `delete from login_attempt`, `docker cp` de volta, `docker start`. Na suíte, **1** tentativa por run.
2. `docker cp` de volta no `grafana.db` deixa o arquivo com o uid do host (1000) → SQLite
   `unable to open database file (14)`. Corrigir com `chown 472:472` + `chmod 640` (uid `grafana` = 472).
3. `bge-m3` no `verify_stack.sh`: o Ollama **serializa** modelos; se um `qwen3` estiver residente,
   a 1ª chamada espera o *swap* (medido: 63-90 s). Timeout subiu para 120 s + 1 retentativa
   (era 30 s → falso negativo com a GPU ocupada).

**Fail-first (teste negativo do CI):** suíte falsa que falha → `exit=1`, `last-run.json`
`success:false`, métrica `0` e Prometheus servindo `0`; suíte real restaurada → `PASS=99 FAIL=0 WARN=0`.

**Bug 3 — o agendador não existia (o mais grave):** o pacote **`cron` não estava instalado**
no host (`dpkg -l cron` → `un`). As entradas em `/etc/cron.d` (backup 03:30 desde a 6.4 e CI
04:10) existiam, mas **nunca rodaram** — nem o backup diário. A suíte só checava a existência
do arquivo, não o daemon; e os artefatos de backup que existiam tinham sido feitos à mão.
Correção: `apt-get install -y cron` + `systemctl enable --now cron`. Provado de ponta a ponta
agendando cada um a cada minuto e vendo o evento disparar:
`CRON[...]` no syslog → `CI OK: PASS=99` e `hermes-20261018T090401Z.tar.gz` (3.8M).
Novos checks na suíte: `cron` **ativo** e **habilitado no boot** + as duas entradas.

**Pendência que ficou visível:** o backup (6.4) **não** inclui o volume `grafana_data`
(usuários/orgs/prefs do Grafana). Dashboards e datasource são provisionados por arquivo e
voltam sozinhos; o resto se recria. Incluir `grafana.db` no `hermes-backup` é melhoria opcional.

### Fase 6a - Estabilizar e endurecer (2026-10-10)

**6a.1 Latencia - decisao: voltar ao estado limpo (thinking).** Medicoes reais na RX 6600 (8 GB):

| Cenario | Tempo/turno | Resposta |
|---|---|---|
| `qwen3:4b-64k` + thinking, tools completas | **91 s** | limpa |
| `qwen3:4b-64k` + thinking, toolset enxuto | **70 s** | limpa |
| `qwen3:4b-64k` + `reasoning_effort: none` | 77-127 s | **narra o raciocinio na resposta** (e em ingles) |

Restricoes descobertas (medicoes, nao palpites):
- **So a familia qwen3 serve 64K aqui.** `qwen2.5:7b-instruct` (4,6 s, resposta impecavel) e
  `qwen2.5:3b-instruct` travam em **32.768** - e o contexto **nativo** deles, nao VRAM - e sao
  reprovados pelo piso de 64.000 do Hermes.
- **`think:false` e `/no_think` NAO desligam o thinking do qwen3** no Ollama 0.40.2 (ambos testados).
  O `TEMPLATE` custom do Modelfile e **ignorado** - `/api/show` devolve o template do registry.
- System prompt do Hermes ~ **15,5k tokens** -> ~28 s por chamada a ~560 tok/s, antes de gerar token
  algum. Enxugar o toolset economiza ~21 s/turno (-23%).

**6a.2 Rede.** ufw instalado e ativo (`deny incoming`; allow `22/3000/8642/9119`). Ponto critico:
**o Docker ignora o ufw** - portas publicadas entram por `PREROUTING -> FORWARD -> DOCKER-USER`, nunca por
`INPUT`. Sem regra nessa cadeia, "fechar o firewall" nao fecha nada. Por isso:
- `DOCKER-USER` com `DROP` em **6333 (Qdrant)** e **11434 (Ollama)** - so os containers precisam delas.
- Persistencia: `docker-firewall.service` (systemd, `After=docker.service`) + script idempotente.
  As regras vivem **so no kernel** (iptables nao e persistente): somem no reboot, e o servico as repoe.
  Provado esvaziando a cadeia e reiniciando o unit: os 2 `DROP` voltam, e 3 execucoes seguidas nao
  duplicam nada. Os dois arquivos sao **versionados** em `ops/bin/docker-firewall.sh` e
  `ops/systemd/docker-firewall.service` e instalados pelo `sync-to-host.ps1` — antes existiam so no host
  (num rebuild as regras nao voltariam).
- **Validar sempre de outra maquina:** curl do host para o proprio IP passa por `OUTPUT` e mente
  (200 mesmo com a regra ativa). Teste valido: `curl http://192.168.15.231:6333` de outro host -> 000.
- O host so tem interface de LAN (`ens18`), sem WAN - a ameaca e a propria rede local.

**6a.3 Higiene.** Removidos: estado PM abandonado `installs.disabled-20261009-2150` (**3,4 GB**), 6
modelos experimentais que nao funcionaram (qwen2.5 x4, qwen3:4b-64k-nt/nt2 - **6,7 GB**) e 5 `.bak`
obsoletos. Ollama 15 GB -> **8,3 GB**; `.hermes` 4,1 GB -> **904 MB**.

## 4. Riscos conhecidos

| Risco | Impacto | Mitigação |
|---|---|---|
| user_id não chega como e-mail | **Alto** — multiusuário falha silencioso | **Resolvido**: header `X-Hermes-Session-Key: {{USER_EMAIL}}` (OWUI) + fallback no plugin (patch reaplicar após update) |
| `plugins install --yes-deps` sequestra o `sys.path` (PM) | **Alto** — derruba o gateway sem erro claro | Não rodar `--yes-deps`; se rodar, `mv /opt/data/installs /opt/data/installs.disabled-<data>` |
| Piso de contexto 64K × VRAM 8 GB | **Alto** — modelo recusado no boot | `qwen3:4b-64k` (65.536 tokens reais, 87% GPU); 8B não serve a 64K usável |
| qwen3 *thinking* quebra extração do mem0 | Médio — `results: []` silencioso | Modelo de extração sem thinking (`qwen3:8b-extract`) em `mem0.json` |
| Patch do plugin sobrescrito por update | Médio | Reaplicar `__init__.py` após `hermes plugins update mem0` |
| mem0 ADD-only (fato velho ≠ novo) | Médio | Usar `mem0_update`/delete quando fatos mudarem |
| `sync_max_chars` default 450 | Baixo | Setado para 6000 (bge-m3 = 8k tokens) |
| Compose original perdido | Baixo | Specs recuperadas em `_archive/` + renders |
| Re-baixar modelos (~7 GB) | Baixo | Fase 2 demora — rodar em background |
| Porta 3000 (Open WebUI × Grafana) | Baixo | **Resolvido**: Grafana em `:3001` via nginx (TLS); OWUI em `:3000` só no loopback |
| Certificado autoassinado (aviso no navegador) | Baixo | Esperado em lab sem CA; importar `server.crt` como confiável nos PCs |
| Backup no mesmo PC do repositório | Médio | Destino atual é local; replicar off-site para DR real |
| Citação pode estar errada (modelo) | Médio | `[1]` aponta o chunk, mas não garante o texto; revisão humana + verificação futura |

## 5. Comandos de sempre (host)

```bash
# status geral
ssh davy-jones-hermes "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
# logs do hermes (mem0)
docker logs -f hermes-agent 2>&1 | grep -i mem0
# reset parcial do mem0 (apagar memórias, manter stack)
curl -X DELETE localhost:6333/collections/mem0_memories
```

## 6. Suíte de regressão (N2 aplicado — 2026-10-17)

O "oráculo" do lab: `tests/verify_stack.sh` (+ `tests/run-tests.ps1` para Windows, e as regras em `AGENTS.md`).
Checa **88 invariantes** — todos os fixes das fases viram testes. Rodar antes/depois de qualquer mudança.

```bash
# Windows
powershell -File tests/run-tests.ps1
# ou direto no host
bash tests/verify_stack.sh
```

Cobre: containers/health · Qdrant+coleção · Ollama+GPU+modelos · OWUI auth · gateway/mem0 ·
patch de identidade (Risco #1) · `tool_search: off` · conexão OWUI + header + **sem nuvem** ·
`model`+`access_grant` · isolamento (`user_id` ≠ `hermes-user`) · Fase 6 (Docling health,
`VECTOR_DB=qdrant`, prefixo `owui`, embeddings bge-m3/1024d, extração docling e `rag.*` efetivo ·
OWUI 0.12.3 + sessão humana · HTTPS/TLS na LAN · SearXNG com busca web desligada ·
Prometheus/Grafana · backup íntegro e recente · imagens pinadas) · firewall (ufw + DOCKER-USER).

Estado atual: **PASS=88 / FAIL=0**. Teste negativo confirmado (a suíte falha e retorna exit 1).

