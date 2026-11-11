# Runbook — staging llama.cpp

## Objetivo

Executar testes do candidato llama.cpp sem substituir Ollama, sem alterar o banco
produtivo do Open WebUI e sem expor o servidor de inferência à LAN.

## Requisitos

- host ou projeto Docker de staging separado;
- volumes e `.env` exclusivos;
- GGUF com SHA-256 registrado;
- imagem/build pinado;
- `/dev/kfd` e `/dev/dri` concedidos apenas ao container;
- `HSA_OVERRIDE_GFX_VERSION=10.3.0` para a RX 6600;
- porta publicada somente em loopback durante testes manuais.

## Configuração validada

```text
imagem: llama.cpp:server-rocm-local-785322d
fonte: 785322d17f2d51e5185cf996a1f4e46d87640841
alvo: gfx1030
modelo: Qwen3-4B-Q4_K_M.gguf
contexto validado: 4096 e 16384
```

## Procedimento

1. Confirmar `docker context`, hostname, diretório e volumes de staging.
2. Confirmar que não há mounts de produção.
3. Parar o Ollama somente se a RX 6600 não suportar coexistência.
4. Iniciar o container com `--restart no`, `--read-only` quando compatível e
   porta `127.0.0.1`.
5. Aguardar `/health=200`; processo `Up` isoladamente não é suficiente.
6. Testar `/v1/models`, chat, streaming, reasoning e concorrência.
7. Testar consumidores somente com dados e contas de staging.
8. Remover o container temporário.
9. Restaurar e verificar Ollama.
10. Executar `hermes-ci --quiet` e preservar a evidência.

## Proibições

- não editar `webui.db` produtivo para criar conexão de teste;
- não apontar `owui_knowledge` ou `mem0_memories` produtivos para embeddings novos;
- não executar `docker compose down -v`;
- não remover imagens/volumes Ollama;
- não publicar a porta na LAN;
- não aceitar CPU fallback como sucesso.

## Rollback

Remover o container de staging, iniciar Ollama, aguardar `healthy` e executar o
oráculo. Não restaurar bancos se nenhum dado produtivo foi mutado.
