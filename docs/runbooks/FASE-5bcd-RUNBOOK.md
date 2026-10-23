# Runbook — Fechar Fase 5b / 5c / 5d (Hermes × mem0 × Open WebUI)

> ## ✅ STATUS: CONCLUÍDO (2026-10-17)
> Verificado no host: **5c** (`tool_search: "off"`), **5b** (conexão `http://hermes:8642/v1` + header
> `X-Hermes-Session-Key: {{USER_EMAIL}}`) e **5d** (`model` + `access_grant`, visível p/ não-admin)
> já estão aplicados e validados. Isolamento A/B confirmado no Qdrant (`user_id` = e-mail).
> Este documento passa a valer como referência de **reprodução/recuperação**.

> Pré-requisito: host `davy-jones-hermes` (192.168.15.231) ligado e na rede.
> Verificar antes de qualquer coisa:
> ```bash
> ssh davy-jones-hermes "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
> ```
> Esperado: `qdrant`, `ollama`, `open-webui`, `hermes-agent` (e `hermes-dashboard`) todos `Up`/`healthy`.

---

## Ordem de execução

1. **5c** (config) — correção na config do Hermes (tool_search off). Rápida, só arquivo + restart.
2. **5b** (Open WebUI) — criar a conexão do Hermes no OWUI (na UI). Habilita o chat.
3. **5d** (Open WebUI/DB) — liberar o modelo `hermes-agent` para usuários comuns (SQL).
4. **Validação A/B no navegador** (usuário comum × 2 contas).

> Regra: cada passo tem verificação. Só avançar quando a anterior passar.

---

## Fase 5c — ponte de tools desligada

**Sintoma que isso corrige:** chat "trava", Ollama gerando sem parar (task 900+ tokens), `qwen3:4b` não monta o array `calls`.

**Editar** `hermes-data/config.yaml` **no host** (bind-mount → `/opt/data/config.yaml` dentro do container):

```yaml
tools:
  tool_search:
    enabled: "off"
```

**Aplicar:**
```bash
ssh davy-jones-hermes "cd /home/tlandskron/hermes-architect && docker compose restart hermes"
# ou, se o arquivo estiver em ~/.hermes:
# cp ~/.hermes/config.yaml ~/.hermes/config.yaml.bak-$(date +%Y%m%d-%H%M)
```

**Verificar:**
```bash
ssh davy-jones-hermes "docker exec hermes-agent hermes config get tools.tool_search.enabled"
# esperado: off
curl -s http://192.168.15.231:8642/health
```

---

## Fase 5b — conexão do Hermes no Open WebUI

Ainda **não existe** conexão no OWUI (tabela `connection` vazia).

**Caminho na UI:** `http://192.168.15.231:3000` → ⚙️ *Admin Settings* → *Connections* → *OpenAI API* → **+**

| Campo | Valor |
|---|---|
| Base URL | `http://hermes:8642/v1` |
| API Key | `$API_SERVER_KEY` (no `.env` do host; nunca no repo) |
| Headers | `{"X-Hermes-Session-Key": "{{USER_EMAIL}}"}` |

⚠️ **Sem o header**, todo mundo cai no balde `hermes-user` (isolamento multiusuário quebra).
O `{{USER_EMAIL}}` é interpolado pelo OWUI (`open_webui/utils/headers.py`).

**Verificar (SQLite do OWUI — tabela `config`, NÃO `connection`):**
```bash
# as conexões ficam na tabela config, chaves openai.* (não existe tabela 'connection' nesta versão)
ssh davy-jones-hermes "docker exec open-webui python /tmp/owui_probe2.py"
# esperado:
#   openai.api_base_urls  -> ['https://api.openai.com/v1', 'http://hermes:8642/v1']
#   openai.api_configs['1'].headers -> {'X-Hermes-Session-Key': '{{USER_EMAIL}}'}
```

**Teste rápido do passo (mechanical) — sem navegador:**
```bash
curl -s http://192.168.15.231:8642/v1/models \
  -H "Authorization: Bearer $API_SERVER_KEY"
```

> Nota: em `/v1/chat/completions` a session key **não** funde conversas (o `session_id` é
> fingerprint da conversa). A resolução por chave declarada só existe em `/v1/responses`.

---

## Fase 5d — acesso ao modelo `hermes-agent` (OWUI 0.11.4)

Nesta versão **todo modelo de conexão nasce privado** (só admin vê). São **duas** coisas; a 2ª é a que costuma faltar.

### SQL (dentro do container OWUI, DB = `/app/backend/data/webui.db`)

Descobrir o id do admin e os ids dos usuários de teste:
```bash
ssh davy-jones-hermes "docker exec open-webui python -c \"import sqlite3;c=sqlite3.connect('/app/backend/data/webui.db');print(c.execute('select id,email,role from user').fetchall())\""
```

**1) Registrar o modelo na tabela `model`** (sem linha aqui, nada aparece para usuário comum):
```sql
INSERT INTO model (id, user_id, base_model_id, name, params, meta, is_active, updated_at, created_at)
VALUES ('hermes-agent', '<ADMIN_USER_ID>', NULL, 'hermes-agent', '{}', '{}', 1,
        strftime('%s','now'), strftime('%s','now'));
```

**2) Liberar leitura via `access_grant`:**
```sql
INSERT INTO access_grant (id, resource_type, resource_id, principal_type, principal_id, permission, created_at)
VALUES (lower(hex(randomblob(16))), 'model', 'hermes-agent', 'user', '*', 'read', strftime('%s','now'));
```

⚠️ **Pegadinha:** "público" é `principal_type='user'` + `principal_id='*'` — **NÃO** `'anyone'`.
A constante `PRINCIPAL_TYPE_ANYONE` existe só na conversão de ACL legado; `has_access()`
consulta literalmente `user` + `*`. Um grant `'anyone'` é silenciosamente ignorado.

**Cache:** `MODELS_CACHE_TTL` default é **1 s** → vale na próxima requisição, sem restart.

**Alternativa global (menos segura):** `BYPASS_MODEL_ACCESS_CONTROL=true` (ignora ACL de modelos para todos).

---

## Validação final (A/B no navegador)

Com **admin** e com **usuário comum**:

1. Login `admin@example.com` → conversa → diga: *"prefiro café coado"*.
2. Nova sessão (mesmo usuário) → *"que café eu gosto?"* → deve responder.
3. Login `teste@example.com` → *"o que o outro usuário gosta de beber?"* → **não pode saber**.

**Conferir no dado (isolamento real):**
```bash
ssh davy-jones-hermes "curl -s localhost:6333/collections/mem0_memories/points/scroll \
  -X POST -H 'Content-Type: application/json' \
  -d '{\"limit\":20,\"with_payload\":true}' | jq '.result.points[].payload.user_id'"
# esperado: e-mails distintos por memória (nunca hermes-user)
```

**Critério de "Fase 5b/5c/5d fechada":**
- [ ] `tools.tool_search.enabled = off`
- [ ] conexão `http://hermes:8642/v1` existe no OWUI, com header `X-Hermes-Session-Key`
- [ ] modelo `hermes-agent` visível para usuário **não-admin**
- [ ] turno fecha sem loop de tool_call (tool_search off)
- [ ] A/B: B não vê memória de A; `payload.user_id` = e-mail

---

## Se algo falhar

| Sintoma | Causa provável | Ação |
|---|---|---|
| Chat trava, Ollama gerando sem parar | 5c não aplicado (`tool_search` ainda `auto`) | aplicar `enabled: "off"` + restart |
| Usuário comum não vê o modelo | falta linha na tabela `model` **ou** grant `'anyone'` | refazer passo 1 e 2 com `user`+`*` |
| Todos compartilham memória | header `X-Hermes-Session-Key` ausente | recriar conexão com o header |
| `user_id` = `hermes-user` | patch do plugin mem0 perdido (update) | reaplicar `__init__.py` (ver plano, Risco #1) |
| Gateway unhealthy, 8642 fechada | `plugins install --yes-deps` sequestrou o venv | `mv /opt/data/installs /opt/data/installs.disabled-$(date +%Y%m%d)` |
