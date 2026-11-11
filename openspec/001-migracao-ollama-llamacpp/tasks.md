# Tarefas de execução

## Fase 0 — preparação

- [ ] criar backup completo e validar o artefato;
- [ ] confirmar estado dos containers e modelos;
- [ ] executar o oráculo;
- [ ] medir o baseline;
- [ ] registrar hashes e versões.

## Fase 1 — spike

- [ ] definir imagem pinada do llama.cpp;
- [ ] criar serviço paralelo;
- [ ] preparar modelos GGUF;
- [ ] validar backend AMD;
- [ ] validar contexto, streaming e healthcheck.

## Fase 2 — integração

- [ ] validar API OpenAI-compatible;
- [ ] validar embeddings e dimensionalidade;
- [ ] validar Open WebUI e RAG;
- [ ] validar Hermes e mem0;
- [ ] executar smoke Tutor e Apostilas;
- [ ] substituir checks Ollama por checks equivalentes sem perder contratos.

## Fase 3 — operação

- [ ] atualizar compose, deploy e métricas;
- [ ] atualizar firewall e observabilidade;
- [ ] atualizar runbooks e troubleshooting;
- [ ] testar reinício e rollback;
- [ ] repetir benchmark.

## Fase 4 — cutover condicionado

- [ ] criar backup final;
- [ ] apontar consumidores para llama.cpp;
- [ ] executar smoke e oráculo;
- [ ] observar por 24–72 horas;
- [ ] solicitar autorização final para remover Ollama, se aprovado.
