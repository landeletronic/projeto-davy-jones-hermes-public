# Critérios de aceite

## Runtime

- `llama-server` inicia automaticamente;
- healthcheck fica saudável;
- GPU é usada efetivamente;
- contexto mínimo de 65.536 tokens é validado ou a incompatibilidade é explicitamente
  registrada e impede o cutover;
- desempenho igual ou superior ao baseline;
- sem OOM durante carga e concorrência.

## Integrações

- Open WebUI funciona com streaming;
- `content` e `reasoning_content` permanecem separados;
- RAG recupera fontes e citações corretas;
- embeddings têm dimensão compatível;
- mem0 preserva identidade e isolamento;
- Tutor Tiradentes continua consulta exata e somente local;
- Apostilas Tiradentes preserva disciplina, fontes e fallback web controlado.

## Operação

- backup pré-migração validado;
- rollback testado;
- portas e privilégios revisados;
- métricas publicadas;
- documentação e runbooks atualizados;
- `tests/verify_stack.sh` termina com `FAIL=0` e `WARN=0`.

A remoção definitiva do Ollama exige autorização separada depois desses critérios.
