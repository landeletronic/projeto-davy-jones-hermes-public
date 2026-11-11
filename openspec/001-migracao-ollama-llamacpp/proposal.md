# OpenSpec 001 — Migração Ollama para llama.cpp

**Status:** proposta — não iniciar sem autorização explícita de execução.

## Objetivo

Avaliar e, se aprovado pelos critérios de aceite, substituir o container Ollama por
`llama.cpp`, buscando maior performance sem regressão em Open WebUI, Hermes, mem0,
RAG, Tutor Tiradentes ou Apostilas Tiradentes.

## Escopo

- Criar um serviço `llama-server` paralelo ao Ollama.
- Validar modelos GGUF equivalentes aos modelos atuais.
- Preservar API compatível com OpenAI, streaming, embeddings e raciocínio separado.
- Medir GPU, VRAM, latência, tokens/s e concorrência na RX 6600.
- Adaptar integrações somente após o spike passar.
- Manter rollback para Ollama até a aprovação final.

## Fora de escopo

- Remover o volume ou as imagens do Ollama durante a primeira migração.
- Alterar o Tutor Tiradentes funcionalmente.
- Alterar a política de internet do sistema.
- Migrar o worker de podcast ou qualquer outro serviço não relacionado.

## Princípios

1. Backup antes de cada etapa destrutiva.
2. Produção continua no Ollama durante o staging.
3. Nenhuma inferência de uso de GPU sem medição real.
4. Mudança de embedding exige validação dimensional e possível reindexação.
5. Falha em qualquer critério interrompe a migração e preserva o rollback.
