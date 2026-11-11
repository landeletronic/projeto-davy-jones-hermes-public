# Plano de rollback

## Gatilhos

Executar rollback se ocorrer:

- piora de latência ou tokens/s;
- uso excessivo de CPU ou VRAM;
- OOM ou instabilidade da GPU;
- falha de streaming;
- perda de citações;
- incompatibilidade de embeddings;
- falha no mem0;
- regressão no Tutor ou Apostilas;
- qualquer `FAIL` no oráculo.

## Procedimento

1. parar o tráfego para `llama-server`;
2. restaurar URLs do Open WebUI, Hermes e RAG para `ollama:11434`;
3. reiniciar somente os consumidores necessários;
4. executar smoke tests;
5. confirmar o oráculo;
6. preservar logs e evidências do incidente.

O volume e os modelos do Ollama não serão removidos até uma autorização final
posterior à observação em produção.
