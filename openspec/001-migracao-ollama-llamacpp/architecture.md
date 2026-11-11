# Arquitetura proposta

## Estado atual

```text
Open WebUI ──┐
Hermes/mem0 ─┼──> ollama:11434 ──> RX 6600 / ROCm
RAG         ─┘          ├── chat
                         ├── extração
                         └── embeddings bge-m3
```

O compose atual usa `ollama/ollama` com `/dev/kfd`, `/dev/dri`,
`HSA_OVERRIDE_GFX_VERSION=10.3.0`, `OLLAMA_KV_CACHE_TYPE=q4_0` e dois modelos
residentes. O Open WebUI usa Ollama para chat e embeddings; Hermes/mem0 também
depende do endpoint atual.

## Arquitetura de staging

```text
Open WebUI/Hermes ──> Ollama (produção)
                         │
                         └── comparação

llama-server (staging) ──> modelos GGUF ──> RX 6600
```

O novo container deverá ter:

- rede interna Docker;
- nenhuma porta exposta à LAN;
- imagem pinada por digest;
- backend HIP/ROCm ou Vulkan comprovadamente funcional;
- modelos montados separadamente e somente leitura;
- healthcheck HTTP;
- métricas e logs rotacionados;
- ausência de `docker.sock`, `.ssh` e segredos desnecessários.

## Contrato de compatibilidade

Validar os endpoints equivalentes:

- `/v1/chat/completions`, incluindo streaming;
- `/v1/embeddings`;
- `/health` ou endpoint de readiness definido pelo servidor;
- separação entre `content` e `reasoning_content`;
- erros, timeouts e encerramento limpo.

## Modelos

Validar equivalentes GGUF para:

- `qwen3:4b-64k`;
- `qwen3:8b-chat-16k`;
- `qwen3:8b-extract`;
- `bge-m3`.

O modelo de embedding deverá manter 1024 dimensões. Se não mantiver, a coleção
vetorial deverá ser reindexada antes do cutover.
