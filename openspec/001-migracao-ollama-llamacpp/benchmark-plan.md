# Plano de benchmark

## Baseline

Registrar antes da mudança:

- modelo e quantização;
- tempo até o primeiro token;
- tokens por segundo;
- latência total;
- VRAM e RAM;
- temperatura e uso da GPU;
- latência de embeddings;
- latência do RAG;
- comportamento com dois modelos residentes.

O baseline histórico do lab é `qwen3:4b-64k` em `q4_0`, aproximadamente 5,6 GB,
100% na GPU e cerca de 62 tokens/s. Deve ser confirmado novamente antes da decisão.

## Cenários

1. pergunta curta;
2. pergunta longa;
3. contexto de 16k;
4. contexto de 65.536 tokens;
5. raciocínio separado;
6. streaming;
7. consulta RAG com citação;
8. geração de embedding;
9. duas requisições concorrentes;
10. reinício do serviço;
11. troca entre chat, extração e embedding;
12. carga contínua.

## Critério comparativo

llama.cpp deverá igualar ou superar o baseline sem:

- OOM;
- fallback silencioso para CPU;
- perda de citações;
- mistura de `content` e raciocínio;
- erro de embedding;
- regressão de memória ou autenticação.
