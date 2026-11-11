# Evidência — build local ROCm compatível

**Data:** 2026-11-01  
**Status:** build local validada em GPU com contexto reduzido; sem cutover.

## Build

- fonte: `llama.cpp` commit `785322d17f2d51e5185cf996a1f4e46d87640841`;
- Dockerfile: `.devops/rocm.Dockerfile` upstream;
- alvo AMD: `gfx1030`;
- imagem local: `llama.cpp:server-rocm-local-785322d`;
- backend compilado: `ggml-hip`;
- imagem criada sem alterar o compose do projeto.

## Configuração necessária

A RX 6600 não foi estável sem o override usado pelo Ollama. Com:

```text
HSA_OVERRIDE_GFX_VERSION=10.3.0
```

o servidor local carregou o GGUF oficial e permaneceu saudável. A configuração
também precisa manter `/dev/kfd`, `/dev/dri` e os grupos de acesso à GPU.

## Teste GPU — contexto 4k

Modelo: `Qwen3-4B-Q4_K_M.gguf` oficial da Qwen.  
Parâmetros: `-c 4096 -ngl 99 --jinja`.

Resultado:

- healthcheck HTTP: `200`;
- `model loaded` e servidor escutando;
- três respostas HTTP `200`;
- tokens/s: `67,22`, `67,42`, `67,32`;
- média: aproximadamente `67,3 tokens/s`;
- baseline Ollama: aproximadamente `61,6 tokens/s`;
- uso observado: aproximadamente 237–244 MiB de memória do container;
- `reasoning_content` separado do campo `content`.

O prompt curto terminou por limite de tokens dentro do raciocínio e deixou
`content` vazio. Isso não é aceite de integração: o template/controle de thinking
deverá ser ajustado e testado antes de qualquer consumer cutover.

## Teste GPU — contexto 16k

Parâmetros: `-c 16384 -ngl 99 --jinja`.

Resultado:

- healthcheck HTTP: `200`;
- container `running`, exit `0`;
- resposta HTTP `200`;
- aproximadamente `67,7 tokens/s`;
- Ollama restaurado saudável ao final.

## Comparação com testes anteriores

- imagem ROCm upstream `0.8.0-dev` sem override: `exit 139`;
- build local sem override: `exit 139`;
- build local com `HSA_OVERRIDE_GFX_VERSION=10.3.0`: funciona em 4k e 16k;
- contexto 65k com KV padrão: OOM de aproximadamente 9,2 GB;
- GGUF oficial informa contexto máximo de 40.960 tokens, portanto não comprova
  o requisito atual de 65k.

## Recuperação e oráculo

Após a janela controlada:

```text
Ollama: running / healthy
CI OK: PASS=271 FAIL=0 WARN=0
```

O container temporário foi removido. Nenhuma URL de produção, compose ou conexão
de consumidor foi alterada.
