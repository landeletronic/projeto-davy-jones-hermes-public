# Decisões técnicas pendentes

## D001 — Migração paralela

**Decisão proposta:** manter Ollama como produção e executar llama.cpp em staging.

**Motivo:** permite benchmark, teste de compatibilidade e rollback sem interromper
o laboratório.

## D002 — Embeddings não serão trocados implicitamente

**Decisão proposta:** não alterar o modelo de embedding sem confirmar dimensionalidade,
qualidade e necessidade de reindexação do Qdrant.

## D003 — Mem0 terá validação independente

**Decisão proposta:** mem0 só será apontado para llama.cpp depois de validar extração
JSON, identidade por e-mail, isolamento e ausência de `hermes-user`. Se necessário,
mem0 permanecerá temporariamente no Ollama.

## D004 — Sem fallback para a RX 6600

**Decisão proposta:** fallback para CPU não será considerado sucesso. O runtime deverá
demonstrar uso efetivo da GPU e respeitar o limite de VRAM.
