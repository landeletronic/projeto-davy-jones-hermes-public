# Evidência — Fase 2 — staging integrado controlado

**Data:** 2026-11-01  
**Status:** API e concorrência validadas; consumidores de produção não foram
redirecionados.

## Topologia do teste

- imagem: `llama.cpp:server-rocm-local-785322d`;
- modelo: `Qwen3-4B-Q4_K_M.gguf` oficial;
- `HSA_OVERRIDE_GFX_VERSION=10.3.0`;
- contexto do servidor: 4096;
- slots: 2;
- porta temporária: `127.0.0.1:18083`;
- Ollama parado somente durante a janela e restaurado ao final.

## Resultados

### Chat não-stream

Com raciocínio explicitamente desativado (`reasoning_effort=none`):

- HTTP `200`;
- `content` preenchido corretamente;
- `reasoning_content` ausente;
- resposta observada: `Integração ok.`.

Com raciocínio habilitado (`reasoning_effort=low`):

- HTTP `200`;
- `reasoning_content` separado;
- `content` vazio porque o orçamento de 64 tokens foi consumido no raciocínio.

Isso confirma a separação dos campos, mas também mostra que o orçamento de thinking
precisa ser configurado para o comportamento esperado pelo Hermes/Open WebUI.

### Streaming

- resposta SSE recebida;
- 6 eventos `data:`;
- marcador `[DONE]` presente;
- nenhum erro HTTP.

### Concorrência

Duas requisições simultâneas:

- ambas retornaram HTTP `200`;
- ambas preencheram `content`;
- slots 0 e 1 foram utilizados;
- desempenho observado nos logs ficou aproximadamente entre 58,6 e 58,8 tokens/s
  por requisição sob concorrência.

### Health e ciclo de vida

- healthcheck HTTP `200`;
- modelo carregado sem crash;
- container temporário removido;
- Ollama voltou `running/healthy`.

## Limitações ainda abertas

- não houve redirecionamento do Open WebUI/Hermes;
- embeddings continuam no Ollama;
- Qdrant/RAG ainda não foram executados contra este servidor;
- mem0, Tutor e Apostilas ainda não foram apontados ao staging;
- o GGUF oficial declara contexto máximo de 40960, abaixo do requisito de 65k;
- o campo `content` com thinking exige definição de orçamento/template.

## Oráculo

```text
CI OK: PASS=271 FAIL=0 WARN=0
Ollama: running / healthy
```
