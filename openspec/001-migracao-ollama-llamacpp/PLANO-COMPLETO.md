# Plano completo — Migração Ollama para llama.cpp

**OpenSpec:** 001  
**Status:** planejamento documentado; execução ainda não iniciada  
**Escopo:** host `davy-jones-hermes`, RX 6600, Open WebUI, Hermes, mem0, RAG,
Tutor Tiradentes e Apostilas Tiradentes.

## 1. Objetivo

Avaliar e, caso todos os critérios sejam atendidos, substituir o container Ollama
por `llama.cpp`, buscando melhor performance sem quebrar chat, streaming,
embeddings, memória, citações, autenticação ou os dois projetos pedagógicos.

O Ollama será mantido durante todo o staging e somente poderá ser removido após
autorização final separada.

## 2. Estado atual

O ambiente atual usa:

- container `ollama/ollama` com imagem pinada;
- `/dev/kfd` e `/dev/dri` para a RX 6600;
- `HSA_OVERRIDE_GFX_VERSION=10.3.0`;
- `OLLAMA_KV_CACHE_TYPE=q4_0`;
- até dois modelos residentes;
- `qwen3:4b-64k` para chat;
- `qwen3:8b-chat-16k` para estudo;
- `qwen3:8b-extract` para extração/mem0;
- `bge-m3` para embeddings;
- Open WebUI, Hermes e RAG apontando para `http://ollama:11434`.

Baseline histórico a confirmar: `qwen3:4b-64k` em `q4_0`, aproximadamente 5,6 GB,
100% na GPU e cerca de 62 tokens/s.

## 3. Escopo e limites

### Incluído

- serviço paralelo `llama-server`;
- modelos equivalentes em GGUF;
- backend AMD HIP/ROCm ou Vulkan validado por medição;
- compatibilidade OpenAI API;
- chat, streaming, embeddings e raciocínio separado;
- integração progressiva com Open WebUI, Hermes, mem0 e RAG;
- benchmarks, smoke tests, observabilidade e rollback;
- atualização do compose, CI e runbooks.

### Não incluído inicialmente

- remoção do Ollama ou de seus volumes;
- alteração funcional do Tutor Tiradentes;
- alteração da política global de internet;
- migração do worker de podcast;
- fallback silencioso para CPU;
- cutover sem aprovação dos critérios de aceite.

## 4. Governança OpenSpec

Todos os artefatos ficam em:

```text
openspec/001-migracao-ollama-llamacpp/
```

Documentos da especificação:

- `proposal.md` — objetivo, escopo e princípios;
- `architecture.md` — estado atual, staging e contrato de API;
- `decisions.md` — decisões técnicas pendentes;
- `benchmark-plan.md` — baseline, cenários e métricas;
- `security.md` — isolamento e controles;
- `rollback.md` — gatilhos e procedimento de retorno;
- `acceptance.md` — critérios de aceite;
- `tasks.md` — lista de execução;
- `PLANO-COMPLETO.md` — consolidação executiva deste documento.

## 5. Uso de subagentes

Os subagentes trabalham apenas em análise, testes ou documentação delimitada.
Nenhum subagente recebe autorização implícita para apagar dados, alterar produção
ou remover o Ollama.

### Inventário

Mapear compose, volumes, modelos, endpoints, integrações, testes, scripts de deploy
e dependências.

### Performance

Definir parâmetros de `llama-server`, quantização, contexto, batch, offload,
concorrência e métricas de VRAM/latência/tokens por segundo.

### Integração

Validar Open WebUI, streaming, embeddings, Qdrant, mem0, Hermes, Tutor e Apostilas.

### Segurança

Revisar portas, volumes, privilégios, GPU, tokens, isolamento, logs e ausência de
`docker.sock` e `.ssh`.

### Testes

Criar benchmarks automatizados, smoke tests, regressões, teste de rollback e checks
equivalentes aos atuais checks específicos do Ollama.

## 6. Fase 0 — inventário, baseline e backup

1. Confirmar acesso SSH ao host.
2. Registrar containers, imagens, versões e modelos.
3. Registrar GPU, VRAM, RAM, temperatura e processos.
4. Medir o baseline do Ollama.
5. Executar o oráculo completo.
6. Criar backup completo.
7. Validar `gzip`, `tar`, bancos, snapshots e configurações.
8. Registrar hashes dos artefatos.
9. Congelar o estado de referência.

Nenhum serviço de produção será alterado nesta fase.

## 7. Fase 1 — spike isolado

Criar um novo serviço paralelo, sem substituir o Ollama.

Requisitos:

- imagem pinada por digest;
- rede interna Docker;
- nenhuma porta aberta na LAN;
- acesso somente aos dispositivos GPU necessários;
- modelos GGUF separados;
- modelos montados em modo somente leitura quando possível;
- healthcheck HTTP real;
- logs com rotação;
- métricas próprias;
- sem `docker.sock`, `.ssh` ou segredos desnecessários.

Validar:

- carregamento do modelo;
- backend de GPU;
- geração de texto;
- streaming;
- contexto de 65.536 tokens;
- encerramento e reinício;
- ausência de fallback silencioso para CPU.

## 8. Fase 2 — modelos e compatibilidade

Preparar e validar equivalentes GGUF para:

- `qwen3:4b-64k`;
- `qwen3:8b-chat-16k`;
- `qwen3:8b-extract`;
- `bge-m3`.

O embedding deverá manter 1024 dimensões. Se a dimensão ou o modelo mudar,
a coleção vetorial será considerada incompatível e deverá ser reindexada antes
do cutover.

Validar o template de cada modelo, especialmente o comportamento de thinking,
JSON de extração e separação de `content` e `reasoning_content`.

## 9. Fase 3 — benchmark comparativo

Executar o mesmo conjunto de testes no Ollama e no llama.cpp.

### Cenários

1. pergunta curta;
2. pergunta longa;
3. contexto de 16k;
4. contexto de 65k;
5. streaming;
6. raciocínio separado;
7. consulta RAG com citação;
8. geração de embedding;
9. duas requisições concorrentes;
10. carga contínua;
11. troca entre chat, extração e embedding;
12. reinício do serviço.

### Métricas

- tempo até o primeiro token;
- tokens por segundo;
- latência total;
- VRAM e RAM;
- temperatura;
- utilização real da GPU;
- latência de embeddings;
- taxa de erro;
- estabilidade durante concorrência.

### Critério

O llama.cpp deverá igualar ou superar o baseline sem OOM, sem regressão de RAG,
sem erro de embeddings e sem misturar raciocínio com o conteúdo final.

## 10. Fase 4 — integração progressiva

### Open WebUI

Validar conexão OpenAI-compatible, autenticação, streaming, modelos, chat e
respostas longas.

### RAG

Validar embeddings, Qdrant, recuperação, fontes, citações e reindexação quando
necessária. O resultado precisa permanecer compatível com as coleções existentes.

### Hermes e mem0

Validar provider, extração JSON, identidade por e-mail, isolamento, busca, adição
de memória e ausência de `hermes-user`.

Se mem0 não funcionar diretamente com llama.cpp, mantê-lo temporariamente no Ollama.

### Tutor Tiradentes

Confirmar consulta exata por ano e número, banco somente leitura, ausência de web e
respostas oficiais sem regressão.

### Apostilas Tiradentes

Confirmar disciplina, prioridade das fontes locais, fallback SearXNG controlado,
fontes externas separadas e fail-closed.

## 11. Fase 5 — segurança e observabilidade

Implementar ou validar:

- porta interna somente;
- healthcheck de prontidão real;
- restart policy adequada;
- limites de recursos;
- rotação de logs;
- métricas Prometheus;
- latência, erro e uso de GPU;
- autenticação entre serviços;
- firewall e `DOCKER-USER`;
- ausência de montagens privilegiadas desnecessárias.

Atualizar compose, deploy, CI, dashboards, cards operacionais e troubleshooting.

## 12. Fase 6 — staging

Durante o staging:

```text
Ollama       = produção
llama.cpp    = staging
```

O llama.cpp recebe somente tráfego controlado de teste. Executar:

- testes unitários;
- smoke RAG;
- smoke Tutor;
- smoke Apostilas;
- probe stream/non-stream;
- teste mem0;
- benchmark de carga;
- teste de reinício;
- teste de rollback;
- oráculo completo.

## 13. Fase 7 — cutover controlado

Antes do cutover:

1. criar novo backup;
2. validar o backup;
3. salvar configuração e hashes;
4. confirmar critérios de aceite;
5. manter rollback pronto.

Durante o cutover:

1. apontar consumidores para llama.cpp;
2. preservar Ollama e seus volumes;
3. reiniciar apenas dependências necessárias;
4. executar smoke tests;
5. testar usuário comum;
6. verificar Hermes, mem0, RAG, Tutor e Apostilas;
7. observar métricas.

## 14. Rollback

Rollback imediato se houver:

- piora de latência ou tokens/s;
- OOM;
- instabilidade da GPU;
- falha de streaming;
- perda de citações;
- embeddings incompatíveis;
- falha do mem0;
- regressão no Tutor ou Apostilas;
- qualquer `FAIL` no oráculo.

Procedimento:

1. parar tráfego para llama.cpp;
2. restaurar URLs para `ollama:11434`;
3. reiniciar consumidores necessários;
4. executar smoke tests;
5. confirmar o oráculo;
6. preservar logs e evidências.

## 15. Critérios de aceite

### Runtime

- serviço saudável;
- GPU efetivamente utilizada;
- contexto mínimo de 65k validado;
- desempenho igual ou superior ao baseline;
- nenhuma falha de memória;
- reinício automático funcional.

### Integrações

- Open WebUI com streaming;
- `content` e `reasoning_content` separados;
- RAG com fontes e citações corretas;
- embeddings dimensionalmente compatíveis;
- mem0 com identidade e isolamento preservados;
- Tutor sem alteração funcional;
- Apostilas sem regressão.

### Operação

- backup validado;
- rollback testado;
- portas protegidas;
- métricas publicadas;
- documentação atualizada;
- `FAIL=0` e `WARN=0` no oráculo.

## 16. Autorizações e gates

São necessários três gates explícitos:

### Gate A — iniciar investigação

Autoriza inventário, backup, OpenSpec executável, spike paralelo e benchmarks.

### Gate B — staging integrado

Autoriza apontar consumidores de teste para llama.cpp, sem remover Ollama.

### Gate C — cutover

Autoriza colocar llama.cpp em produção após os critérios de aceite.

A remoção definitiva do Ollama exige uma autorização posterior específica.

## 17. Resultado possível

### Migração aprovada

llama.cpp substitui Ollama.

### Migração parcial

llama.cpp assume chat, enquanto Ollama permanece para embeddings ou mem0.

### Migração rejeitada

Ollama permanece como runtime principal se performance, compatibilidade ou segurança
não forem satisfatórias.
