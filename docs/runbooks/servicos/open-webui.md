# open-webui — interface de chat e RAG

| | |
|---|---|
| Imagem | `ghcr.io/open-webui/open-webui@sha256:a537bbe1…` (**0.12.3**, pinada por digest) |
| Porta | `127.0.0.1:3000` → `8080` no container; a LAN entra pelo **nginx em 443** |
| Dados | volume `open_webui_data` (`webui.db` = usuários, conversas, knowledge) |
| Conexão | `http://hermes:8642/v1` + header `X-Hermes-Session-Key: {{USER_EMAIL}}` |
| Vetores | `VECTOR_DB=qdrant`, coleções com prefixo `owui_` |

## Verificar

```bash
docker inspect -f '{{.State.Health.Status}}' open-webui     # healthy
curl -s -o /dev/null -w '%{http_code}\n' https://192.168.15.231/        # 200 (via nginx)
docker exec open-webui ls -l /app/backend/data/webui.db
```

Login de teste na UI é o que prova o resto: usuário com e-mail → o `user_id` da memória é o
**e-mail**.

## Reiniciar

```bash
cd /home/usuario/hermes-architect && docker compose restart open-webui
```

## Sintomas típicos

- **Chat responde 502/504** → o gateway (`hermes-agent`) está fora. Teste
  `curl -s localhost:8642/health` e reinicie `hermes`.
- **Mudou `rag.*` e nada aconteceu** → essas chaves são `PersistentConfig`: env **não vale**
  depois do 1º boot. Altere na UI (Admin → Settings → Documents) ou pelo banco
  (`tools/set_owui_rag_config.py`).
- **Upload não vira conhecimento** → Docling fora ou `bge-m3` ausente (ver
  [docling](docling.md) e [ollama](ollama.md)).
- **`knowledge_file` com órfãs** → o 0.12.3 não apaga a linha de ligação ao remover
  knowledge/file. `tools/cleanup_owui_leftovers.py` limpa (com a suíte parada).
- **Sessão JWT recusada** → `/api/v1/auths/` aceita só token de sessão humana (`typ=session`);
  API key **não** vale como sessão.
- **`docker exec` não vê `WEBUI_SECRET_KEY`** → é gerada no start; leia de `/proc/1/environ`.

## Backup

`webui.db` entra no tar diário (`.backup` do SQLite, não `cp` do banco vivo). O drill
`tools/drill_restore_clean.sh` semeia o volume **antes** do 1º boot — copiar banco por cima de
container já iniciado deixou o `-wal` velho e o SQLite acusou `database disk image is malformed`.
