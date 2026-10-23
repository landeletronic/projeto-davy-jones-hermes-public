# hermes-agent — gateway do Hermes (API compatível com OpenAI)

| | |
|---|---|
| Serviço no compose | `hermes` (o nome do container é `hermes-agent`) |
| Imagem | `hermes-tools:local` (build de `ops/docker/hermes-tools/`) |
| Porta | `8642` — **fora da LAN** (só loopback + rede `backend`); bloqueada no `DOCKER-USER` |
| Config | `~/.hermes/config.yaml` no host, montada no container. Fonte versionada: `hermes-data/config.yaml` |
| Memória | plugin mem0 → Qdrant (`mem0_memories`); `user_id` = header `X-Hermes-Session-Key` |
| Ferramentas | `terminal.backend: local` (shell **dentro** do container) |

## Verificar

```bash
docker inspect -f '{{.State.Health.Status}}' hermes-agent      # healthy
curl -s localhost:8642/health
curl -s localhost:8642/v1/models | head -c 300
docker inspect hermes-agent --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}'
```

A última linha **não** pode mostrar `/var/run/docker.sock` nem `~/.ssh` (ver AGENTS §5).

## Reiniciar

```bash
cd /home/usuario/hermes-architect && docker compose restart hermes
```

Mudou `hermes-data/config.yaml`? O caminho normal é `ops\deploy\sync-to-host.ps1` (instala em
`~/.hermes/config.yaml` e reinicia o gateway). **Não** edite o arquivo vivo à mão.

## Sintomas típicos

- **Chat do OWUI responde 502** → gateway fora; `docker logs --tail 50 hermes-agent`.
- **Memória gravada como `hermes-user`** → a chamada veio **sem** `X-Hermes-Session-Key`. Em
  teste manual mande o header com o e-mail; depois confira `user_id` na coleção.
- **Raciocínio vazando no texto** → o modelo escreveu `reasoning` fora das tags. O gateway separa
  `content` e `reasoning_content` nos dois caminhos (SSE e não-stream); a `temperature: 0.3` é o
  que reduz o caso. O smoke de RAG falha se aparecer `thinking` no `content`.
- **Gateway morre ao instalar plugin** → `hermes plugins install --yes-deps` sequestra o venv e
  derruba o gateway. **Não rode.**
- **`tool_search` ligado sem querer** → deve ser `tools.tool_search.enabled = off`.
- **Config divergente** → a suíte compara `hermes-data/config.yaml` (repo) com
  `~/.hermes/config.yaml` (produção) e falha se diferirem.

## Backup

`~/.hermes` entra no tar diário **excluindo caches** e com `sudo tar` (há arquivos de root).
