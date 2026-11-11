# Evidência — Fase 1 — spike llama.cpp ROCm

**Data:** 2026-11-01  
**Status:** imagem e GPU validadas; carga do modelo ainda não executada para não
interromper a produção Ollama nem contaminar o benchmark.

## Imagem

```text
ghcr.io/ggml-org/llama.cpp:server-rocm
digest: sha256:b50087da4b37cf89feecb7106f0f851dd6ad11d4a57edbbb4214592602a1d6e4
versão: 0.8.0-dev (build 12030, commit a91eab67d)
```

A imagem upstream informa que as variantes GPU não são cobertas integralmente pelo
CI upstream; por isso a validação local é obrigatória.

## GPU

Com `/dev/kfd`, `/dev/dri`, grupo `video` e grupo `991`:

```text
Available devices:
  ROCm0: AMD Radeon RX 6600 (8176 MiB, 8152 MiB free)
```

O backend ROCm reconheceu a GPU correta.

## Modelo de staging

O `Modelfile` do Ollama aponta `qwen3:4b-64k` para um blob GGUF reutilizável:

```text
/root/.ollama/models/blobs/sha256-3e4cb14174460404e7a233e531675303b2fbf7749c02f91864fe311ab6344e4f
```

Foi copiado sem alterar o volume persistente para:

```text
/var/tmp/llama-staging/qwen3-4b-64k.gguf
```

Tamanho observado: 2,4 GB.

## Restrição operacional

O Ollama mantém `qwen3:4b-64k` e `bge-m3` residentes na RX 6600. Carregar o mesmo
modelo simultaneamente no llama.cpp poderia gerar OOM, fallback silencioso ou medir
contenção em vez de performance. O próximo teste deve ser uma janela controlada,
com preservação do backup e rollback simples.
