# Evidência — falha de carga do modelo no spike

**Data:** 2026-11-01  
**Produção:** Ollama restaurado e saudável após cada tentativa  
**Cutover:** não realizado

## Tentativa A — contexto 65k, KV padrão

Parâmetros principais:

```text
-c 65536 -ngl 99 --jinja
```

Resultado:

```text
failed to allocate 9216.00 MiB on device 0: cudaMalloc failed: out of memory
failed to allocate buffer for kv cache
exiting due to model loading error
```

Conclusão: o KV cache padrão de 65k não cabe na RX 6600.

## Tentativa B — contexto 65k, KV quantizado

Parâmetros principais:

```text
-c 65536 -ngl 99 --cache-type-k q4_0 --cache-type-v q4_0 --jinja
```

Resultado:

```text
container exit=139
```

O processo terminou com segmentation fault durante a inicialização, antes do
healthcheck.

## Tentativa C — contexto 16k, KV padrão

Parâmetros principais:

```text
-c 16384 -ngl 99 --jinja
```

Resultado:

```text
container exit=139
```

O processo novamente terminou após `llama threadpool init`, antes de aceitar
requisições.

## Diagnóstico atual

O problema não é somente o tamanho de contexto. Há incompatibilidade ou bug entre
a imagem `server-rocm` `0.8.0-dev` usada no spike e o blob GGUF extraído do Ollama,
ou no backend ROCm para essa combinação de modelo/arquitetura.

Não é permitido concluir que llama.cpp é mais rápido ou substituir Ollama com esta
evidência. O próximo caminho seguro é testar um GGUF publicado especificamente para
llama.cpp/Qwen3 ou uma versão estável/build local compatível, mantendo o Ollama como
produção.
