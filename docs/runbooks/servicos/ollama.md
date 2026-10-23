# ollama — servidor de modelos (chat + embeddings)

| | |
|---|---|
| Imagem | `ollama/ollama@sha256:58b807f1…` (pinada por digest) |
| Porta | `11434` publicada, **bloqueada na LAN** pela cadeia `DOCKER-USER` |
| Dados | volume `ollama_data` |
| Modelos | `qwen3:4b-64k` (chat), `bge-m3` (embeddings 1024d), `qwen3:8b-extract` (extração do mem0) |
| GPU | RX 6600 8 GB · `OLLAMA_KV_CACHE_TYPE=q4_0` |

## Verificar

```bash
docker inspect -f '{{.State.Health.Status}}' ollama      # healthy
docker exec ollama ollama list                            # os 3 modelos
docker exec ollama ollama ps                              # quem está na VRAM agora
```

`ollama ps` é a **prova** de GPU: `qwen3:4b-64k` deve aparecer com ~5,6 GB e `100% GPU`
(se aparecer `13%/87% CPU`, o KV cache não é `q4_0`).

## Reiniciar

```bash
cd /home/tlandskron/hermes-architect && docker compose restart ollama
```

## Sintomas típicos

- **Resposta demora 60–90 s na primeira mensagem** → swap de modelo: o Ollama é **serializado**.
  `ollama ps` mostra qual está residente. Não é bug; é o custo de manter o `bge-m3` junto.
- **`model not found`** → o volume foi recriado ou o modelo foi apagado:
  `docker exec ollama ollama pull bge-m3` (idem `qwen3:4b-64k`).
- **OOM / cai para CPU** → outro processo ocupando a VRAM (ver `rocm-smi`); o lab só suporta
  a família `qwen3` nesse tamanho.
- **Embedding de RAG falha** → `bge-m3` não está baixado; o upload do OWUI depende dele.
