#!/usr/bin/env bash
# =============================================================================
# verify_stack.sh — Suíte de REGRESSÃO do lab davy-jones-hermes
# Roda NO HOST (ou via: ssh davy-jones-hermes 'bash -s' < verify_stack.sh)
#
# Cada item corresponde a um fix/validação de uma fase. Se um fix regredir,
# o teste correspondente FALHA. Este é o "oráculo" do projeto.
#
# Exit: 0 = tudo passou · 1 = houve falha
# =============================================================================
set -u

# A chave do gateway vive no .env do host (nunca no repo): é lida do ambiente do
# container, que é a fonte efetiva no runtime.
KEY=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' hermes-agent 2>/dev/null | sed -n 's/^API_SERVER_KEY=//p' | head -1)
HERMES_DIR="/home/usuario/.hermes"

PASS=0
FAIL=0
WARN=0

section() { printf '\n== %s ==\n' "$1"; }
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
warn(){ printf '  WARN  %s\n' "$1"; WARN=$((WARN + 1)); }
info(){ printf '  INFO  %s\n' "$1"; }
has() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

# ---------------------------------------------------------------------------
section "INFRA — containers"
for c in qdrant ollama docling open-webui nginx searxng prometheus node-exporter cadvisor grafana hermes-agent hermes-dashboard; do
  st=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo missing)
  if [ "$st" = "running" ]; then ok "container $c running"; else bad "container $c ($st)"; fi
done
for c in qdrant ollama docling open-webui nginx searxng prometheus node-exporter cadvisor grafana hermes-agent hermes-dashboard; do
  h=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$c" 2>/dev/null || echo missing)
  # `none` era aceito antes: um container sem healthcheck passava como "ok".
  # Up != vivo — todos os 12 precisam de healthcheck de verdade (#5 do relatório).
  if [ "$h" = "healthy" ]; then ok "health $c = healthy"; else bad "health $c = $h (esperado healthy)"; fi
done

# Rotação de logs do Docker (#6 do relatório): sem max-size o json-file cresce
# sem limite. Vale para todo container em execução, inclusive os criados depois.
semrot=""
for c in $(docker ps --format '{{.Names}}'); do
  lo=$(docker inspect -f '{{.HostConfig.LogConfig.Type}}/{{index .HostConfig.LogConfig.Config "max-size"}}' "$c" 2>/dev/null)
  case "$lo" in json-file/*m|json-file/*k|json-file/*M|json-file/*K) ;; *) semrot="$semrot $c" ;; esac
done
if [ -z "$semrot" ]; then ok "todos os containers com rotação de log"; else bad "sem rotação de log:$semrot"; fi
if grep -q 'max-size' /etc/docker/daemon.json 2>/dev/null; then ok "daemon.json com rotação instalado"; else bad "/etc/docker/daemon.json ausente ou sem max-size"; fi

# ---------------------------------------------------------------------------
section "QDRANT (Fase 1)"
col=$(curl -s --max-time 5 http://localhost:6333/collections)
if has "$col" "mem0_memories"; then ok "coleção mem0_memories existe"; else bad "coleção mem0_memories ausente"; fi

# Upgrade do Qdrant (2026-10-20): 1.15.2 -> 1.16.3 -> 1.19.2. O salto direto NÃO
# funciona (o índice de payload `rocks_db` do 1.15 não é lido pelo 1.19); o degrau
# 1.16 converte o volume. tools/verify_qdrant_upgrade.sh prova a cadeia numa cópia
# do volume antes de tocar em produção. Aqui garantimos que a versão que está no
# ar é a mesma que o compose manda — drift silencioso é como um "upgrade" volta atrás.
qrun=$(curl -s --max-time 5 http://localhost:6333/ | python3 -c 'import sys,json;print(json.load(sys.stdin).get("version",""))' 2>/dev/null)
qpin=$(grep -oE 'qdrant/qdrant:v[0-9.]+' /home/usuario/hermes-architect/docker-compose.yml | head -1 | sed 's|.*:v||')
if [ -n "$qrun" ] && [ "$qrun" = "$qpin" ]; then
  ok "Qdrant no ar = compose (v$qrun)"
else
  bad "Qdrant no ar (v${qrun:-?}) != compose (v${qpin:-?}) — drift entre imagem e container"
fi

# ---------------------------------------------------------------------------
section "OLLAMA + GPU (Fase 2)"
tags=$(curl -s --max-time 5 http://localhost:11434/api/tags)
for m in bge-m3 qwen3:4b-64k qwen3:8b-extract; do
  if has "$tags" "$m"; then ok "modelo $m presente"; else bad "modelo $m ausente"; fi
done
hsa=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' ollama 2>/dev/null | grep -c 'HSA_OVERRIDE_GFX_VERSION=10.3.0')
if [ "$hsa" -ge 1 ]; then ok "HSA_OVERRIDE_GFX_VERSION=10.3.0"; else bad "HSA_OVERRIDE_GFX_VERSION ausente"; fi

# GPU: com 64k de contexto, o KV em q8_0 fazia o qwen3 (8.3 GB) estourar os 8 GB
# da RX 6600 -> 13% das camadas em CPU e ~31 tok/s. Com KV q4_0 ele cabe inteiro
# (5.6 GB, 100% GPU, ~62 tok/s) e convive com o bge-m3 (664 MB) sem swap.
oenv=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' ollama 2>/dev/null)
if has "$oenv" "OLLAMA_KV_CACHE_TYPE=q4_0"; then ok "KV cache q4_0 (qwen3 cabe na GPU)"; else bad "KV cache != q4_0 (modelo volta a transbordar para a CPU)"; fi
if has "$oenv" "OLLAMA_MAX_LOADED_MODELS=2"; then ok "OLLAMA_MAX_LOADED_MODELS=2 (chat + embedding juntos)"; else bad "OLLAMA_MAX_LOADED_MODELS != 2 (embedding expulsa o chat)"; fi
# Funcional: carrega os dois e confere que ficam residentes, ambos 100% na GPU.
curl -s -m 120 http://localhost:11434/api/generate \
  -d '{"model":"qwen3:4b-64k","prompt":"ok","stream":false,"options":{"num_predict":4},"keep_alive":"5m"}' >/dev/null 2>&1
curl -s -m 120 http://localhost:11434/api/embed \
  -d '{"model":"bge-m3","input":"teste","keep_alive":"5m"}' >/dev/null 2>&1
ops=$(docker exec ollama ollama ps 2>/dev/null)
if printf '%s' "$ops" | grep -q 'qwen3:4b-64k.*100% GPU'; then
  ok "qwen3:4b-64k inteiro na GPU (sem offload para CPU)"
else
  bad "qwen3:4b-64k com offload para CPU: $(printf '%s' "$ops" | grep qwen3:4b-64k | tr -s ' ')"
fi
nres=$(printf '%s\n' "$ops" | grep -cE '^(qwen3:4b-64k|bge-m3:latest) ')
if [ "$nres" -ge 2 ]; then ok "chat + bge-m3 residentes ao mesmo tempo (sem swap por consulta)"; else warn "só $nres modelo(s) residente(s) — swap a cada consulta RAG"; fi

# ---------------------------------------------------------------------------
section "OPEN WEBUI (Fase 3)"
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:3000/health)
if [ "$code" = "200" ]; then ok "OWUI /health = 200"; else bad "OWUI /health = $code"; fi
auth=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' open-webui 2>/dev/null | grep -c 'WEBUI_AUTH=true')
if [ "$auth" -ge 1 ]; then ok "WEBUI_AUTH=true (login obrigatório)"; else bad "WEBUI_AUTH != true"; fi

# ---------------------------------------------------------------------------
section "HERMES gateway + mem0 (Fase 4)"
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:8642/health)
if [ "$code" = "200" ]; then ok "gateway /health = 200"; else bad "gateway /health = $code"; fi
models=$(curl -s --max-time 5 http://localhost:8642/v1/models -H "Authorization: Bearer $KEY")
if has "$models" "hermes-agent"; then ok "gateway /v1/models -> hermes-agent"; else bad "gateway /v1/models sem hermes-agent"; fi
memstatus=$(docker exec hermes-agent hermes memory status 2>/dev/null)
if has "$memstatus" "Provider:  mem0"; then ok "memory provider = mem0"; else bad "memory provider != mem0"; fi
if has "$memstatus" "active"; then ok "plugin mem0 ativo"; else bad "plugin mem0 não está ativo"; fi

# Endurecimento do gateway (#4): a ferramenta `shell` roda LOCAL, dentro do
# hermes-agent. Se o container montar o socket do Docker, um pedido no chat vale
# root no host; se montar ~/.ssh, vale as chaves. Nenhum dos dois é necessário.
hmounts=$(docker inspect hermes-agent --format '{{range .Mounts}}{{.Source}} {{end}}' 2>/dev/null)
if has "$hmounts" "docker.sock"; then
  bad "hermes-agent monta docker.sock (chat = root no host)"
else
  ok "hermes-agent sem docker.sock (shell não alcança o Docker do host)"
fi
if printf '%s' "$hmounts" | grep -qE '(^|/)\.ssh( |$)'; then
  bad "hermes-agent monta ~/.ssh (chaves do host legíveis pelo chat)"
else
  ok "hermes-agent sem ~/.ssh"
fi

# Higiene da memória (#7): o mem0 é ADD-only; o job diário dedupa e aplica o teto.
if [ -x /usr/local/bin/mem0-maintenance ]; then ok "mem0-maintenance instalado"; else bad "mem0-maintenance ausente (a memória volta a crescer sem limite)"; fi
if [ -f /etc/cron.d/mem0-maintenance ]; then ok "cron da manutenção do mem0 instalado"; else bad "cron /etc/cron.d/mem0-maintenance ausente"; fi
dups=$(curl -s --max-time 10 -X POST http://localhost:6333/collections/mem0_memories/points/scroll \
  -H 'Content-Type: application/json' -d '{"limit":2000,"with_payload":true,"with_vector":false}' 2>/dev/null \
  | python3 -c '
import sys, json
try:
    pts = json.load(sys.stdin)["result"]["points"]
except Exception:
    print("err"); raise SystemExit
seen, dup = set(), 0
for p in pts:
    pl = p.get("payload") or {}
    if pl.get("hash"):
        k = (pl.get("user_id"), pl.get("hash"))
        if k in seen: dup += 1
        else: seen.add(k)
print(dup)
' 2>/dev/null)
if [ "${dups:-err}" = "0" ]; then ok "mem0 sem duplicatas exatas (user_id+hash)"; else bad "mem0 com ${dups:-?} duplicata(s) exata(s)"; fi

# ---------------------------------------------------------------------------
section "RISCO #1 — identidade por usuário (Fase 5)"
if grep -q 'gateway_session_key' "$HERMES_DIR/plugins/mem0/__init__.py" 2>/dev/null; then
  ok "patch do plugin (gateway_session_key) presente"
else
  bad "patch do plugin AUSENTE (reaplicar após 'hermes plugins update mem0')"
fi
if [ -f "$HERMES_DIR/plugins/mem0/__init__.py.bak-labpatch-20261009" ]; then
  ok "backup do patch existe"
else
  bad "backup do patch ausente"
fi
if grep -q 'MEM0_USER_ID' "$HERMES_DIR/.env" 2>/dev/null; then
  bad "MEM0_USER_ID fixo no .env (une todos os usuários num balde só)"
else
  ok "sem MEM0_USER_ID fixo"
fi

# ---------------------------------------------------------------------------
section "CONFIG do Hermes (Fase 5c)"
if grep -A2 'tool_search:' "$HERMES_DIR/config.yaml" 2>/dev/null | grep -q 'off'; then
  ok "tools.tool_search.enabled = off"
else
  bad "tool_search não está 'off' (chat pode travar em loop de tool_call)"
fi
if grep -q 'qwen3:4b-64k' "$HERMES_DIR/config.yaml" 2>/dev/null; then
  ok "modelo de chat = qwen3:4b-64k"
else
  bad "modelo de chat != qwen3:4b-64k"
fi

# O repo guarda uma CÓPIA de config.yaml que NÃO é a montada (o container monta
# ~/.hermes). Cópia que ninguém aplica apodrece em silêncio: em 2026-10-20 o repo
# estava em temperature 0.7 e a produção em 0.3 — um rebuild pelo repo desfaria
# o fix #8 sem aviso. Aqui a divergência vira FAIL, não surpresa.
REPO_CFG=/home/usuario/hermes-architect/hermes-data/config.yaml
if [ -f "$REPO_CFG" ]; then
  if diff -q <(sed -e '$a\' "$REPO_CFG") <(sed -e '$a\' "$HERMES_DIR/config.yaml") >/dev/null 2>&1; then
    ok "config do Hermes: repo == produção (sem deriva)"
  else
    bad "config do Hermes diverge do repo — repo: $(grep -m1 temperature "$REPO_CFG" | tr -d ' ') | prod: $(grep -m1 temperature "$HERMES_DIR/config.yaml" | tr -d ' ')"
  fi
else
  warn "cópia do config no repo ausente ($REPO_CFG) - rode ops/deploy/sync-to-host.ps1"
fi

# ---------------------------------------------------------------------------
section "OPEN WEBUI DB — conexão e acesso (Fases 5b/5d)"
cat > /tmp/_owui_check.py <<'PY'
import sqlite3
c = sqlite3.connect('/app/backend/data/webui.db')
def g(k):
    r = c.execute('select value from config where key=?', (k,)).fetchone()
    return r[0] if r else ''
print('URLS=' + str(g('openai.api_base_urls')))
print('CFG=' + str(g('openai.api_configs')))
print('MODEL=' + str(c.execute("select count(*) from model where id='hermes-agent' and is_active=1").fetchone()[0]))
print('GRANT=' + str(c.execute("select count(*) from access_grant where resource_id='hermes-agent' and principal_type='user' and principal_id='*' and permission='read'").fetchone()[0]))
PY
docker cp /tmp/_owui_check.py open-webui:/tmp/_owui_check.py >/dev/null 2>&1
ow=$(docker exec open-webui python /tmp/_owui_check.py 2>/dev/null)

if has "$ow" "hermes:8642"; then ok "conexão Hermes presente (http://hermes:8642/v1)"; else bad "conexão Hermes ausente"; fi
if has "$ow" "X-Hermes-Session-Key"; then ok "header X-Hermes-Session-Key presente"; else bad "header de sessão ausente"; fi
if has "$ow" "USER_EMAIL"; then ok "header usa {{USER_EMAIL}}"; else bad "header não usa {{USER_EMAIL}}"; fi
if has "$ow" "api.openai.com"; then bad "conexão de NUVEM ainda presente (viola 100% local)"; else ok "sem conexão de nuvem (100% local)"; fi
# Eixo de estudos: o chat de estudo NÃO passa pelo gateway. O gateway monta o repo
# em /workspace e injeta o AGENTS.md (36 KB) + ferramentas: 21,6k tokens por
# chamada (65-91 s cada). Medido em 2026-10-21, o mesmo pedido direto no Ollama
# com os mesmos chunks levou 12-34 s.
if has "$ow" "ollama:11434"; then ok "conexão local Ollama (chat de estudo) presente"; else bad "conexão local Ollama ausente"; fi
if docker exec ollama ollama list 2>/dev/null | grep -q '^qwen3:8b-chat-16k'; then
  ok "modelo de estudo qwen3:8b-chat-16k presente (16k ctx, cabe 100% na GPU)"
else
  bad "modelo qwen3:8b-chat-16k ausente (chat de estudo sem modelo)"
fi

if has "$ow" "MODEL=1"; then ok "model hermes-agent registrado e ativo"; else bad "model hermes-agent ausente/inativo"; fi
if has "$ow" "GRANT=1"; then ok "access_grant user/* read presente"; else bad "access_grant ausente"; fi

# ---------------------------------------------------------------------------
section "MEMÓRIA — isolamento no dado (Fase 5)"
body='{"limit":100,"with_payload":true,"with_vector":false}'
pts=$(curl -s --max-time 10 http://localhost:6333/collections/mem0_memories/points/scroll \
        -X POST -H 'Content-Type: application/json' -d "$body")
if has "$pts" 'hermes-user'; then
  bad "encontrado user_id='hermes-user' (balde compartilhado — isolamento quebrado!)"
else
  ok "nenhum user_id = hermes-user"
fi
if has "$pts" '"user_id":"'; then ok "memórias com user_id próprio (isoladas)"; else info "coleção sem memórias ainda (não é falha)"; fi

# ---------------------------------------------------------------------------
section "FASE 6 — RAG jurídica (Docling + Qdrant + bge-m3)"
dcode=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:5001/health)
if [ "$dcode" = "200" ]; then ok "docling /health = 200"; else bad "docling /health = $dcode"; fi

owenv=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' open-webui 2>/dev/null)
if has "$owenv" "VECTOR_DB=qdrant"; then ok "VECTOR_DB=qdrant (Qdrant compartilhado)"; else bad "VECTOR_DB != qdrant"; fi
if has "$owenv" "QDRANT_COLLECTION_PREFIX=owui"; then ok "coleções RAG prefixadas (owui_*)"; else bad "prefixo de coleção RAG ausente"; fi
if has "$owenv" "RAG_EMBEDDING_MODEL=bge-m3"; then ok "embeddings RAG = bge-m3"; else bad "embeddings RAG != bge-m3"; fi
if has "$owenv" "CONTENT_EXTRACTION_ENGINE=docling"; then ok "extração = docling"; else bad "extração != docling"; fi

# valores efetivos no DB (PersistentConfig ignora env depois do 1º boot)
cat > /tmp/_owui_rag.py <<'PY'
import sqlite3
c = sqlite3.connect('/app/backend/data/webui.db')
def g(k):
    r = c.execute('select value from config where key=?', (k,)).fetchone()
    return '' if r is None else str(r[0]).strip('"')
print('EMB_ENGINE=' + g('rag.embedding_engine'))
print('EMB_MODEL=' + g('rag.embedding_model'))
print('EXTRACT=' + g('rag.content_extraction_engine'))
print('DOCLING=' + g('rag.docling_server_url'))
print('PARAMS=' + g('rag.docling_params'))
print('BYPASS=' + g('rag.bypass_embedding_and_retrieval'))
print('SPLITTER=' + g('rag.enable_markdown_header_text_splitter'))
print('CHUNK=' + g('rag.chunk_size'))
print('OVERLAP=' + g('rag.chunk_overlap'))
print('TOPK=' + g('rag.top_k'))
print('HYBRID=' + g('rag.enable_hybrid_search'))
print('TAGS=' + g('task.tags.enable'))
print('FOLLOWUP=' + g('task.follow_up.enable'))
print('TASKMODEL=' + g('task.model.default'))
PY
docker cp /tmp/_owui_rag.py open-webui:/tmp/_owui_rag.py >/dev/null 2>&1
rag=$(docker exec open-webui python /tmp/_owui_rag.py 2>/dev/null)
if has "$rag" "EMB_ENGINE=ollama"; then ok "rag.embedding_engine = ollama (local)"; else bad "rag.embedding_engine != ollama"; fi
if has "$rag" "EMB_MODEL=bge-m3"; then ok "rag.embedding_model = bge-m3"; else bad "rag.embedding_model != bge-m3"; fi
if has "$rag" "EXTRACT=docling"; then ok "rag.content_extraction_engine = docling"; else bad "extração efetiva != docling"; fi
if has "$rag" "DOCLING=http://docling:5001"; then ok "docling_server_url interno correto"; else bad "docling_server_url errado"; fi
if has "$rag" "do_ocr"; then ok "docling_params com OCR (pt)"; else bad "docling_params sem OCR"; fi
if has "$rag" "BYPASS=false"; then ok "RAG não está bypassado"; else bad "rag.bypass_embedding_and_retrieval != false"; fi

# Chunking do eixo de estudos (2026-10-21): o splitter de cabeçalho fatiava o
# markdown do Docling em cada `## Questão N` -> 88 chunks de 281 chars (um de
# 13). Com ele desligado e 1200/200 a mesma prova virou 30 chunks de ~850.
if has "$rag" "SPLITTER=false"; then ok "chunking: splitter de cabeçalho desligado"; else bad "splitter de cabeçalho ligado (chunks de 13 chars)"; fi
if has "$rag" "CHUNK=1200"; then ok "rag.chunk_size = 1200"; else bad "rag.chunk_size != 1200"; fi
if has "$rag" "OVERLAP=200"; then ok "rag.chunk_overlap = 200"; else bad "rag.chunk_overlap != 200"; fi
# top_k=8 é necessário para a página do gabarito com a resposta da Q26 entrar no
# contexto (a 3/6 ela ficava de fora e o modelo dizia "não encontrei").
if has "$rag" "TOPK=8"; then ok "rag.top_k = 8"; else bad "rag.top_k != 8"; fi
if has "$rag" "HYBRID=true"; then ok "busca híbrida (BM25 + vetor) ligada"; else bad "busca híbrida desligada"; fi
# Cada geração auxiliar é uma chamada de LLM por mensagem (título/tags/follow-up).
# Com o gateway a 21,6k tokens isso somava ~400 s por pergunta.
if has "$rag" "TAGS=false"; then ok "OWUI sem geração de tags"; else bad "geração de tags ligada (1 chamada de LLM/mensagem)"; fi
if has "$rag" "FOLLOWUP=false"; then ok "OWUI sem geração de follow-up"; else bad "follow-up ligado (1 chamada de LLM/mensagem)"; fi
if has "$rag" "TASKMODEL=qwen3:8b-chat-16k"; then ok "gerações auxiliares usam o modelo de estudo (nunca o gateway)"; else bad "task.model.default != qwen3:8b-chat-16k"; fi

# Docling é alcançável de dentro do OWUI (DNS da rede backend)
reach=$(docker exec open-webui python -c 'import urllib.request; print(urllib.request.urlopen("http://docling:5001/health", timeout=5).status)' 2>/dev/null)
if has "$reach" "200"; then ok "OWUI alcança docling (200)"; else bad "OWUI não alcança docling ($reach)"; fi

# embedding local real: bge-m3 deve devolver 1024 dimensões.
# O Ollama serializa modelos: se outro modelo estiver residente (ex.: qwen3 em uso),
# a 1ª chamada espera o swap — daí timeout folgado + 1 retentativa (flakiness no CI).
dim=""
for _try in 1 2; do
  dim=$(curl -s --max-time 120 http://localhost:11434/api/embed -d '{"model":"bge-m3","input":"teste"}' | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["embeddings"][0]))' 2>/dev/null)
  [ "$dim" = "1024" ] && break
  sleep 5
done
if [ "$dim" = "1024" ]; then ok "bge-m3 -> 1024 dims"; else bad "bge-m3 dims = ${dim:-erro}"; fi

# knowledge_file: o OWUI 0.12.3 NÃO apaga a linha de ligação ao remover o
# knowledge/file. Três execuções do smoke deixaram 3 órfãs (bug real) — o smoke
# passou a limpar explicitamente, e este check garante que o banco não volta a sujar.
orph=$(docker exec open-webui python3 -c "
import sqlite3
c = sqlite3.connect('/app/backend/data/webui.db')
print(c.execute('''select count(*) from knowledge_file
  where knowledge_id not in (select id from knowledge)
     or file_id not in (select id from file)''').fetchone()[0])
" 2>/dev/null)
if [ "$orph" = "0" ]; then ok "sem linhas órfãs em knowledge_file"; else bad "knowledge_file com ${orph:-?} linha(s) órfã(s)"; fi
# Base de teste não pode ficar no banco do escritório (a "Teste raciocinio" ficou
# meses; removida em 2026-10-20 com tools/cleanup_owui_test_kb.py).
tst=$(docker exec open-webui python3 -c "
import sqlite3
c = sqlite3.connect('/app/backend/data/webui.db')
print(c.execute(\"select count(*) from knowledge where lower(name) like '%teste%'\").fetchone()[0])
" 2>/dev/null)
if [ "$tst" = "0" ]; then ok "nenhuma knowledge base de teste no OWUI"; else bad "${tst:-?} knowledge base(s) de teste no OWUI (use tools/cleanup_owui_test_kb.py)"; fi

# ---------------------------------------------------------------------------
section "OWUI — versão e sessão humana (v0.12.3+)"
owui_ver=$(curl -sk --max-time 8 https://localhost/api/version 2>/dev/null \
  | python3 -c 'import sys,json;print(json.load(sys.stdin).get("version",""))' 2>/dev/null)
if [ "$owui_ver" = "0.12.3" ]; then ok "OWUI 0.12.3 (pinado)"; else bad "OWUI versão = ${owui_ver:-?} (esperado 0.12.3)"; fi

# /api/v1/auths/ exige sessão humana (JWT typ=session); API key não serve mais.
cat > /tmp/_owui_session.py <<'PY'
import json, os, sqlite3, time, urllib.request
from datetime import datetime, timedelta, timezone

import jwt

DB = '/app/backend/data/webui.db'
ADMIN = 'admin@example.com'


def pid1_env(n):
    try:
        for p in open('/proc/1/environ', 'rb').read().split(b'\0'):
            if p.startswith(n.encode() + b'='):
                return p.split(b'=', 1)[1].decode()
    except OSError:
        pass
    return ''


secret = os.environ.get('WEBUI_SECRET_KEY') or pid1_env('WEBUI_SECRET_KEY')
c = sqlite3.connect(DB)
row = c.execute('select id from user where email=?', (ADMIN,)).fetchone()
if not row:
    print('NO_USER')
    raise SystemExit
uid = row[0]
stamp = c.execute('select session_stamp from auth where id=?', (uid,)).fetchone()[0]
tok = jwt.encode(
    {
        'id': uid,
        'typ': 'session',
        'auth_method': 'password',
        'auth_time': int(time.time()),
        'session_stamp': stamp,
        'mfa_verified': False,
        'exp': datetime.now(timezone.utc) + timedelta(minutes=5),
    },
    secret,
    algorithm='HS256',
)
req = urllib.request.Request(
    'http://127.0.0.1:8080/api/v1/auths/',
    headers={'Authorization': 'Bearer ' + tok},
)
with urllib.request.urlopen(req, timeout=15) as r:
    print('SESSION_OK', r.status, json.load(r).get('email'))
PY
docker cp /tmp/_owui_session.py open-webui:/tmp/_owui_session.py >/dev/null 2>&1
sess=$(docker exec open-webui python /tmp/_owui_session.py 2>&1 | tail -1)
if has "$sess" "SESSION_OK"; then ok "sessão humana (JWT typ=session) aceita"; else bad "sessão humana rejeitada ($sess)"; fi
apik=$(curl -sk --max-time 8 -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer sk-invalido' https://localhost/api/v1/auths/ 2>/dev/null)
if [ "$apik" = "401" ] || [ "$apik" = "403" ]; then ok "API key NÃO vale como sessão ($apik)"; else bad "API key aceita como sessão ($apik)"; fi
if docker exec open-webui python -c "import jwt" >/dev/null 2>&1; then ok "PyJWT disponível no container"; else bad "PyJWT ausente no container"; fi

# ---------------------------------------------------------------------------
section "FASE 6.2 — HTTPS na LAN (nginx)"
hcode=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 8 https://localhost/health)
if [ "$hcode" = "200" ]; then ok "https://localhost/health = 200"; else bad "HTTPS local = $hcode"; fi
rcode=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost/)
if [ "$rcode" = "301" ]; then ok "http :80 redireciona para HTTPS"; else bad "http :80 = $rcode (esperado 301)"; fi
owport=$(docker port open-webui 8080 2>/dev/null)
if has "$owport" "127.0.0.1:3000"; then ok "OWUI 3000 só no loopback"; else bad "OWUI exposto fora do loopback ($owport)"; fi
if [ -f /home/usuario/hermes-architect/nginx/certs/server.crt ]; then ok "certificado TLS presente"; else bad "certificado TLS ausente"; fi

# Renovação (#10): o cert é autoassinado — nada renova sozinho. Expirado = FAIL
# (HTTPS quebrado); <30 dias = WARN (estado do ambiente, igual às regras de alerta).
CRT=/home/usuario/hermes-architect/nginx/certs/server.crt
if [ -f "$CRT" ]; then
  if openssl x509 -in "$CRT" -noout -checkend 0 >/dev/null 2>&1; then
    if openssl x509 -in "$CRT" -noout -checkend $((30 * 86400)) >/dev/null 2>&1; then
      ok "certificado TLS válido por mais de 30 dias (expira $(openssl x509 -in "$CRT" -noout -enddate | cut -d= -f2))"
    else
      warn "certificado TLS expira em <30 dias — renove: tools/make_tls_cert.sh --force --reload"
    fi
  else
    bad "certificado TLS EXPIRADO — HTTPS quebrado (tools/make_tls_cert.sh --force --reload)"
  fi
  san=$(openssl x509 -in "$CRT" -noout -ext subjectAltName 2>/dev/null)
  if has "$san" "hermes-lab" && has "$san" "davy-jones-hermes"; then
    ok "SAN do certificado cobre os hostnames do lab"
  else
    bad "SAN do certificado não cobre hermes-lab/davy-jones-hermes"
  fi
  curip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')
  [ -n "$curip" ] || curip=$(hostname -I 2>/dev/null | awk '{print $1}')
  if [ -n "$curip" ] && has "$san" "$curip"; then
    ok "IP atual ($curip) está na SAN do certificado"
  else
    warn "IP atual (${curip:-?}) fora da SAN — regenere o cert se a LAN usa esse IP"
  fi
  # Renovou o arquivo e esqueceu o reload? O nginx continua servindo o antigo.
  served=$(echo | openssl s_client -connect 127.0.0.1:443 -servername hermes-lab 2>/dev/null | openssl x509 -noout -fingerprint -sha256 2>/dev/null)
  localfp=$(openssl x509 -in "$CRT" -noout -fingerprint -sha256 2>/dev/null)
  if [ -n "$served" ] && [ "$served" = "$localfp" ]; then
    ok "nginx serve o certificado do arquivo (fingerprint confere)"
  else
    bad "nginx serve certificado DIFERENTE do arquivo — faltou reload após renovar"
  fi
fi
tlsm=$(docker exec prometheus wget -qO- 'http://127.0.0.1:9090/api/v1/query?query=hermes_tls_cert_days_left' 2>/dev/null)
if has "$tlsm" '"value"'; then ok "métrica de validade do TLS exposta (hermes_tls_cert_*)"; else bad "métrica hermes_tls_cert_* ausente (cron tls-cert)"; fi
if [ -x /usr/local/bin/tls-cert-metrics ] && [ -f /etc/cron.d/tls-cert ]; then ok "métrica do TLS instalada + cron diário"; else bad "tls-cert-metrics e/ou cron /etc/cron.d/tls-cert ausentes"; fi
# Renovação provada em diretório isolado (nunca no cert de produção).
tdir=$(mktemp -d /var/tmp/tlsrenew.XXXXXX)
mkcert=/home/usuario/hermes-architect/tools/make_tls_cert.sh
if bash "$mkcert" --out "$tdir" --days 2 --force >/dev/null 2>&1 \
   && openssl x509 -in "$tdir/server.crt" -noout -checkend 86400 >/dev/null 2>&1 \
   && ! openssl x509 -in "$tdir/server.crt" -noout -checkend $((3 * 86400)) >/dev/null 2>&1; then
  ok "renovação gera par novo com a validade pedida (teste isolado)"
else
  bad "script de renovação falhou no teste isolado ($tdir)"
fi
fp1=$(sha256sum "$tdir/server.crt" 2>/dev/null | cut -d' ' -f1)
bash "$mkcert" --out "$tdir" --days 30 >/dev/null 2>&1
fp2=$(sha256sum "$tdir/server.crt" 2>/dev/null | cut -d' ' -f1)
if [ -n "$fp1" ] && [ "$fp1" = "$fp2" ]; then ok "renovação não sobrescreve sem --force"; else bad "script sobrescreveu certificado sem --force"; fi
bash "$mkcert" --out "$tdir" --days 30 --force >/dev/null 2>&1
if ls "$tdir"/server.crt.bak-* >/dev/null 2>&1; then ok "renovação guarda o par antigo (server.crt.bak-*)"; else bad "renovação sem cópia do par antigo"; fi
rm -rf "$tdir"

# ---------------------------------------------------------------------------
section "FASE 6.2b — SearXNG (instalado, busca web desligada)"
sx=$(docker exec open-webui python -c 'import urllib.request; print(urllib.request.urlopen("http://searxng:8080/healthz", timeout=5).status)' 2>/dev/null)
if has "$sx" "200"; then ok "OWUI alcança searxng (200)"; else bad "OWUI não alcança searxng ($sx)"; fi
if docker exec searxng grep -q 'json' /etc/searxng/settings.yml 2>/dev/null; then ok "searxng expõe formato json"; else bad "searxng sem formato json"; fi
owenv=$(docker inspect open-webui --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null)
if has "$owenv" "ENABLE_WEB_SEARCH=false"; then ok "OWUI busca web desligada (100% local)"; else bad "ENABLE_WEB_SEARCH != false"; fi
if has "$owenv" "SEARXNG_QUERY_URL=http://searxng:8080/search"; then ok "SEARXNG_QUERY_URL interno correto"; else bad "SEARXNG_QUERY_URL errado"; fi

# ---------------------------------------------------------------------------
section "FASE 6.3 — Monitoramento (Prometheus/Grafana)"
tg=$(docker exec prometheus wget -qO- 'http://127.0.0.1:9090/api/v1/targets?state=active' 2>/dev/null | grep -o '"health":"up"' | wc -l)
if [ "${tg:-0}" -ge 4 ]; then ok "prometheus com $tg alvos UP"; else bad "prometheus alvos UP = ${tg:-0} (esperado >=4)"; fi
gh=$(curl -sk --max-time 10 https://localhost:3001/api/health 2>/dev/null)
if has "$gh" '"database"' && has "$gh" 'ok'; then ok "grafana health ok via TLS :3001"; else bad "grafana health via TLS :3001 falhou"; fi
if has "$gh" '"version"'; then ok "grafana respondendo"; else bad "grafana sem resposta"; fi
if [ -f /home/usuario/hermes-architect/monitoring/grafana/dashboards/hermes-lab.json ]; then ok "dashboard hermes-lab provisionado"; else bad "dashboard hermes-lab ausente"; fi
gp=$(docker port grafana 2>/dev/null)
if [ -z "$gp" ]; then ok "grafana não publica porta (só via nginx)"; else bad "grafana publicando porta: $gp"; fi
# Login: o Grafana só aplica GF_SECURITY_ADMIN_PASSWORD no 1º boot do volume.
# Se o valor do .env divergir do banco, o escritório fica sem acesso — testa de verdade.
gadm=$(grep -h '^GRAFANA_ADMIN_PASSWORD=' /home/usuario/hermes-architect/.env 2>/dev/null | cut -d= -f2 | tr -d '\r')
gip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' grafana 2>/dev/null)
gcode=$(curl -s -o /tmp/_g.json -w '%{http_code}' --max-time 10 -u "admin:$gadm" "http://$gip:3000/api/user" 2>/dev/null)
# (só UMA tentativa por execução: login errado repetido aciona o brute-force do Grafana)
if [ "$gcode" = "200" ]; then ok "login do Grafana aceita a senha do .env"; else bad "login do Grafana falhou ($gcode) — senha do .env divergente do volume?"; fi
gdash=$(curl -s --max-time 10 -u "admin:$gadm" "http://$gip:3000/api/dashboards/uid/hermes-lab" 2>/dev/null)
if has "$gdash" 'hermes_ci_last_run_success'; then ok "dashboard hermes-lab carregado no Grafana"; else bad "dashboard não carregado no Grafana (permissão de leitura em monitoring/?)"; fi
# o processo do Grafana (uid 472) precisa de o+rx no diretório montado, senão o
# file provider falha com "permission denied" e o dashboard nunca aparece.
mperm=$(stat -c '%a' /home/usuario/hermes-architect/monitoring/grafana/dashboards 2>/dev/null)
case "$mperm" in
  *[57]) ok "dashboards legíveis por containers (modo $mperm)" ;;
  *)      bad "monitoring/grafana/dashboards sem o+rx (modo ${mperm:-?}) — Grafana não lê" ;;
esac
if [ -f /home/usuario/hermes-architect/monitoring/prometheus.yml ]; then ok "prometheus.yml presente"; else bad "prometheus.yml ausente"; fi

# Alertas: regras carregadas, métrica do backup publicada e nada disparado.
# Disparo vira WARN (não FAIL): é estado do ambiente, não regressão do código —
# mesma razão pela qual o estado do próprio CI nunca pode derrubar a suíte.
rules=$(docker exec prometheus wget -qO- 'http://127.0.0.1:9090/api/v1/rules' 2>/dev/null)
if has "$rules" '"name":"lab"'; then ok "alertas do lab carregados (grupo lab)"; else bad "prometheus sem as regras do lab (rule_files)"; fi
# O Prometheus NÃO relê rule_files a cada evaluation_interval (só no start ou em
# SIGHUP — descoberto em 2026-10-20: regra nova ficou invisível até o HUP).
# Sem este check, um deploy de alerta passa verde rodando as regras velhas.
nrules=$(printf '%s' "$rules" | python3 -c '
import sys, json
try:
    print(sum(len(g["rules"]) for g in json.load(sys.stdin)["data"]["groups"]))
except Exception:
    print("err")
' 2>/dev/null)
rulefile=/home/usuario/hermes-architect/monitoring/alert-rules.yml
nfile=$(grep -c -- '- alert:' "$rulefile" 2>/dev/null || echo "?")
if [ "${nrules:-err}" = "${nfile:-?}" ] && has "$rules" 'LabMem0MaintenanceLate'; then
  ok "todas as ${nfile} regras do arquivo carregadas (inclui a do mem0)"
else
  bad "regras carregadas=${nrules:-?} de ${nfile:-?} no arquivo — rode: docker kill -s HUP prometheus"
fi
bkp=$(docker exec prometheus wget -qO- 'http://127.0.0.1:9090/api/v1/query?query=hermes_backup_last_success_timestamp_seconds' 2>/dev/null)
if has "$bkp" '"value"'; then ok "métrica de backup exposta (hermes_backup_*)"; else bad "métrica hermes_backup_* ausente (textfile do backup)"; fi
m0m=$(docker exec prometheus wget -qO- 'http://127.0.0.1:9090/api/v1/query?query=hermes_mem0_points_total' 2>/dev/null)
if has "$m0m" '"value"'; then ok "métrica do mem0 exposta (hermes_mem0_*)"; else bad "métrica hermes_mem0_* ausente (manutenção do mem0)"; fi
nf=$(docker exec prometheus wget -qO- 'http://127.0.0.1:9090/api/v1/query?query=ALERTS%7Balertstate%3D%22firing%22%7D' 2>/dev/null | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["data"]["result"]))' 2>/dev/null)
if [ "${nf:-0}" = "0" ]; then ok "nenhum alerta disparado"; else warn "${nf} alerta(s) disparado(s) — painel Hermes Lab — Alertas"; fi
# O watcher do Windows é a notificação ativa: se o Prometheus não responde, ele TEM
# de avisar. Em 2026-10-22 a monitoração ficou 4 h fora (host desligado e o
# prometheus não voltou) e ninguém soube — o script morria no stderr do ssh antes
# de chegar ao aviso (EAP=Stop + NativeCommandError) e no fim só logava.
watch=/home/usuario/hermes-architect/ops/windows/watch-alerts.ps1
if [ -f "$watch" ] && grep -q 'PrometheusSemResposta' "$watch" && grep -q "ErrorActionPreference = 'Continue'" "$watch"; then
  ok "watch-alerts avisa quando o Prometheus não responde"
else
  bad "watch-alerts sem o aviso de 'Prometheus não responde' (monitoração cega em silêncio)"
fi
# A tarefa do Windows chama wscript + run-hidden.vbs (zero janela) e o toast usa
# AUMID próprio ("Hermes Lab"): powershell.exe direto numa tarefa interativa abria
# um console a cada 30 min e roubava o foco de quem estava digitando (2026-10-22).
hidden=/home/usuario/hermes-architect/ops/windows/run-hidden.vbs
if [ -f "$hidden" ] && grep -q 'sh.Run cmd, 0, False' "$hidden" \
   && grep -q 'Hermes\.Lab\.Alerts' "$watch" && ! grep -q '1AC14E77' "$watch"; then
  ok "watcher sem janela (run-hidden.vbs) e toast com AUMID 'Hermes Lab'"
else
  bad "watcher abriria console / toast voltaria a aparecer como 'Windows PowerShell'"
fi

# ---------------------------------------------------------------------------
section "FASE 7 — CI do oráculo (N2)"
# --- o agendador em si: /etc/cron.d não roda nada se o cron não estiver ativo ---
# (bug real: o pacote `cron` não estava instalado no host — as entradas existiam e
#  nunca rodavam; a suíte só olhava o arquivo, não o daemon)
if systemctl is-active --quiet cron 2>/dev/null; then ok "cron ativo (agendador do backup e do CI)"; else bad "cron INATIVO — backup 03:30 e CI 04:10 não rodam"; fi
if systemctl is-enabled --quiet cron 2>/dev/null; then ok "cron habilitado no boot"; else bad "cron não habilitado no boot"; fi
# --- fuso horário: o cron lê a hora LOCAL do host ---
# Em 2026-10-22 o host estava em Etc/UTC: o backup das 03:30 rodava à meia-noite de
# Brasília e todo log aparecia 3 h adiantado (a queda de energia "01:09" era 22:09).
tz=$(timedatectl show -p Timezone --value 2>/dev/null)
if [ "$tz" = "America/Sao_Paulo" ]; then
  ok "fuso horário do host = America/Sao_Paulo (backup 03:30 é 03:30 local)"
else
  bad "fuso horário do host = ${tz:-?} (esperado America/Sao_Paulo — cron e logs 3 h fora)"
fi
if grep -q 'hermes-backup' /etc/cron.d/hermes-backup 2>/dev/null; then ok "agendamento do backup (03:30)"; else bad "agendamento do backup ausente"; fi
if grep -q 'hermes-ci' /etc/cron.d/hermes-ci 2>/dev/null; then ok "agendamento do CI (04:10)"; else bad "agendamento do CI ausente"; fi
# --- fatos estáticos: se regredirem, é FALHA ---
if [ -x /usr/local/bin/hermes-ci ]; then ok "runner hermes-ci instalado"; else bad "hermes-ci ausente"; fi
if [ -f /etc/cron.d/hermes-ci ]; then ok "cron do CI presente"; else bad "cron do CI ausente"; fi
if grep -q 'collector.textfile.directory' /home/usuario/hermes-architect/docker-compose.yml 2>/dev/null; then ok "node-exporter com textfile collector"; else bad "node-exporter sem textfile collector"; fi
if grep -q 'hermes_ci_last_run_success' /home/usuario/hermes-architect/monitoring/grafana/dashboards/hermes-lab.json 2>/dev/null; then ok "painel do CI no dashboard"; else bad "painel do CI ausente"; fi

# --- estado do CI: AVISO, nunca FALHA ---
# (se fosse FAIL, a suíte ficaria travada em vermelho: todo run verde reportaria
#  o vermelho do run anterior. O CI se observa pelo painel "Oráculo" do Grafana.)
cijson=/home/usuario/ci/last-run.json
if [ -f "$cijson" ] && python3 -c "import json,sys;sys.exit(0 if json.load(open('$cijson')).get('success') else 1)" 2>/dev/null; then
  ok "último CI = VERDE"
else
  warn "último CI = VERMELHO/ausente (veja o painel Oráculo no Grafana)"
fi
if [ -f "$cijson" ]; then
  ci_age=$(( ( $(date +%s) - $(stat -c %Y "$cijson") ) / 3600 ))
  if [ "$ci_age" -le 48 ]; then ok "CI rodou nas últimas ${ci_age}h"; else warn "CI atrasado (${ci_age}h)"; fi
else
  warn "sem ~/ci/last-run.json (o CI nunca rodou?)"
fi
tf=/home/usuario/hermes-architect/ci/textfile/hermes_ci.prom
if grep -q '^hermes_ci_last_run_success 1' "$tf" 2>/dev/null; then ok "métrica do CI publicada (textfile)"; else warn "métrica do CI ausente no textfile"; fi
ciprom=$(docker exec prometheus wget -qO- 'http://127.0.0.1:9090/api/v1/query?query=hermes_ci_last_run_success' 2>/dev/null)
# o Prometheus relê a cada scrape: comparar o VALOR recém-publicado seria raçudo.
# O invariante aqui é a série existir (textfile → node-exporter → Prometheus).
if has "$ciprom" 'hermes_ci_last_run_success'; then ok "Prometheus expõe a métrica do CI"; else warn "Prometheus sem métrica do CI"; fi

# ---------------------------------------------------------------------------
section "REDE / firewall (Fase 6a)"
if command -v ufw >/dev/null 2>&1; then
  u=$(sudo -n ufw status 2>/dev/null | head -1)
  if has "$u" "active"; then ok "ufw ativo"; else bad "ufw não ativo ($u)"; fi
fi
# A política de portas precisa estar versionada: perdida no host, um rebuild não a recupera.
if [ -x /usr/local/bin/ufw-lab.sh ]; then ok "ufw-lab.sh instalado"; else bad "ufw-lab.sh ausente (política de portas não volta num rebuild)"; fi
ufws=$(sudo -n ufw status 2>/dev/null)
for p in 22 80 443 3001 9119; do
  if printf '%s' "$ufws" | grep -qE "^$p/tcp +ALLOW"; then ok "ufw libera :$p"; else bad "ufw NÃO libera :$p"; fi
done
# 8642 é porta PUBLICADA pelo Docker: o ufw não a governa (INPUT ≠ FORWARD).
# O invariante é o contrário do resto — ela NÃO pode aparecer como liberada.
if printf '%s' "$ufws" | grep -qE '^8642/tcp +ALLOW'; then
  bad "ufw ainda 'libera' :8642 (regra inócua e enganosa — a API é do DOCKER-USER)"
else
  ok "ufw não anuncia :8642 (porta é governada pelo DOCKER-USER)"
fi
dusrules=$(sudo -n iptables -S DOCKER-USER 2>/dev/null)
if [ -z "$dusrules" ]; then
  info "não foi possível ler DOCKER-USER (sem sudo -n?)"
else
  # 8642 = Hermes API com chave estática: só o OWUI (rede interna) precisa dela.
  for p in 6333 11434 8642; do
    if has "$dusrules" "$p"; then ok "DOCKER-USER bloqueia :$p para a LAN"; else bad "DOCKER-USER sem bloqueio para :$p"; fi
  done
fi
# O gateway continua vivo para o host (loopback não passa por FORWARD) e para o OWUI.
gh=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:8642/health)
if [ "$gh" = "200" ]; then ok "API :8642 responde no loopback (host)"; else bad "API :8642 não responde no loopback ($gh)"; fi
# As regras só voltam no boot se o script + unit estiverem instalados e ativos.
# (Já dependeram de existir apenas no host, fora do repo — não voltariam num rebuild.)
if [ -x /usr/local/bin/docker-firewall.sh ]; then ok "docker-firewall.sh instalado"; else bad "docker-firewall.sh ausente (regras não voltam no reboot)"; fi
fw_en=$(systemctl is-enabled docker-firewall.service 2>/dev/null)
fw_ac=$(systemctl is-active docker-firewall.service 2>/dev/null)
if [ "$fw_en" = "enabled" ] && [ "$fw_ac" = "active" ]; then ok "docker-firewall.service ativo e habilitado"; else bad "docker-firewall.service ($fw_en/$fw_ac)"; fi

# ---------------------------------------------------------------------------
section "SMB — share de documentos (eixo de estudos)"
# Os documentos (editais, provas, gabaritos) vivem NO HOST e o Windows grava por
# SMB: é a fonte única e entra no backup. O invariante que importa é que a porta
# 445 não fique aberta para o mundo e que o share não aponte para o home inteiro.
if command -v smbd >/dev/null 2>&1; then ok "samba instalado"; else bad "samba ausente (apt-get install -y samba)"; fi
smb_en=$(systemctl is-enabled smbd 2>/dev/null)
smb_ac=$(systemctl is-active smbd 2>/dev/null)
if [ "$smb_en" = "enabled" ] && [ "$smb_ac" = "active" ]; then ok "smbd ativo e habilitado"; else bad "smbd ($smb_en/$smb_ac)"; fi
TP=$(command -v testparm 2>/dev/null)
share_path=$([ -n "$TP" ] && sudo -n "$TP" -s --section-name=documentos --parameter-name=path 2>/dev/null | tr -d ' \t')
if [ "$share_path" = "/home/usuario/documents" ]; then ok "share 'documentos' -> ~/documents"; else bad "share 'documentos' aponta para '$share_path'"; fi
share_user=$([ -n "$TP" ] && sudo -n "$TP" -s --section-name=documentos --parameter-name='valid users' 2>/dev/null)
if has "$share_user" "usuario"; then ok "share restrito a usuário nominal (sem guest)"; else bad "share sem valid users=usuario ($share_user)"; fi
smb_allow=$([ -n "$TP" ] && sudo -n "$TP" -s --parameter-name='hosts allow' 2>/dev/null)
if has "$smb_allow" "192.168.15.0/24" && ! has "$smb_allow" "0.0.0.0/0"; then
  ok "samba só aceita a sub-rede do lab (hosts allow)"
else
  bad "hosts allow ausente/permissivo ($smb_allow)"
fi
# 445 é INPUT de verdade: tem de estar liberada PARA A SUB-REDE, nunca para todos.
if printf '%s' "$ufws" | grep -qE '^445/tcp +ALLOW +192\.168\.15\.0/24'; then ok "ufw libera :445 só da sub-rede"; else bad "ufw não libera :445 da sub-rede"; fi
if printf '%s' "$ufws" | grep -qE '^445/tcp +ALLOW +Anywhere'; then bad "ufw libera :445 para Anywhere (SMB exposto a qualquer origem)"; else ok "ufw não expõe :445 para Anywhere"; fi
if [ -d /home/usuario/documents/concurso ] && [ -w /home/usuario/documents ]; then
  ok "árvore de documentos existe e é gravável"
else
  bad "árvore /home/usuario/documents ausente ou sem escrita"
fi

# ---------------------------------------------------------------------------
section "RAG — worker de ingestão do share (eixo de estudos, Fase 2)"
# O share entra no container como /documents:ro e o worker (tools/rag_ingest.py)
# roda no host: varre, calcula sha256, chama o uploader dentro do container e
# registra em ~/rag-state/manifest.csv. Invariantes: nada de cópia de arquivo,
# o container NÃO escreve no share, e o modo --dry-run é somente leitura.
owui_docs=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/documents"}}{{.Source}}|{{.RW}}{{end}}{{end}}' open-webui 2>/dev/null)
if [ "$owui_docs" = "/home/usuario/documents|false" ]; then
  ok "share montado no OWUI em /documents somente leitura"
else
  bad "mount /documents:ro ausente ou gravável ($owui_docs)"
fi
for f in tools/rag_ingest.py tools/owui_upload.py tools/rag_complemento.py; do
  if [ -f "/home/usuario/hermes-architect/$f" ]; then ok "worker: $f instalado"; else bad "worker: $f ausente no host"; fi
done
miss=""
for f in rag_ingest.py owui_upload.py rag_complemento.py; do
  grep -qF "$f" /home/usuario/hermes-architect/docs/runbooks/scripts/tools.md 2>/dev/null || miss="$miss $f"
done
if [ -z "$miss" ]; then ok "worker documentado em docs/runbooks/scripts/tools.md"; else bad "script sem linha em tools.md:$miss"; fi
# --dry-run é LEITURA: sai 0 e não mexe no manifest (o log também não é escrito).
man=/home/usuario/rag-state/manifest.csv
antes=""
[ -f "$man" ] && antes=$(stat -c %Y%s "$man" 2>/dev/null)
dry_out=$(mktemp /var/tmp/rag-dry.XXXXXX)
if python3 /home/usuario/hermes-architect/tools/rag_ingest.py --dry-run >"$dry_out" 2>&1; then
  ok "rag-ingest --dry-run roda (somente leitura)"
else
  bad "rag-ingest --dry-run falhou: $(tail -2 "$dry_out" 2>/dev/null | tr '\n' ' ')"
fi
rm -f "$dry_out"
depois=""
[ -f "$man" ] && depois=$(stat -c %Y%s "$man" 2>/dev/null)
if [ "$antes" = "$depois" ]; then ok "dry-run não toca no manifest"; else bad "dry-run alterou o manifest"; fi
# O manifest é histórico e a chave do "já ingerido" é o sha256 — mover arquivo de
# pasta NÃO reingere nada (provado em 2026-10-22 ao criar apostilas/<matéria>/).
# Mas o manifest guarda o caminho do upload: se a origem apontar para arquivo que
# não existe mais, o relatório e o `--remover` mentem. O caminho tem de existir.
orfas=$(python3 - "$man" <<'PY' 2>/dev/null
import csv, os, sys
caminho = sys.argv[1]
docs = '/home/usuario/documents'
if not os.path.exists(caminho):
    print('sem-manifest')
    raise SystemExit
linhas = list(csv.DictReader(open(caminho, encoding='utf-8')))
faltando = [r['origem'] for r in linhas if r['estado'] == 'ok'
            and not os.path.exists(os.path.join(docs, r['origem']))]
print(len(faltando))
for f in faltando[:3]:
    print(f, file=sys.stderr)
PY
)
if [ "$orfas" = "0" ]; then
  ok "manifest: todo documento 'ok' aponta para arquivo existente no share"
else
  bad "manifest aponta para arquivo inexistente ($orfas) - confira a coluna origem"
fi
# CRLF no manifest quebra quem casa `,ok$` com grep (a suíte e o relatório). Aconteceu
# em 2026-10-22 ao regravar o CSV com csv.DictWriter: o padrão do Python é \r\n.
if grep -q $'\r' "$man" 2>/dev/null; then
  bad "manifest com CRLF (grave com lineterminator='\\n') - quebra grep ',ok\$'"
else
  ok "manifest em LF (grep ',ok\$' funciona)"
fi
# O Docling às vezes converte TABELA em figura e o texto de dentro dela não entra
# (AGENTS §5, medido na apostila de Matemática). tools/rag_complemento.py grava
# `complemento-<documento>.md` com o texto dessas páginas — se o complemento existe
# no share mas não está NA BASE, a tabela continua invisível para o chat.
semcomp=""
while IFS= read -r arq; do
  [ -n "$arq" ] || continue
  csha=$(sha256sum "$arq" 2>/dev/null | awk '{print $1}')
  [ -n "$csha" ] || continue
  grep -q "^$csha,.*,ok$" "$man" 2>/dev/null || semcomp="$semcomp $(basename "$arq")"
done < <(find /home/usuario/documents -name 'complemento-*.md' -not -path '*/_*' 2>/dev/null | sort)
if [ -z "$semcomp" ]; then
  ok "complementos de tabela: todo .md do share está na base"
else
  bad "complemento de tabela fora da base (rode rag-ingest):$semcomp"
fi
# Canário do caso real: a tabela de ângulos da p.160 da Matemática (que o Docling
# perdeu) tem de estar pesquisável. Se o complemento sumir, o chat volta a não saber.
tabela=$(python3 - "$man" <<'PY' 2>/dev/null
import csv, json, sys, urllib.request
alvo = [r for r in csv.DictReader(open(sys.argv[1], encoding='utf-8'))
        if r['estado'] == 'ok' and 'complemento-apostila-medio-matematica' in r['origem']]
if not alvo:
    print('sem-complemento')
    raise SystemExit
sha = alvo[-1]['sha256']
texto, offset = '', None
while True:
    corpo = {'filter': {'must': [{'key': 'metadata.file_hash', 'match': {'value': sha}}]},
             'limit': 256, 'with_payload': ['text'], 'with_vector': False}
    if offset is not None:
        corpo['offset'] = offset
    req = urllib.request.Request('http://127.0.0.1:6333/collections/owui_knowledge/points/scroll',
                                 data=json.dumps(corpo).encode(),
                                 headers={'Content-Type': 'application/json'})
    res = json.load(urllib.request.urlopen(req, timeout=60))['result']
    texto += ' '.join(p['payload'].get('text') or '' for p in res['points'])
    offset = res.get('next_page_offset')
    if offset is None:
        break
print('ok' if 'Correspondentes' in texto and 'a=e' in texto else 'sem-texto')
PY
)
case "$tabela" in
  ok) ok "tabela da p.160 da Matemática pesquisável na base (complemento)" ;;
  sem-complemento) bad "complemento da Matemática não está no manifest (rode tools/rag_complemento.py)" ;;
  *) bad "texto da tabela da p.160 não está na base (complemento vazio?)" ;;
esac
# heurística do aviso de extração curta: PDF escaneado avisa, .txt curto não
# (o gabarito de 2022 digitado tem 190 chars em 239 bytes — é o arquivo inteiro,
# avisar ali era falso alarme de "OCR falhou").
if python3 -c 'import sys; sys.path.insert(0, "/home/usuario/hermes-architect/tools"); import rag_ingest as r; assert r.aviso_extracao(".txt", 190, 239) == ""; assert r.aviso_extracao(".pdf", 190, 500000) != ""; assert r.aviso_extracao(".pdf", 5000, 500000) == ""' 2>/dev/null; then
  ok "aviso de extração curta: PDF escaneado avisa, .txt curto não"
else
  bad "heurística do aviso de extração curta mudou (falso alarme em .txt curto)"
fi
# Substituição de versão (2026-10-22): mesmo caminho + conteúdo novo = a versão
# antiga SAI da base. Antes ela ficava, e a base acumulava duas cópias do mesmo
# documento — o gabarito de 2022 ficou com a resposta errada citável ao lado da
# corrigida. Sandbox em /var/tmp: nada aqui toca no share nem no OWUI (dry-run).
sb=$(mktemp -d /var/tmp/rag-sub.XXXXXX)
mkdir -p "$sb/docs/concurso/tiradentes-bm/2024/prova_gabarito" "$sb/state"
printf '1A\n2B\n' > "$sb/docs/concurso/tiradentes-bm/2024/prova_gabarito/gabarito-2024.txt"
printf 'sha256,bytes,origem,tipo,ano,knowledge_id,file_id,ingerido_em,duracao_s,estado\n' > "$sb/state/manifest.csv"
printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,6,concurso/tiradentes-bm/2024/prova_gabarito/gabarito-2024.txt,gabarito,2024,kb,file,2026-01-01T00:00:00Z,0.5,ok\n' >> "$sb/state/manifest.csv"
sub_out=$(python3 /home/usuario/hermes-architect/tools/rag_ingest.py --dry-run --documents "$sb/docs" --state "$sb/state" --min-idade 0 2>&1)
if printf '%s' "$sub_out" | grep -q 'substituiria'; then
  ok "conteúdo novo no mesmo caminho substitui a versão antiga"
else
  bad "conteúdo novo no mesmo caminho não substitui (vai duplicar): $(printf '%s' "$sub_out" | tail -1)"
fi
sha_now=$(sha256sum "$sb/docs/concurso/tiradentes-bm/2024/prova_gabarito/gabarito-2024.txt" | awk '{print $1}')
sed -i "s/^aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,/$sha_now,/" "$sb/state/manifest.csv"
rep_out=$(python3 /home/usuario/hermes-architect/tools/rag_ingest.py --dry-run --documents "$sb/docs" --state "$sb/state" --min-idade 0 2>&1)
if printf '%s' "$rep_out" | grep -q 'já ingerido' && ! printf '%s' "$rep_out" | grep -q 'substituiria'; then
  ok "mesmo conteúdo não substitui nada (é o mesmo documento)"
else
  bad "mesmo conteúdo dispararia substituição (compare SHA-256 deveria igualar)"
fi
# a versão antiga (estado `substituido`) também tem de ser removível: antes o
# --remover só aceitava `ok` e recusava justamente a linha que se quer limpar
sed -i "s/^$sha_now,/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,/" "$sb/state/manifest.csv"
sed -i 's/,ok$/,substituido/' "$sb/state/manifest.csv"
rm_out=$(python3 /home/usuario/hermes-architect/tools/rag_ingest.py --remover aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --dry-run --documents "$sb/docs" --state "$sb/state" 2>&1)
if printf '%s' "$rm_out" | grep -q 'removeria'; then
  ok "versão antiga (substituido) pode ser removida com --remover"
else
  bad "não consegui remover uma versão substituida: $(printf '%s' "$rm_out" | tail -1)"
fi
rm -rf "$sb"
if [ -f "$man" ]; then
  head1=$(head -1 "$man" 2>/dev/null | tr -d '\r')
  if [ "$head1" = "sha256,bytes,origem,tipo,ano,knowledge_id,file_id,ingerido_em,duracao_s,estado" ]; then
    ok "manifest com as 10 colunas do desenho"
  else
    bad "manifest com cabeçalho inesperado ($head1)"
  fi
  nok=$(tr -d '\r' < "$man" 2>/dev/null | awk -F, 'NR>1 && $NF=="ok"' | wc -l)
  if [ "${nok:-0}" -ge 1 ]; then ok "manifest registra $nok documento(s) ingerido(s)"; else warn "manifest sem documento ok (worker nunca ingeriu)"; fi
else
  warn "manifest.csv ainda não existe (rag-ingest nunca rodou)"
fi

# ---------------------------------------------------------------------------
section "RAG — worker agendado (eixo de estudos, Fase 3)"
# Fase 3 = o mesmo worker, agora no cron a cada 15 min. O invariante que importa:
# roda como usuario (como root, _rejeitados/ e _relatorio/ nasceriam de root
# dentro do share) e o agendamento existe DE VERDADE (arquivo + efeito recente).
if [ -x /usr/local/bin/rag-ingest ]; then ok "rag-ingest instalado em /usr/local/bin"; else bad "rag-ingest ausente (rode o sync)"; fi
if [ -f /etc/cron.d/rag-ingest ]; then ok "entrada /etc/cron.d/rag-ingest instalada"; else bad "cron do worker ausente"; fi
if grep -qE '^\*/15 \* \* \* \* usuario /usr/local/bin/rag-ingest' /etc/cron.d/rag-ingest 2>/dev/null; then
  ok "worker agendado a cada 15 min como usuario"
else
  bad "linha do cron ausente/errada em /etc/cron.d/rag-ingest (usuário errado = arquivos de root no share)"
fi
if has "$(grep -E '^HOME=' /etc/cron.d/rag-ingest 2>/dev/null)" "HOME=/home/usuario"; then
  ok "cron com HOME do dono do share"
else
  warn "cron sem HOME=/home/usuario (o docker pode reclamar)"
fi
# Prova pelo EFEITO, não pelo arquivo: o relatório é reescrito a cada execução
# real. Mais de 45 min = cron parado ou host desligado (estado do ambiente → WARN).
rel=/home/usuario/documents/_relatorio/INGESTAO.md
if [ -f "$rel" ]; then
  idade=$(( ( $(date +%s) - $(stat -c %Y "$rel") ) / 60 ))
  if [ "$idade" -le 45 ]; then
    ok "worker rodou há ${idade} min (cron ativo)"
  else
    warn "última ingestão há ${idade} min (>45) — cron parado ou host desligado"
  fi
else
  warn "sem _relatorio/INGESTAO.md (worker nunca rodou de verdade)"
fi
# O relatório/log é lido pelo dono no Explorer: horário LOCAL com offset. Um "Z"
# aqui volta a mostrar 3 h a mais (foi o que causou a confusão de 2026-10-22).
if grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}' "$rel" 2>/dev/null; then
  ok "relatório do worker em horário local com offset (ex.: -03:00)"
else
  warn "relatório sem horário local com offset (leitura confusa no Explorer)"
fi

# ---------------------------------------------------------------------------
section "RAG — operação e métricas (eixo de estudos, Fase 4)"
# Fase 4: o próprio worker publica o estado no textfile do node-exporter
# (hermes_rag_*). Sem métrica, "documento pendente" só apareceria quando alguém
# abrisse o Explorer; o alerta de 24 h é o que fecha o ciclo.
ragtf=/home/usuario/hermes-architect/ci/textfile/hermes_rag.prom
miss=""
for m in hermes_rag_documentos_total hermes_rag_falhas_total hermes_rag_pendentes_total \
         hermes_rag_pendente_mais_antigo_segundos hermes_rag_ultima_execucao_timestamp_seconds \
         hermes_rag_ultima_execucao_sucesso; do
  grep -q "^$m " "$ragtf" 2>/dev/null || miss="$miss $m"
done
if [ -z "$miss" ]; then
  ok "métricas do RAG publicadas (hermes_rag.prom, textfile)"
else
  bad "métricas do RAG ausentes em $ragtf:$miss"
fi
if [ -f "$ragtf" ]; then
  rage=$(( ( $(date +%s) - $(stat -c %Y "$ragtf") ) / 60 ))
  if [ "$rage" -le 45 ]; then
    ok "métricas do RAG atualizadas há ${rage} min"
  else
    warn "métricas do RAG com ${rage} min (>45) — worker parado ou host desligado"
  fi
  # falha de ingestão é estado do ambiente (um arquivo ruim), não regressão do código
  if grep -q '^hermes_rag_ultima_execucao_sucesso 1' "$ragtf" 2>/dev/null; then
    ok "última ingestão sem falhas"
  else
    warn "última ingestão com falha (veja _rejeitados/ e _relatorio/INGESTAO.md)"
  fi
fi
ragprom=$(docker exec prometheus wget -qO- 'http://127.0.0.1:9090/api/v1/query?query=hermes_rag_documentos_total' 2>/dev/null)
if has "$ragprom" 'hermes_rag_documentos_total'; then
  ok "Prometheus expõe hermes_rag_* (textfile → node-exporter)"
else
  bad "Prometheus sem hermes_rag_* (node-exporter não lê o textfile?)"
fi
# As regras do eixo de estudos precisam estar CARREGADAS (o HUP é obrigatório
# para o Prometheus reler alert-rules.yml — ver seção de monitoramento).
miss=""
for r in LabRagPendente24h LabRagParado LabRagFalhou LabRagMetricMissing; do
  has "$rules" "\"$r\"" || miss="$miss $r"
done
if [ -z "$miss" ]; then
  ok "alertas do eixo de estudos carregados (LabRag*)"
else
  bad "regra(s) do RAG ausente(s) no Prometheus:$miss — rode: docker kill -s HUP prometheus"
fi

# ---------------------------------------------------------------------------
section "RAG — banco de questões (eixo de estudos, Fase 5)"
# O RAG responde "o que diz o edital"; contagem/por número de questão é do banco
# (docs/plans/BANCO-DE-QUESTOES.md). Invariantes: todo ano com prova E gabarito
# fecha 50/50 (o importador NÃO inventa), o gabarito em imagem é lido por OCR,
# e o .md de estatísticas publicado é o que o worker ingere (vira citação).
if [ -x /usr/local/bin/questoes ]; then ok "questoes instalado em /usr/local/bin"; else bad "questoes ausente (rode o sync)"; fi
if [ -f /etc/cron.d/questoes ]; then ok "entrada /etc/cron.d/questoes instalada"; else bad "cron do banco de questões ausente"; fi
if grep -qE '^5,35 \* \* \* \* usuario /usr/local/bin/questoes' /etc/cron.d/questoes 2>/dev/null; then
  ok "banco de questões agendado a cada 30 min como usuario"
else
  bad "linha do cron ausente/errada em /etc/cron.d/questoes (usuário errado = arquivo de root no share)"
fi
if command -v tesseract >/dev/null 2>&1 && tesseract --list-langs 2>/dev/null | grep -qx 'por'; then
  ok "OCR disponível no host (tesseract + português)"
else
  bad "tesseract/idioma por ausente — gabaritos em imagem (2023/2025) não são lidos"
fi
qdb=/home/usuario/rag-state/questoes.db
if [ -f "$qdb" ]; then
  ok "banco de questões existe (~/rag-state/questoes.db, entra no backup)"
else
  bad "questoes.db ausente — rode: /usr/local/bin/questoes importar"
fi
# Prova pelo CONTEÚDO: todo ano com prova e gabarito tem 50 questões 1..50.
qres=$(python3 - "$qdb" <<'PY' 2>/dev/null
import sqlite3, sys
try:
    c = sqlite3.connect(sys.argv[1]); c.row_factory = sqlite3.Row
except Exception as exc:
    print('erro', exc); raise SystemExit(0)
ruins, anos = [], 0
for r in c.execute("select * from ano_status order by ano"):
    q = c.execute('select count(*) from questao where ano=?', (r['ano'],)).fetchone()[0]
    g = c.execute('select count(*) from gabarito where ano=?', (r['ano'],)).fetchone()[0]
    if r['status'] in ('ok', 'sem_prova', 'sem_gabarito'):
        anos += 1
    if r['status'] == 'ok' and (q != 50 or g != 50):
        ruins.append(f"{r['ano']}:{q}/{g}")
    if r['status'] == 'revisar':
        ruins.append(f"{r['ano']}:revisar")
print('ok' if not ruins else 'ruins ' + ','.join(ruins))
print('anos', anos)
PY
)
case "$qres" in
  ok*)
    ok "todo ano com prova e gabarito fecha 50 questões + 50 respostas"
    ;;
  *)
    bad "ano(s) incompleto(s) no banco de questões: $(printf '%s' "$qres" | tr '\n' ' ')"
    ;;
esac
# Os dois gabaritos que são IMAGEM no PDF: se o OCR parar de funcionar, o ano
# fica `revisar` — este check diz qual caminho foi usado.
if python3 - "$qdb" >/dev/null 2>&1 <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
fontes = dict(c.execute("select ano, min(fonte) from gabarito group by ano").fetchall())
assert fontes.get('2023') == 'ocr-grade', fontes
assert fontes.get('2025') == 'ocr-tabela', fontes
PY
then
  ok "gabaritos em imagem (2023 grade, 2025 tabela) lidos por OCR"
else
  bad "OCR dos gabaritos em imagem mudou (2023 deveria ser ocr-grade, 2025 ocr-tabela)"
fi
qout=$(mktemp /var/tmp/quest-conf.XXXXXX)
if python3 /home/usuario/hermes-architect/tools/questoes.py --db "$qdb" conferir >"$qout" 2>&1; then
  ok "questoes conferir: 50/50 em todos os anos com prova e gabarito"
else
  bad "questoes conferir falhou: $(tail -2 "$qout" 2>/dev/null | tr '\n' ' ')"
fi
rm -f "$qout"
# Relatório lido no Explorer: fresco = cron rodando (estado do ambiente → WARN).
qrel=/home/usuario/documents/_relatorio/QUESTOES.md
if [ -f "$qrel" ]; then
  qidade=$(( ( $(date +%s) - $(stat -c %Y "$qrel") ) / 60 ))
  if [ "$qidade" -le 45 ]; then
    ok "banco de questões rodou há ${qidade} min (cron ativo)"
  else
    warn "banco de questões parado há ${qidade} min (>45) — cron ou host desligado"
  fi
else
  warn "sem _relatorio/QUESTOES.md (questoes nunca rodou de verdade)"
fi
# O documento gerado precisa estar NA BASE (é o que deixa o chat responder
# "quantas de matemática caíram em 2025" com citação).
qest=/home/usuario/documents/referencias/estatisticas-questoes.md
if [ -f "$qest" ]; then
  qsha=$(sha256sum "$qest" | awk '{print $1}')
  qman=/home/usuario/rag-state/manifest.csv
  if grep -q "^$qsha,.*referencias/estatisticas-questoes.md,.*,ok$" "$qman" 2>/dev/null; then
    ok "estatísticas das questões publicadas e ingeridas (citáveis no chat)"
  elif grep -qF 'referencias/estatisticas-questoes.md' "$qman" 2>/dev/null; then
    warn "estatísticas publicadas mas a versão atual não está na base (worker ainda não rodou)"
  else
    warn "estatísticas publicadas mas nunca ingeridas (confira o worker)"
  fi
else
  bad "referencias/estatisticas-questoes.md ausente (rode: questoes estatisticas --publicar)"
fi
miss=""
grep -qF 'questoes.py' /home/usuario/hermes-architect/docs/runbooks/scripts/tools.md 2>/dev/null || miss="$miss tools.md"
[ -f /home/usuario/hermes-architect/docs/runbooks/scripts/questoes.md ] || miss="$miss card"
if [ -z "$miss" ]; then ok "banco de questões documentado (tools.md + card do script)"; else bad "documentação do banco de questões faltando:$miss"; fi
# Regressão em sandbox (nada toca no share): 50/50 passa; incompleto é `revisar`
# e falha. É o "não inventa" — o importador nunca completa questão faltando.
qsb=$(mktemp -d /var/tmp/quest-sb.XXXXXX)
mkdir -p "$qsb/ok/concurso/tiradentes-bm/2030/prova_gabarito" \
         "$qsb/ruim/concurso/tiradentes-bm/2031/prova_gabarito"
for n in $(seq 1 50); do
  printf 'Questão %s. Enunciado da questão %s.\n   (A) alternativa A\n   (B) alternativa B\n   (C) alternativa C\n   (D) alternativa D\n   (E) alternativa E\n\n' "$n" "$n"
done > "$qsb/ok/concurso/tiradentes-bm/2030/prova_gabarito/prova-2030.txt"
for n in $(seq 1 50); do printf '%s A\n' "$n"; done > "$qsb/ok/concurso/tiradentes-bm/2030/prova_gabarito/gabarito-2030.txt"
for n in 1 2 3; do
  printf 'Questão %s. Enunciado da questão %s.\n   (A) a\n   (B) b\n   (C) c\n   (D) d\n   (E) e\n\n' "$n" "$n"
done > "$qsb/ruim/concurso/tiradentes-bm/2031/prova_gabarito/prova-2031.txt"
for n in 1 2 3; do printf '%s A\n' "$n"; done > "$qsb/ruim/concurso/tiradentes-bm/2031/prova_gabarito/gabarito-2031.txt"
if python3 /home/usuario/hermes-architect/tools/questoes.py --db "$qsb/ok.db" --documents "$qsb/ok" importar --quiet >/dev/null 2>&1 \
   && python3 /home/usuario/hermes-architect/tools/questoes.py --db "$qsb/ok.db" conferir >/dev/null 2>&1; then
  ok "sandbox: prova+gabarito completos importam 50/50 e conferem"
else
  bad "sandbox: import de 50/50 não passou (parser quebrado)"
fi
if python3 /home/usuario/hermes-architect/tools/questoes.py --db "$qsb/ruim.db" --documents "$qsb/ruim" importar --quiet >/dev/null 2>&1 \
   && ! python3 /home/usuario/hermes-architect/tools/questoes.py --db "$qsb/ruim.db" conferir >/dev/null 2>&1; then
  ok "sandbox: ano incompleto fica revisar e conferir falha (não inventa)"
else
  bad "sandbox: ano incompleto passou como ok (importador inventando questão)"
fi
rm -rf "$qsb"

# ---------------------------------------------------------------------------
section "TUTOR TIRADENTES — modelo pedagógico determinístico"
tutor_mount=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/data/questoes.db"}}{{.Source}}|{{.RW}}{{end}}{{end}}' open-webui 2>/dev/null)
if [ "$tutor_mount" = "/home/usuario/rag-state/questoes.db|false" ]; then
  ok "Tutor: questoes.db montado no Open WebUI somente leitura"
else
  bad "Tutor: mount esperado /home/usuario/rag-state/questoes.db -> /data/questoes.db:ro (atual: $tutor_mount)"
fi

tutor_state=$(docker exec -i open-webui python - <<'PY' 2>/dev/null
import hashlib, json, sqlite3
c = sqlite3.connect('/app/backend/data/webui.db')
f = c.execute("select name,content,is_active,is_global from function where id='tutor_tiradentes'").fetchone()
m = c.execute("select name,meta,is_active from model where id='tutor_tiradentes'").fetchone()
mg = c.execute("select count(*) from access_grant where resource_type='model' and resource_id='tutor_tiradentes' and principal_type='user' and principal_id='*' and permission='read'").fetchone()[0]
kg = c.execute("select count(*) from access_grant where resource_type='knowledge' and resource_id='60d58cd2-29b9-424d-a483-c9d5cc68f77c' and principal_type='user' and principal_id='*' and permission='read'").fetchone()[0]
print('FUNCTION=' + ('ok' if f and f[0] == 'Tutor Tiradentes — 9º ano' and f[2] == 1 and f[3] == 0 else 'bad'))
print('MODEL=' + ('ok' if m and m[0] == 'Tutor Tiradentes — 9º ano' and m[2] == 1 else 'bad'))
meta = json.loads(m[1]) if m else {}
knowledge = meta.get('knowledge') or []
print('KNOWLEDGE=' + ('ok' if any(k.get('id') == '60d58cd2-29b9-424d-a483-c9d5cc68f77c' for k in knowledge) else 'bad'))
print(f'GRANTS={mg}/{kg}')
print('SOURCE_SHA=' + (hashlib.sha256(f[1].encode()).hexdigest() if f else 'missing'))
try:
    ro = sqlite3.connect('file:/data/questoes.db?mode=ro', uri=True)
    ro.execute('PRAGMA query_only=ON')
    ro.execute('SELECT count(*) FROM questao').fetchone()
except sqlite3.Error:
    print('READONLY=bad')
else:
    try:
        ro.execute('CREATE TABLE _tutor_write_must_fail (x)')
        print('READONLY=bad')
    except sqlite3.OperationalError:
        print('READONLY=ok')
PY
)
if has "$tutor_state" "FUNCTION=ok"; then ok "Tutor: Pipe ativo e não global com nome amigável"; else bad "Tutor: Function ausente ou incorreta"; fi
if has "$tutor_state" "MODEL=ok"; then ok "Tutor: modelo ativo com nome amigável"; else bad "Tutor: modelo ausente/inativo"; fi
if has "$tutor_state" "KNOWLEDGE=ok"; then ok "Tutor: base Tiradentes BM anexada como apoio"; else bad "Tutor: base Tiradentes BM não anexada"; fi
if has "$tutor_state" "GRANTS=1/1"; then ok "Tutor: modelo e base legíveis por usuário comum"; else bad "Tutor: ACL pública de leitura incompleta"; fi
if has "$tutor_state" "READONLY=ok"; then ok "Tutor: SQLite recusa escrita dentro do container"; else bad "Tutor: SQLite não está efetivamente somente leitura"; fi

tutor_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)
[ -f "$tutor_root/test_tutor_pipe.py" ] || tutor_root=/home/usuario/hermes-architect/tests
tutor_source=/home/usuario/hermes-architect/ops/open-webui/tutor_tiradentes.py
if [ -f "$tutor_source" ]; then
  expected_sha=$(sha256sum "$tutor_source" | awk '{print $1}')
  if has "$tutor_state" "SOURCE_SHA=$expected_sha"; then ok "Tutor: Function sem deriva em relação ao repo"; else bad "Tutor: código da Function diverge do repo (rode o sync)"; fi
else
  bad "Tutor: fonte versionada ausente"
fi
if python3 "$tutor_root/test_tutor_pipe.py" >/dev/null 2>&1; then
  ok "Tutor: regressões locais (parser, fail-closed, RAG e read-only)"
else
  bad "Tutor: testes locais falharam"
fi
if docker exec -i open-webui python - < "$tutor_root/smoke_tutor.py" >/dev/null 2>&1; then
  ok "Tutor: usuário comum vê o modelo e questão inexistente falha fechado"
else
  bad "Tutor: smoke como usuário comum falhou"
fi

# Regressão do guia visual: a captura real chegou a ser salva com caracteres
# substituídos por '?' ("orienta??es", "tr?s", "9? ano"). O XML continuava
# válido e o erro passava silencioso; confira o texto UTF-8 que a aluna enxerga.
tutor_svg=/home/usuario/hermes-architect/docs/assets/tutor-tiradentes-tela.svg
if [ -f "$tutor_svg" ] \
   && grep -qF 'Tela real do Tutor Tiradentes com orientações' "$tutor_svg" \
   && grep -qF 'com três setas' "$tutor_svg" \
   && grep -qF 'Tutor Tiradentes — 9º ano' "$tutor_svg"; then
  ok "Tutor: guia visual preserva acentos em UTF-8"
else
  bad "Tutor: guia visual ausente ou com acentos corrompidos"
fi

# O primeiro PDF foi gerado com o título interno "Tutor Tiradentes ? guia para
# alunas", embora o texto das páginas estivesse correto. Esse metadado aparece
# nas propriedades do arquivo e em indexadores, então também faz parte do guia.
tutor_pdf=/home/usuario/hermes-architect/docs/learning/TUTOR-TIRADENTES-GUIA-ALUNAS.pdf
tutor_pdf_title=$(pdfinfo "$tutor_pdf" 2>/dev/null | sed -n 's/^Title:[[:space:]]*//p')
if [ "$tutor_pdf_title" = 'Tutor Tiradentes — guia para alunas' ]; then
  ok "Tutor: PDF publicado com título interno correto"
else
  bad "Tutor: PDF ausente, ilegível ou com título interno corrompido"
fi

# ---------------------------------------------------------------------------
section "FASE 6.4 — Backup e pinagem"
if [ -x /usr/local/bin/hermes-backup ]; then ok "script hermes-backup instalado"; else bad "hermes-backup ausente"; fi
if [ -f /etc/cron.d/hermes-backup ]; then ok "cron de backup diário"; else bad "cron de backup ausente"; fi
latest=$(ls -1t /home/usuario/backups/hermes-*.tar.gz 2>/dev/null | head -1)
if [ -n "$latest" ]; then
  age=$(( ( $(date +%s) - $(stat -c %Y "$latest") ) / 3600 ))
  if [ "$age" -le 48 ]; then ok "backup recente (${age}h)"; else bad "backup antigo (${age}h)"; fi
  if tar -tzf "$latest" >/dev/null 2>&1; then ok "backup íntegro (tar ok)"; else bad "backup corrompido"; fi
  if tar -tzf "$latest" 2>/dev/null | grep -q 'webui.db'; then ok "backup inclui webui.db"; else bad "backup sem webui.db"; fi
  if tar -tzf "$latest" 2>/dev/null | grep -q 'qdrant-mem0_memories'; then ok "backup inclui mem0_memories"; else bad "backup sem mem0_memories"; fi
  if tar -tzf "$latest" 2>/dev/null | grep -q 'project-config.tgz'; then ok "backup inclui configs do projeto"; else bad "backup sem configs do projeto"; fi
  # Documentos do eixo de estudos (share SMB): é a SEGUNDA cópia. Se faltar aqui,
  # um disco perdido levaria editais/provas junto.
  if tar -tzf "$latest" 2>/dev/null | grep -q 'documents.tgz'; then ok "backup inclui documentos (share SMB)"; else bad "backup sem documents.tgz (editais/provas fora do backup)"; fi
  if tar -tzf "$latest" 2>/dev/null | grep -qE '(^|/)grafana\.db$'; then
    ok "backup inclui grafana.db"
  else
    bad "backup sem grafana.db (usuários/prefs do Grafana não voltam)"
  fi

  # Restaurar de verdade: "tar abre" não prova nada. Extrai num diretório isolado
  # e valida que o conteúdo vira estado utilizável (DB consultável, compose
  # parseável, config do Hermes íntegra, snapshots legíveis). Nada é sobrescrito.
  rt=$(mktemp -d /var/tmp/vs-restore.XXXXXX 2>/dev/null) || rt=""
  if [ -n "$rt" ] && tar -xzf "$latest" -C "$rt" 2>/dev/null; then
    if python3 - "$rt/webui.db" >/dev/null 2>&1 <<'PY'
import sqlite3, sys
c = sqlite3.connect(f'file:{sys.argv[1]}?mode=ro', uri=True)
assert c.execute('pragma integrity_check').fetchone()[0] == 'ok'
assert c.execute('select count(*) from user').fetchone()[0] >= 1
assert 'hermes-agent' in [r[0] for r in c.execute('select id from model')]
assert any('hermes:8642' in str(r) for r in c.execute('select * from config'))
PY
    then ok "backup restaura: webui.db íntegro (usuários, modelo, conexão Hermes)"
    else bad "backup restaura: webui.db inutilizável"
    fi

    if [ -f "$rt/grafana.db" ] && python3 - "$rt/grafana.db" >/dev/null 2>&1 <<'PY'
import sqlite3, sys
c = sqlite3.connect(f'file:{sys.argv[1]}?mode=ro', uri=True)
assert c.execute('pragma integrity_check').fetchone()[0] == 'ok'
assert c.execute("select count(*) from sqlite_master where name='user'").fetchone()[0] == 1
PY
    then ok "backup restaura: grafana.db íntegro (usuários/prefs)"
    else bad "backup restaura: grafana.db ausente ou inutilizável"
    fi

    if [ -f "$rt/documents.tgz" ] && tar -tzf "$rt/documents.tgz" >/dev/null 2>&1; then
      ok "backup restaura: documents.tgz íntegro"
    else
      bad "backup restaura: documents.tgz ausente/corrompido"
    fi

    mkdir -p "$rt/cfg" "$rt/hermes"
    if tar -xzf "$rt/project-config.tgz" -C "$rt/cfg" 2>/dev/null \
       && python3 - "$rt/cfg/docker-compose.yml" >/dev/null 2>&1 <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))
svcs = d.get('services') or {}
assert len(svcs) >= 10, f'apenas {len(svcs)} serviços'
bad = [str(s.get('image')) for s in svcs.values()
       if any(x in str(s.get('image', '')) for x in (':latest', ':main', ':rocm'))]
assert not bad, bad
PY
    then ok "backup restaura: compose parseável e imagens pinadas"
    else bad "backup restaura: compose inválido ou com tag flutuante"
    fi

    if tar -xzf "$rt/hermes-data.tgz" -C "$rt/hermes" 2>/dev/null \
       && python3 - "$rt/hermes/.hermes/config.yaml" >/dev/null 2>&1 <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))
assert d.get('memory', {}).get('provider') == 'mem0'
assert d.get('model', {}).get('default')
PY
    then ok "backup restaura: .hermes/config.yaml válido (mem0)"
    else bad "backup restaura: .hermes/config.yaml inválido"
    fi

    badsnap=0
    for s in "$rt"/qdrant-*.snapshot; do
      [ -e "$s" ] || continue
      tar -tf "$s" >/dev/null 2>&1 || badsnap=$((badsnap + 1))
    done
    if [ "$badsnap" -eq 0 ]; then ok "backup restaura: snapshots Qdrant legíveis"; else bad "backup restaura: $badsnap snapshot(s) corrompido(s)"; fi
    rm -rf "$rt"
  else
    bad "backup não extrai"
    [ -n "$rt" ] && rm -rf "$rt"
  fi
else
  bad "nenhum backup encontrado"
fi
if grep -Eq 'image:.*:(main|rocm|latest)([[:space:]]|$)' /home/usuario/hermes-architect/docker-compose.yml; then
  bad "compose com tag flutuante (:main/:rocm/:latest)"
else
  ok "imagens pinadas (sem :main/:rocm/:latest)"
fi

# ---------------------------------------------------------------------------
section "RAG — E2E sob demanda (SMOKE_RAG=1)"
if [ "${SMOKE_RAG:-0}" = "1" ]; then
  sut=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)
  [ -f "$sut/smoke_rag.py" ] || sut=/home/usuario/hermes-architect/tests
  # mktemp: com fs.protected_regular, o root não sobrescreve um log antigo em /tmp
  # de outro dono (era o que fazia o smoke "falhar" lendo o arquivo velho).
  smoke_out=$(mktemp /tmp/smoke-rag.XXXXXX)
  docker cp "$sut/fixtures/contrato-teste.pdf" open-webui:/tmp/contrato-teste.pdf >/dev/null 2>&1
  docker cp "$sut/smoke_rag.py" open-webui:/tmp/smoke_rag.py >/dev/null 2>&1
  if docker exec open-webui python /tmp/smoke_rag.py >"$smoke_out" 2>&1; then
    ok "RAG E2E: upload -> docling -> bge-m3 -> Qdrant -> resposta com citação [1]"
    rm -f "$smoke_out"
  else
    bad "RAG E2E falhou — ver $smoke_out: $(tail -2 "$smoke_out" 2>/dev/null | tr '\n' ' ')"
  fi
else
  info "não executado (rote com: SMOKE_RAG=1 bash tests/verify_stack.sh)"
fi

# ---------------------------------------------------------------------------
section "SEGREDOS — credencial não mora no repo"
DOCDIR=/home/usuario/hermes-architect
# Varre só o que o sync ENTREGA (árvore versionada). `archive/` fica de fora: é
# quarentena local (ebook, PDF, export de sessão) e não viaja para o host.
SCAN=$(cd "$DOCDIR" 2>/dev/null && ls -d tests ops tools monitoring nginx searxng hermes-data docs 2>/dev/null; cd "$DOCDIR" 2>/dev/null && ls *.md docker-compose.yml .env.example 2>/dev/null)
if [ -n "$KEY" ] && grep -rqI -e "$KEY" $SCAN 2>/dev/null; then
  bad "API_SERVER_KEY aparece em arquivo versionado do repo (deve ficar no .env)"
else
  ok "API_SERVER_KEY fora do repo (só no .env/ambiente)"
fi
if grep -rqI -E 'aim_[A-Za-z0-9_-]{30,}' $SCAN 2>/dev/null; then
  bad "token aim_ (ai-memory) dentro do repo"
else
  ok "nenhum token aim_ no repo"
fi
if grep -rqI -E 'BEGIN (OPENSSH|RSA|EC|PRIVATE) PRIVATE KEY' $SCAN 2>/dev/null; then
  bad "chave privada dentro do repo"
else
  ok "nenhuma chave privada no repo"
fi

# --- Espelho publico (repo projeto-davy-jones-hermes-public) ------------------
# O gerador roda no Windows, sob demanda. Ele NAO pode "simplificar" para um clone
# do privado: o 1o commit do privado (15feb19) trazia a senha e o secret do
# dashboard 9119 escritos no compose, e sao as credenciais em uso hoje. Por isso o
# espelho nasce de um snapshot (git archive do HEAD) e cada publicacao e um commit
# novo, ja com a tabela de redacao aplicada e a varredura de segredo aprovada.
PUB="$DOCDIR/ops/deploy/make-public-repo.ps1"
PUB_CARD="$DOCDIR/docs/runbooks/scripts/make-public-repo.md"
if [ -f "$PUB" ] && [ -f "$PUB_CARD" ]; then
  ok "gerador do espelho publico + card documentados"
else
  bad "gerador do espelho publico (ops/deploy/make-public-repo.ps1) ou card faltando"
fi
miss=""
for par in 'admin@example.com' 'teste@example.com' 'C:\Users\usuario' "De = 'usuario'" "Para = 'usuario'"; do
  grep -qF -- "$par" "$PUB" 2>/dev/null || miss="$miss [$par]"
done
if [ -z "$miss" ]; then
  ok "espelho publico: tabela de redacao completa (e-mails, caminho Windows e usuário Linux)"
else
  bad "espelho publico: tabela de redacao incompleta:$miss"
fi
if grep -qF 'git archive' "$PUB" 2>/dev/null && ! grep -qF 'git clone' "$PUB" 2>/dev/null; then
  ok "espelho publico nasce de snapshot (git archive), sem herdar a historia do privado"
else
  bad "espelho publico deixou de ser snapshot - a historia do privado tem a senha atual do dashboard"
fi
if grep -qF 'COMPOSE_FILE' "$PUB" 2>/dev/null && grep -qF 'varredura achou' "$PUB" 2>/dev/null; then
  ok "espelho publico: varredura dos valores do .env com aborto antes do commit"
else
  bad "espelho publico: varredura de segredo antes do commit nao esta no script"
fi

# ---------------------------------------------------------------------------
section "DOCUMENTAÇÃO — caminhos citados existem"
# Link morto em doc é bug silencioso: alguém renomeia um script e o runbook passa a
# mandar rodar o que não existe. Aqui todo `tools/…`, `ops/…`, `tests/…`,
# `monitoring/…`, `nginx/…` e `docs/…` citado num .md tem de existir no repo
# sincronizado. A varredura cobre a raiz (README, AGENTS) e docs/ recursivamente.
DOCDIR=/home/usuario/hermes-architect
dead=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  # URL não é caminho local: `https://…/docs/install.md` não pode virar link morto.
  txt=$(sed -E 's#https?://[^ )]*##g' "$f" 2>/dev/null)
  for p in $(printf '%s\n' "$txt" | grep -oE '(tools|ops|tests|monitoring|nginx|docs)/[A-Za-z0-9_./-]*\.[A-Za-z0-9]+' | sort -u); do
    [ -e "$DOCDIR/$p" ] || dead="$dead $(basename "$f"):$p"
  done
done < <(find "$DOCDIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null; find "$DOCDIR/docs" -type f -name '*.md' 2>/dev/null)
if [ -z "$dead" ]; then
  ok "docs: todos os caminhos citados existem"
else
  bad "docs com caminho inexistente:$dead"
fi

# ---------------------------------------------------------------------------
section "FASE 3 — documentação operacional (card por serviço, por script, índice)"
# Documentação que não acompanha o código apodrece: some um container, renomeia um
# script e o runbook continua mandando rodar o que não existe. Aqui a exigência é
# 1:1 — todo container em execução tem card, todo script agendado tem card, todo
# `.md` de docs/ aparece no índice e nenhum arquivo da árvore vira binário gigante.

# 1) um card por container EM EXECUÇÃO (nome do arquivo = nome do container)
no_card=""
for c in $(docker ps --format '{{.Names}}' 2>/dev/null); do
  [ -f "$DOCDIR/docs/runbooks/servicos/$c.md" ] || no_card="$no_card $c"
done
if [ -z "$no_card" ]; then
  ok "todo container em execução tem card em docs/runbooks/servicos/"
else
  bad "container sem card de serviço:$no_card"
fi

# 2) um card por script de ops/ (o que roda sozinho: cron, systemd, Task Scheduler)
no_doc=""
for f in "$DOCDIR"/ops/bin/*.sh "$DOCDIR"/ops/bin/*.py "$DOCDIR"/ops/windows/*.ps1; do
  [ -f "$f" ] || continue
  b=$(basename "$f"); b=${b%.*}
  [ -f "$DOCDIR/docs/runbooks/scripts/$b.md" ] || no_doc="$no_doc $b"
done
if [ -z "$no_doc" ]; then
  ok "todo script de ops/ tem card em docs/runbooks/scripts/"
else
  bad "script de ops/ sem documentação:$no_doc"
fi

# 3) índice completo: todo .md de docs/ é citado em docs/README.md
not_indexed=""
while IFS= read -r f; do
  rel=${f#"$DOCDIR/docs/"}
  [ "$rel" = "README.md" ] && continue
  grep -qF "$rel" "$DOCDIR/docs/README.md" 2>/dev/null || not_indexed="$not_indexed $rel"
done < <(find "$DOCDIR/docs" -type f -name '*.md' 2>/dev/null)
if [ -z "$not_indexed" ]; then
  ok "docs/README.md indexa todos os documentos de docs/"
else
  bad "documento fora do índice:$not_indexed"
fi

# 4) todo .md começa com título H1 (arquivo sem título é rascunho, não doc)
no_title=""
while IFS= read -r f; do
  head -1 "$f" 2>/dev/null | grep -q '^# ' || no_title="$no_title $(basename "$f")"
done < <(find "$DOCDIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null; find "$DOCDIR/docs" -type f -name '*.md' 2>/dev/null)
if [ -z "$no_title" ]; then
  ok "todo .md da árvore começa com título H1"
else
  bad ".md sem título H1:$no_title"
fi

# 5) a árvore sincronizada não guarda binário grande (ebook/PDF/export voltando)
big=$(find "$DOCDIR" \( -path "$DOCDIR/archive" -o -path "$DOCDIR/_legacy" -o -path "$DOCDIR/ci/logs" \) -prune \
  -o -type f -size +1024k -print 2>/dev/null | head -5)
if [ -z "$big" ]; then
  ok "nenhum arquivo >1 MB na árvore sincronizada"
else
  bad "arquivo grande na árvore sincronizada (archive/?): $(echo $big | tr '\n' ' ')"
fi

# 6) archive/ é quarentena LOCAL (export de sessão pode ter segredo) — não vai ao host
if [ -e "$DOCDIR/archive" ]; then
  bad "archive/ presente no host (quarentena não deve ser sincronizada)"
else
  ok "archive/ fora do host (quarentena só no Windows)"
fi

# ---------------------------------------------------------------------------
section "HIGIENE DO HOST — lixo de fase antiga e retenção do backup"
# A chave do gateway já vazou para backups de compose e diagnósticos de setembro
# (limpos em 2026-10-21). Só o .env pode conter o valor; se uma cópia voltar a
# aparecer na árvore do host, este check pega antes de virar hábito.
# `-a` (e não `-I`): o vazamento de 2026-10-21 estava dentro de um SQLite antigo
# (`webui.db.bak-*` em _legacy/) e o grep que ignorava binários não viu.
leaks=$(grep -rla --exclude='.env' --exclude-dir=.git "$KEY" "$DOCDIR" 2>/dev/null | head -5)
if [ -n "$KEY" ] && [ -n "$leaks" ]; then
  bad "chave do gateway em arquivo do host: $(echo $leaks | tr '\n' ' ')"
else
  ok "nenhuma cópia da chave fora do .env no host"
fi
# Mesmo tratamento para o dashboard (9119): usuário/senha/secret moraram no
# docker-compose.yml até 2026-10-23 e o comentário mandava procurar num
# .hermes-dashboard.env que nunca existiu. Agora o compose só interpola do .env;
# se o valor voltar a aparecer em arquivo da árvore, é vazamento.
dsenha=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' hermes-dashboard 2>/dev/null | sed -n 's/^HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=//p' | head -1)
dsecret=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' hermes-dashboard 2>/dev/null | sed -n 's/^HERMES_DASHBOARD_BASIC_AUTH_SECRET=//p' | head -1)
dash_leaks=""
for v in "$dsenha" "$dsecret"; do
  [ -n "$v" ] || continue
  achado=$(grep -rlaF --exclude='.env' --exclude-dir=.git "$v" "$DOCDIR" 2>/dev/null | head -3)
  [ -n "$achado" ] && dash_leaks="$dash_leaks $(echo "$achado" | tr '\n' ' ')"
done
if [ -z "$dsenha" ] || [ -z "$dsecret" ]; then
  bad "dashboard sem senha/secret no env do container (defina no .env, ver .env.example)"
elif [ -n "$dash_leaks" ]; then
  bad "senha/secret do dashboard em arquivo do host:$dash_leaks"
else
  ok "senha e secret do dashboard só no .env (compose interpola)"
fi
# Resto de limpeza não fica DENTRO do projeto: vira árvore sincronizada, entra no
# backup e pode guardar segredo (foi o caso do _legacy/: 100 arquivos, inclusive um
# webui.db antigo com a chave). O lugar de guardar histórico é ~/backups, fora do repo.
if [ -e "$DOCDIR/_legacy" ]; then
  bad "resto de limpeza na árvore do projeto: _legacy/ (arquivar em ~/backups e remover)"
else
  ok "sem restos de limpeza (_legacy/) na árvore do projeto"
fi
junk=$(find "$DOCDIR" -maxdepth 1 \( -name 'docker-compose.yml.bak*' -o -name 'docker-compose.yml.backup.*' \
  -o -name '.qwen3-*-backup-*' -o -name '.honcho-*' -o -name '.split-gpu-cpu-backup-*' \
  -o -name '.compose-layer-fix-backup-*' -o -name 'hermes-dashboard-api-key-diagnostic-*.txt' \
  -o -name 'honcho-rebuild-backup-*' \) 2>/dev/null | head -5)
if [ -z "$junk" ]; then
  ok "sem backups/diagnósticos antigos na raiz do projeto"
else
  bad "lixo de fase antiga na raiz do projeto: $(echo $junk | tr '\n' ' ')"
fi
if grep -q '^KEEP_DAYS=14$' /usr/local/bin/hermes-backup 2>/dev/null \
   && grep -q '^KEEP_MONTHS=6$' /usr/local/bin/hermes-backup 2>/dev/null; then
  ok "retenção de backup instalada (14 diários + 6 mensais)"
else
  bad "retenção de backup ausente/divergente (esperado KEEP_DAYS=14 e KEEP_MONTHS=6)"
fi
if [ -x /usr/local/bin/hermes-backup ]; then
  pr=$(/usr/local/bin/hermes-backup --prune-dry-run 2>&1 || true)
  case "$pr" in
    *"RETENTION: 0"*) ok "retenção em dia (0 artefatos fora da política)";;
    *) bad "retenção pendente: $(echo "$pr" | tr '\n' ' ' | cut -c1-160)";;
  esac
fi

# ---------------------------------------------------------------------------
section "INVENTÁRIO DE HARDWARE — coletor (host) + disparador (Windows)"
# O inventário do servidor físico é o único documento que depende do DMI do ferro.
# O que se protege aqui: (a) o coletor é somente LEITURA e não deixa arquivo no
# host; (b) a máscara de série/UUID/asset tag não regride — o arquivo vai para o
# espelho público; (c) o .ps1 continua ASCII puro (acento quebra o parser do
# PowerShell 5.1) e as duas peças estão documentadas em tools.md.
INV_SH="$DOCDIR/tools/inventario_hardware.sh"
INV_PS1="$DOCDIR/tools/inventario-proxmox.ps1"
if [ -f "$INV_SH" ]; then ok "coletor do inventário presente no host"; else bad "coletor ausente: tools/inventario_hardware.sh"; fi
if [ -f "$INV_PS1" ]; then ok "disparador do inventário presente no host"; else bad "disparador ausente: tools/inventario-proxmox.ps1"; fi
if [ -f "$INV_SH" ]; then
  if bash -n "$INV_SH" 2>/dev/null; then ok "coletor do inventário com sintaxe válida"; else bad "coletor do inventário com erro de sintaxe (bash -n)"; fi
  # A promessa do card é "não grava nada no host": sem mktemp, sem redirect/tee.
  if grep -qE 'mktemp|>[[:space:]]*(/tmp/|~/)|[|][[:space:]]*tee ' "$INV_SH"; then
    bad "coletor do inventário escreve arquivo no host (mktemp/redirect/tee)"
  else
    ok "coletor do inventário é somente leitura (não cria arquivo no host)"
  fi
fi
if [ -f "$INV_PS1" ]; then
  if LC_ALL=C grep -q '[^ -~	]' "$INV_PS1"; then
    bad "inventario-proxmox.ps1 com caractere não-ASCII (parser do PS 5.1 quebra)"
  else
    ok "inventario-proxmox.ps1 é ASCII puro (seguro no PS 5.1)"
  fi
  if grep -qE 'Serial Number\|UUID\|Asset Tag' "$INV_PS1"; then
    ok "disparador confere a máscara de identificador único antes de gravar"
  else
    bad "disparador sem a checagem de identificador único (série/UUID/asset tag)"
  fi
  # Em 2026-10-23 duas camadas de base64 deram ~28 KB de linha de comando e o ssh
  # nem iniciou ("O nome do arquivo ou a extensão é muito grande": CreateProcess ~32 KB).
  # O payload vai UMA vez; a linha real é payload + runner (~350 B) + opções do ssh,
  # então 29 KB deixa ~3 KB de folga para o coletor crescer.
  inv_payload=$(base64 -w0 "$INV_SH" | wc -c | tr -d ' ')
  if [ "${inv_payload:-0}" -gt 29000 ]; then
    bad "payload do inventário grande demais ($inv_payload bytes; limite ~32 KB do CreateProcess)"
  else
    ok "payload do inventário cabe na linha de comando ($inv_payload bytes)"
  fi
  # O PS 5.1 mangla aspa dupla em argumento grande para o ssh → o runner não pode ter nenhuma.
  inv_aspa=$(grep -F 'set -u; f=/tmp/.inventario' "$INV_PS1" | grep -c '"' || true)
  if [ "${inv_aspa:-0}" -ne 0 ]; then
    bad "runner do inventario-proxmox.ps1 com aspa dupla (o ssh do PS 5.1 mangla)"
  else
    ok "runner do disparador em uma linha e sem aspa dupla (seguro no ssh do PS 5.1)"
  fi
fi
inv_miss=""
for f in inventario_hardware.sh inventario-proxmox.ps1; do
  grep -qF "$f" "$DOCDIR/docs/runbooks/scripts/tools.md" 2>/dev/null || inv_miss="$inv_miss $f"
done
[ -f "$DOCDIR/docs/runbooks/scripts/inventario-proxmox.md" ] || inv_miss="$inv_miss card"
[ -f "$DOCDIR/docs/architecture/INVENTARIO-HARDWARE-PROXMOX.md" ] || inv_miss="$inv_miss documento"
if [ -z "$inv_miss" ]; then ok "inventário documentado (tools.md + card + documento)"; else bad "documentação do inventário faltando:$inv_miss"; fi
# Execução de verdade: roda o coletor e exige sucesso, stderr vazio, o título e a
# seção de USB — e nenhum identificador único sem a máscara.
if [ -f "$INV_SH" ]; then
  inv_out=$(mktemp); inv_err=$(mktemp)
  sudo -n bash "$INV_SH" >"$inv_out" 2>"$inv_err"
  inv_rc=$?
  inv_leak=$(grep -E '^[[:space:]]*(Serial Number|UUID|Asset Tag):' "$inv_out" | grep -vF '(omitido)' | head -3)
  # Bug real (2026-10-23, no ferro): `\`` dentro de aspas simples no heredoc saia
  # como barra invertida literal no documento ("\`sensors\`"). E o `|| echo
  # desconhecido` colava "none" + "desconhecido" no cabecalho, porque o
  # systemd-detect-virt imprime "none" e SAI 1 quando nao ha virtualizacao.
  inv_bs=$(grep -c '\\`' "$inv_out" 2>/dev/null || true)
  # Bug real (2026-10-23, no VM): o /sys/.../version vem com espaço à esquerda
  # (" 1.10"), o `case` caía no default e o documento saía "USB ( 1.10), 2 porta(s)".
  inv_usbgen=$(grep -E '^Portas por root hub:' "$inv_out" | grep -c 'USB (' || true)
  # Bug real: quando o DMI não publica o tipo 8, a tabela da seção 11 saía com uma
  # linha em branco entre o separador e a única linha (markdown quebrado).
  inv_tab8=$(awk '/^\| Designador externo \|/{s=NR} s && NR==s+2 {print; exit}' "$inv_out")
  # Bug real (2026-10-23, no ferro): o dmidecode alinha o valor com espacos a
  # direita e o resumo saia "| Memoria | Kingston | 2x 16 GB KF3200C16D4/16GX     (2400 MT/s) ...".
  inv_espacos=$(grep -E '^\| ' "$inv_out" | grep -c '   ' || true)
  if [ "$inv_rc" -ne 0 ]; then
    bad "coletor do inventário falhou (exit $inv_rc): $(head -2 "$inv_err" | tr '\n' ' ')"
  elif [ -s "$inv_err" ]; then
    bad "coletor do inventário escreveu no stderr: $(head -2 "$inv_err" | tr '\n' ' ')"
  elif ! head -1 "$inv_out" | grep -q '^# Inventario de hardware'; then
    bad "coletor do inventário: título inesperado na primeira linha"
  elif ! grep -q '^## 10. USB' "$inv_out"; then
    bad "coletor do inventário: seção de USB ausente"
  elif [ -n "$inv_leak" ]; then
    bad "coletor do inventário vazou identificador único: $(echo "$inv_leak" | tr '\n' ' ' | cut -c1-120)"
  elif [ "${inv_bs:-0}" -ne 0 ]; then
    bad "coletor do inventário com barra invertida literal antes de crase ($inv_bs linha(s))"
  elif ! grep -qE 'systemd-detect-virt = [a-z0-9-]+`\)' "$inv_out"; then
    bad "coletor do inventário: cabeçalho do systemd-detect-virt quebrado em duas linhas"
  elif [ "${inv_usbgen:-0}" -ne 0 ]; then
    bad "coletor do inventário: geração de root hub não normalizada (sai 'USB ( 1.10)')"
  elif [ -n "$inv_tab8" ] && ! printf '%s' "$inv_tab8" | grep -q '^|'; then
    bad "coletor do inventário: tabela da seção 11 com linha em branco depois do separador"
  elif [ "${inv_espacos:-0}" -ne 0 ]; then
    bad "coletor do inventário: linha de tabela com espaço repetido (valor DMI não aparado)"
  else
    ok "coletor do inventário roda de verdade ($(grep -c . "$inv_out") linhas, sem identificador único)"
  fi
  rm -f "$inv_out" "$inv_err"
fi

# ---------------------------------------------------------------------------
section "RESUMO"
printf '  PASS=%s  FAIL=%s  WARN=%s\n' "$PASS" "$FAIL" "$WARN"
if [ "$FAIL" -eq 0 ]; then
  printf '  >> STACK OK <<\n'
  exit 0
else
  printf '  >> %s FALHA(S) <<\n' "$FAIL"
  exit 1
fi
