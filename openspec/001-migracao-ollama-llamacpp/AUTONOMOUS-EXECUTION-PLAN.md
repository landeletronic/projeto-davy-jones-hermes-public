# Plano autônomo de execução — Ollama → llama.cpp

**OpenSpec:** 001  
**Status:** aguardando autorização para execução autônoma  
**Data:** 2026-11-01  
**Executor:** agente DevOps sênior, com subagentes especializados  
**Documento único de planejamento:** este arquivo

## 1. Decisão solicitada

Autorizar o agente a executar autonomamente as fases abaixo, respeitando todos os
gates, preservando o Ollama e interrompendo a execução ao encontrar um bloqueador.

Frase de autorização proposta:

> **autorizo a execução autônoma do plano OpenSpec 001**

Essa autorização não inclui remoção do Ollama, destruição de volumes, descarte de
backups ou cutover final sem o gate específico descrito neste documento.

## 2. Objetivo operacional

Determinar, com evidência reproduzível, se llama.cpp pode assumir uma ou mais funções
do laboratório sem regressão em Open WebUI, Hermes, mem0, RAG/Qdrant, Tutor Tiradentes,
Apostilas Tiradentes, segurança, backup, observabilidade e CI.

O resultado pode ser:

1. **migração completa** — llama.cpp assume chat e funções aprovadas;
2. **migração parcial** — llama.cpp assume somente chat, mantendo Ollama para
   embeddings, extração ou mem0;
3. **migração rejeitada** — Ollama permanece como runtime principal.

Nenhum resultado será escolhido por preferência: a decisão será derivada dos gates.

## 3. Estado conhecido e bloqueadores

### Evidência já obtida

- Ollama 0.40.2 saudável;
- baseline `qwen3:4b-64k`: cerca de 61,6 tokens/s, contexto 65536, 100% GPU;
- `bge-m3`: 1024 dimensões;
- build local llama.cpp ROCm funcional na RX 6600 com `HSA_OVERRIDE_GFX_VERSION=10.3.0`;
- GGUF oficial Qwen3-Q4_K_M: cerca de 67,3 tokens/s em contexto 4k;
- API, streaming e duas requisições concorrentes validados no staging;
- oráculo preservado: `PASS=271 FAIL=0 WARN=0`;
- backup validado e rollback básico exercitado nas janelas de teste.

### Bloqueadores atuais

- o GGUF oficial declara contexto máximo 40960, abaixo do contrato de 65536;
- 65k falhou por OOM ou segmentation fault;
- Open WebUI, Hermes, mem0, RAG, Tutor e Apostilas ainda não foram apontados ao
  staging;
- embeddings llama.cpp ainda não foram validados com 1024 dimensões;
- reasoning precisa de orçamento/template que produza `content` sem perder a
  separação de `reasoning_content`;
- o oráculo atual valida Ollama e não pode ser substituído prematuramente.

## 4. Modelo de trabalho com subagentes

O agente principal mantém a autoridade de execução, mudanças, aprovação de gates e
rollback. Subagentes produzem análises delimitadas e não podem, por conta própria:

- alterar produção;
- apagar dados ou volumes;
- fazer cutover;
- publicar segredos;
- declarar um gate aprovado.

### Subagente de arquitetura

Mapeia contratos de Open WebUI, Hermes, mem0, RAG, Tutor e Apostilas; propõe ordem
de integração e identifica dependências específicas do Ollama.

### Subagente de performance

Analisa contexto, KV cache, offload, concorrência, VRAM, cold start, TTFT, tokens/s
e capacidade da RX 6600. Não aceita fallback silencioso para CPU.

### Subagente de testes

Projeta e revisa testes de contrato, streaming, reasoning/content, embeddings,
RAG, isolamento e consumidores. Benchmarks completos ficam separados do CI curto.

### Subagente de segurança/DevOps

Revisa mounts, portas, privilégios, imagem, hashes, logs, métricas, backup, deploy,
rollback e alertas.

Todos os relatórios dos subagentes serão tratados como evidência não confiável até
serem conferidos pelo agente principal no host e no checkout.

## 5. Fases autônomas e gates

### Fase A — preparação e inventário

- ler instruções do projeto e OpenSpec;
- preservar alterações não relacionadas;
- executar o oráculo antes da janela;
- confirmar containers, imagens, GPU, modelos, mounts e endpoints;
- confirmar backup recente e hash;
- confirmar que Ollama continua saudável.

**Saída:** manifesto de execução e baseline atualizado.  
**Gate A:** `FAIL=0`, backup íntegro e rollback disponível.

### Fase B — runtime reprodutível

- fixar commit, imagem/build e hash do GGUF;
- registrar `HSA_OVERRIDE_GFX_VERSION`, alvo GPU, contexto, slots e flags;
- manter modelos somente leitura;
- criar healthcheck de prontidão real;
- não publicar porta na LAN;
- adicionar configuração separada, sem substituir o compose produtivo;
- verificar ausência de `docker.sock`, `.ssh` e segredos.

**Gate B:** runtime inicia na GPU, sem OOM/segfault, sem CPU fallback e com API
respondendo.

### Fase C — contrato de API

Testar contra llama.cpp e, quando aplicável, comparar com Ollama:

- `/health`;
- `/v1/models`;
- chat stream e não-stream;
- Unicode, Markdown e múltiplas mensagens;
- erro de modelo inexistente, entrada inválida e contexto excedido;
- timeout, cancelamento e reinício;
- `content`, `reasoning_content`, `finish_reason` e `usage`;
- SSE válido, `[DONE]`, sem duplicação ou perda de chunks;
- duas ou mais requisições concorrentes.

**Gate C:** contrato aprovado sem resposta vazia indevida, mistura de raciocínio,
erro de autenticação ou exposição externa.

### Fase D — reasoning e modelo pedagógico

- definir comportamento explícito de reasoning on/off;
- encontrar orçamento que produza resposta final em `content`;
- testar resposta com e sem raciocínio;
- confirmar que `<think>` nunca aparece no conteúdo exibido;
- testar stream e não-stream;
- preservar comportamento do gateway.

**Gate D:** campos separados e conteúdo final utilizável pelo Open WebUI/Hermes.

### Fase E — embeddings e RAG

Executar em coleção temporária primeiro:

- testar endpoint/modelo de embedding;
- confirmar dimensão 1024, finitude e determinismo;
- comparar similaridade e ranking com `bge-m3` atual;
- não reindexar produção sem aprovação específica;
- executar ingestão, recuperação, citações e lastro numérico;
- validar `top_k=8`, chunking atual, complementos e substituição de arquivo;
- validar ausência de órfãos e fail-closed quando não houver fonte.

Se embeddings não forem equivalentes, manter Ollama para embeddings e avaliar
migração somente da geração.

**Gate E:** RAG aprovado ou decisão formal de migração parcial.

### Fase F — consumidores

Validar em ordem de menor risco:

1. chat de estudo em conexão separada;
2. Open WebUI com usuário de teste;
3. Hermes sem alterar autenticação/session key;
4. mem0 com JSON, identidade por e-mail, isolamento e zero `hermes-user`;
5. Tutor por ano/número, sem web e sem alterar o SQLite;
6. Apostilas, fontes locais, rótulo de IA e fallback web controlado.

Não trocar simultaneamente runtime, embeddings, chunking e base vetorial.

**Gate F:** todos os consumidores aprovados ou explicitamente excluídos do escopo
de uma migração parcial.

### Fase G — capacidade, backup e rollback

- benchmark 1/2/4/8 requisições quando couber;
- p50/p95/p99 de TTFT, latência e tokens/s;
- VRAM/RAM/CPU, temperatura, erro e reinícios;
- contexto 4k, 16k, 32k e 40k/65k conforme o modelo;
- carga sustentada e recuperação;
- backup completo novamente;
- validação de gzip/tar/SQLite/snapshots;
- prova de restore em ambiente temporário;
- rollback de endpoint sem restaurar banco quando não houve mutação.

**Gate G:** SLOs definidos antes da comparação, zero OOM/crash-loop e rollback
ensaiado.

### Fase H — canary e cutover condicionado

Somente após autorização do gate final:

- congelar mudanças;
- criar backup final;
- apontar somente um consumidor/grupo de teste;
- manter Ollama pronto como fallback;
- observar erros, latência, GPU, RAG, auth e memória;
- abortar automaticamente diante de qualquer critério crítico;
- ampliar gradualmente, nunca trocar tudo de uma vez;
- executar o oráculo após cada mudança.

**Gate H:** canary estável pelo período definido no runbook, sem regressão.

O cutover global e a remoção do Ollama exigem autorização separada posterior.

## 6. Critérios de abortamento imediato

- qualquer `FAIL` no oráculo;
- exposição de porta na LAN;
- segredo em log, imagem ou configuração;
- perda de isolamento por usuário;
- OOM, exit 139, crash-loop ou fallback CPU;
- conteúdo com `<think>` ou reasoning misturado;
- citação ausente ou número sem lastro;
- embedding incompatível com Qdrant;
- falha de autenticação/session key;
- corrupção, exclusão ou mutação inesperada de dados;
- regressão de desempenho além do limiar pré-definido;
- backup não íntegro ou rollback indisponível.

## 7. Segurança operacional

- sem `docker.sock` ou `~/.ssh`;
- backend em rede interna/loopback;
- autenticação no gateway;
- modelos somente leitura;
- imagem e GGUF pinados por digest/hash;
- usuário não-root quando compatível;
- limites de request, contexto e concorrência;
- logs sem prompts, respostas, tokens, cookies ou segredos;
- métricas com labels de baixa cardinalidade;
- deploy idempotente;
- nunca usar `down -v`, reset de firewall ou remoção ampla;
- reload de upstream nginx após recriação de container quando necessário.

## 8. Observabilidade e documentação a produzir

Durante a execução serão criados ou atualizados, somente quando necessários:

- manifesto YAML desta OpenSpec;
- manifestos de runtime/modelos/checksums;
- compose ou override de staging;
- healthcheck e smoke tests;
- contrato OpenAI e testes de regressão;
- métricas `hermes_llm_*` e alertas de backend;
- dashboard/queries de latência, erro, GPU e modelo carregado;
- runbook de instalação, operação, diagnóstico e rollback;
- card operacional em `docs/runbooks/servicos/`;
- card de cada script em `docs/runbooks/scripts/`;
- evidências por fase em `evidence/`;
- atualização do índice `docs/README.md`.

O agente não substituirá checks Ollama enquanto Ollama for produção. Após cutover
aprovado, os checks serão migrados em mudança separada, mantendo teste explícito de
rollback durante a janela de retenção.

## 9. Commits e rastreabilidade

Cada fase concluída terá:

- evidência com data, comandos resumidos, hashes e resultado;
- `git diff --check`;
- commit pequeno e temático;
- status do working tree, preservando alterações alheias;
- oráculo antes/depois quando houver mudança aplicável.

Nenhum segredo, banco, log bruto ou artefato grande será commitado.

## 10. Autonomia e comunicação

Após a autorização, o agente poderá executar as fases seguras sem pedir confirmação
para cada comando rotineiro. Deve pedir nova autorização para:

- cutover global;
- remoção do Ollama, imagens ou volumes;
- reindexação definitiva do Qdrant;
- alteração destrutiva de dados;
- mudança de firewall fora do escopo aprovado;
- publicar/deployar externamente.

Ao final de cada gate, o agente reportará estado: **aprovado**, **bloqueado** ou
**rejeitado**, com evidências e próximo passo. Em caso de falha, fará rollback e
parará, sem tentar “consertar” silenciosamente produção.

## 11. Resultado esperado da autorização

Com a autorização, a próxima execução será a Fase E/F de integração controlada,
priorizando contrato de reasoning, conexão de estudo, RAG em staging e validação dos
consumidores, mantendo Ollama como fallback e sem cutover global.
