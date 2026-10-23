# ai-memory.md — Memória de contexto do lab davy-jones-hermes

> **O que é este arquivo.** A memória consolidada do projeto, escrita para ser lida por
> **qualquer sessão nova** (humana ou agente) antes de tocar no lab: as diretrizes combinadas,
> o que já foi executado **sem problemas**, e o que já deu **problema** — com causa e correção.
> É o "inbox entre agentes" do mapa mental (N3): onboarding em um arquivo.
>
> **Como usar:** leia a Parte 1 inteira antes de propor mudança. Ao pegar uma tarefa, consulte a
> Parte 3 — se parecer com algo já vivido, comece pela correção registrada. Ao corrigir um bug
> novo, **adicione um check em `tests/verify_stack.sh`** (regra do projeto) e atualize este arquivo.
>
> **Período coberto:** 2026-10-09 → 2026-10-21 · **Fases 0 a 7 + endurecimento (#1-#10) + #4 e P3 + Fases 1/3/5 (estrutura e documentação)** · Suíte: **PASS=206 / FAIL=0 / WARN=0**
> **Host:** `davy-jones-hermes` (192.168.15.231) · Ubuntu 26.04.1 · 15 GB RAM · 16 vCPU · RX 6600 8 GB
> **Documentos relacionados:** `README.md` (entrada), `AGENTS.md` (regras),
> `docs/reports/RELATORIO-LACUNAS.md` (backlog), `docs/plans/PLANO-IMPLEMENTACAO-MEM0.md` (plano),
> `docs/runbooks/FASE-5bcd-RUNBOOK.md`, `docs/runbooks/FASE-6-RUNBOOK.md`,
> `docs/runbooks/FASE-7-RUNBOOK.md` (runbooks), `docs/learning/MAPA-MENTAL.md` (trilha).

---

# PARTE 1 — DIRETRIZES DO PROJETO (o combinado no início)

## 1.1 Objetivo

Um **lab de IA 100% local** para um **escritório de advocacia pequeno (2 a 10 usuários)**:
memória de longo prazo (**mem0**) + **RAG jurídica com citações**, tudo rodando no host
`davy-jones-hermes`, sem internet. O lab é também o **veículo prático** do aprendizado
(trilha N0→N4 do `docs/learning/MAPA-MENTAL.md`, do Flow #663).

## 1.2 Requisitos inegociáveis

| # | Diretriz |
|---|---|
| D1 | **100% local/offline** — nada pode depender de internet; a stack sobrevive à queda do link. |
| D2 | **Multiusuário com login e-mail+senha** (Open WebUI); `user_id` = **e-mail logado**. |
| D3 | **Isolamento por usuário** — nenhum usuário pode ver memória de outro. |
| D4 | **Qdrant compartilhado** entre RAG e mem0 (`mem0_memories`; nada de banco paralelo). |
| D5 | **Honcho removido permanentemente** (decisão do usuário; não reintroduzir). |
| D6 | **Escala de escritório pequeno**: isolamento, backup, auditoria leve e citações verificáveis importam mais que throughput. |
| D7 | **Revisão humana obrigatória** nas respostas com citação — o `[1]` aponta o trecho, mas o modelo pode citar errado. |
| D8 | Imagens **pinadas** por digest/versão — proibido `:main`, `:rocm`, `:latest`. |
| D9 | **Nada de nuvem** (nenhuma conexão OpenAI/Anthropic na config do OWUI). |

## 1.3 Decisões técnicas consolidadas

| Tema | Decisão |
|---|---|
| Memória | **mem0 OSS in-process** dentro do Hermes (`mode: "oss"`) — zero containers novos |
| Vector store | **Qdrant** (`mem0_memories`, 1024 dims) — coleção criada **pelo mem0**, nunca à mão |
| Chat | **`qwen3:4b-64k`** (65.536 tokens reais, `OLLAMA_KV_CACHE_TYPE=q4_0` desde 2026-10-20: 5,6 GB **100% GPU**, ~62 tok/s — com `q8_0` eram 8,3 GB e 13% das camadas na CPU, ~31 tok/s) |
| Extração de fatos | **`qwen3:8b-extract`** (variante sem *thinking*) |
| Embeddings | **`bge-m3`** (1024 dims), via Ollama |
| Pipeline do RAG | **Docling Serve CPU** → **Open WebUI Knowledge** (chunk + bge-m3) → Qdrant (`owui_knowledge`/`owui_files`) |
| Identidade | header `X-Hermes-Session-Key: {{USER_EMAIL}}` (OWUI) + patch de 1 linha no plugin mem0 |
| Acesso LAN | **HTTPS** via nginx: `:443` (OWUI) e `:3001` (Grafana); `:3000` só no loopback |
| Monitoramento | Prometheus + node-exporter + cadvisor + Grafana (Grafana **não** publica porta) |
| Backup | `hermes-backup` diário 03:30 (host, retenção 7) → pull para `\\localhost\backups\hermes-lab` (retenção 8) |
| Oráculo | `tests/verify_stack.sh` (176 checks) + **CI diário 04:10** com painel no Grafana |
| Busca web | **desligada** (`ENABLE_WEB_SEARCH=false`); SearXNG interno pronto, mas opcional |

## 1.4 Modelo de trabalho (regras que o agente segue)

1. **Autorização explícita por fase** — proposta, aprovação do usuário, execução, verificação.
   O host é **lab**: operações destrutivas foram pré-autorizadas pelo usuário.
2. **Uma mudança por vez**; rodar o oráculo **antes e depois**.
3. **Todo bug corrigido vira teste de regressão** (regra do `AGENTS.md`) — e todo invariante
   novo vira um check na suíte. *"O bug não aparece nunca mais."*
4. **Falhar primeiro** — quando possível, provar que o teste/verificação detecta o problema
   antes de corrigir (o teste negativo é obrigatório na prática).
5. **Não mexer no que não foi pedido**; preferir comandos **idempotentes** e sempre com verificação.
6. **Antes de trocar imagem**: rodar o backup e depois a suíte.
7. **Documentar a pegadinha** no runbook da fase + neste arquivo.
8. Idioma do projeto: **português** (docs e comunicação).

## 1.5 Critério de "pronto"

- Suíte verde (`PASS=N / FAIL=0`, `WARN` justificado), rodada **no host**;
- o que foi feito **persiste** ao restart (`restart: unless-stopped`, cron/systemd habilitados);
- existe **backup** do estado novo e o resultado é **visível sem SSH** (Grafana);
- o caminho executado tem documentação de **reprodução e recuperação**.

## 1.6 Trilha paralela: "Davy Jones GPT" (ChatGPT, 20/10/2026)

O dono do projeto consolidou, numa conversa do ChatGPT, um **track paralelo** — arquitetura
prevista (Proxmox → VM → Docker, Vulkan/RADV, `/opt/davy-jones`, Honcho como memória, RAG com
BM25+RRF+reranker), etapas 2–3.10 e uma lista de **regras de implementação**
(READ/WRITE/DESTRUCTIVE, `verify` somente leitura, `.sh`+`.md` com o mesmo nome, estado comprovado
≠ hipótese, LLM inteiro na VRAM provado por medição). Fontes:
`docs/plans/DAVY-JONES-GPT-CONTEXTO-CONTINUIDADE.md` e
`docs/reports/RELATORIO-TECNICO-DAVY-JONES-GPT.md`.

**Regra de leitura:** esse track é **intenção datada**, não inventário. O que vale é o host + este
repo + a suíte. Divergências registradas (memória → mem0; Vulkan → ROCm; VM 8 GB → host 16 vCPU/15 GB;
`/opt/davy-jones` → `hermes-architect`; RAG própria → RAG do OWUI) e os itens que seguem em aberto
(RX 5700, matriz 4K–32K, script 3.10 com bug `unbound variable`) estão na memória do servidor:
`decisions/gpt-track-vs-lab.md` (decisão) e `concepts/davy-jones-gpt-track.md` (conteúdo). As regras
adotadas estão no `AGENTS.md` §6.1.

---

# PARTE 2 — O QUE FOI EXECUTADO SEM PROBLEMAS

## 2.1 Trilha cronológica

| Data | Fase | Resultado |
|---|---|---|
| 2026-10-09 | **0 — Preparação** | imagem `hermes-tools:local` (mem0ai + qdrant-client + ollama), compose/redes/volumes reconstruídos |
| 2026-10-09 | **1 — Qdrant** | `qdrant` v1.15.2 no ar; coleção criada só pelo mem0 (hoje **v1.19.2**, upgrade em 2026-10-20) |
| 2026-10-09 | **2 — Ollama/GPU** | ROCm + RX 6600 (`HSA_OVERRIDE_GFX_VERSION=10.3.0`); modelos baixados |
| 2026-10-09 | **3 — Open WebUI** | auth e-mail+senha (admin `admin@example.com` + `teste@example.com`) |
| 2026-10-09 | **4 — Hermes gateway** | plugin mem0 ativo em `mode: oss`; `/health` ok |
| 2026-10-09 | **5 — E2E multiusuário** | **RISCO #1 resolvido**: `payload.user_id` = e-mail; B não vê memória de A |
| 2026-10-10 | **6a — Endurecer** | firewall de verdade (`DOCKER-USER`), higiene de disco (Ollama 15→8,3 GB) |
| 2026-10-17 | **5b/5c/5d** | conexão Hermes no OWUI + `tool_search: off` + `hermes-agent` liberado p/ não-admin |
| 2026-10-17 | **N2 — Oráculo** | `verify_stack.sh` (36 checks) + `run-tests.ps1` + `AGENTS.md` |
| 2026-10-18 | **6.1–6.5** | RAG com citações, TLS, SearXNG, monitoramento, backup, upgrade OWUI 0.12.3 |
| 2026-10-18 | **7 — CI + 3 bugs** | oráculo automático (04:10), métricas no Grafana; 3 bugs reais corrigidos (Parte 3) |
| 2026-10-20 | **Endurecimento (#1–#10) + P3** | alertas/backup/firewall versionados, healthchecks, rotação de logs, higiene do mem0, raciocínio separado, restore em ambiente limpo, renovação TLS; **#4** (8642 fora da LAN, sem `docker.sock`/`~/.ssh` no gateway), KV q4_0 (100% GPU, ~2× tok/s), base de teste removida, `grafana.db` no backup, pull com SHA-256, **Qdrant 1.19.2**. Detalhe: `docs/reports/RELATORIO-LACUNAS.md` |
| 2026-10-21 | **Fases 1 + 5 — estrutura** | a raiz vira **código**: conhecimento em `docs/{architecture,runbooks,plans,reports,learning}` com índice em `docs/README.md`; `archive/` (gitignored) recebe ebook/PDF/exports; o sync leva `docs/` ao host. Higiene do host: 28 itens com a chave em texto puro apagados, 84 scripts antigos em `_legacy/`, retenção **14 diários + 6 mensais** com `--prune-dry-run`. Suíte: 151 → **159** |
| 2026-10-21 | **Fase 3 — documentação operacional** | **12 cards de serviço** (`docs/runbooks/servicos/<container>.md`), **9 cards de script** (`docs/runbooks/scripts/<base>.md` + tabela de `tools/`), **triagem por sintoma** (`TROUBLESHOOTING.md`) e índice completo em `docs/README.md`. Invariantes 1:1 na suíte: container↔card, script↔card, doc↔índice, título H1, nada >1 MB na árvore, `archive/` fora do host. Suíte: 159 → **165** |
| 2026-10-21 | **`_legacy/` arquivado + segredo em binário** | 100 arquivos (2,1 MB) arquivados em `~/backups/legacy-scripts-2026-10-21.tar.gz` (200 KB, 600, + manifest com sha256) e removidos da árvore (projeto 992 KB). **Achado:** o `webui.db.bak-before-cloud-removal` guardava a `API_SERVER_KEY` em texto puro — o check usava `grep -I` (ignora binário) e não via; agora usa `-a`. Excluído do arquivo de propósito (registrado no manifest). Suíte: 165 → **166** |

| 2026-10-21 | **Eixo de estudos - inbox + share SMB** | `docs/plans/DESENHO-INBOX-DOCUMENTS.md`: documentos **fora do repo**, árvore única no host (`~/documents`) compartilhada por **SMB** (os usuários gravam direto, sem push do Windows), worker por `sha256` com `manifest.csv` em `~/rag-state`, base **uma por concurso** (`Tiradentes BM`, depois magistratura/HCPA), processo **nunca** apaga sozinho. **Feito:** árvore (2027/2028, `edital`, `prova_gabarito`, `referencias`, `incoming`, `_rejeitados`, `_relatorio`) + `LEIA-ME.txt`; Samba 4.23.6 como serviço de host (`ops/samba/smb.conf` versionado, `smbd` habilitado), 445 **só** para `192.168.15.0/24` (ufw + `hosts allow`), `documents.tgz` no backup; share **provado** por `smbclient` (listar/gravar/apagar) e senha rotacionada para valor aleatório — **falta você definir a senha SMB** (`smbpasswd`). Suíte: 166 → **176** |

| 2026-10-21 | **Eixo de estudos - Fase 0 (spike de ingestão)** | 2 PDFs reais de 2026 na base `Tiradentes BM`: Docling **45 s / 20 páginas**, 33 vetores, resposta com citação `[1]` correta. **Achados:** (a) o splitter de cabeçalho do OWUI fatiava o markdown do Docling em **88 chunks de 281 chars** (um de 13) → desligado, 1200/200 e `top_k` 6 → 30 chunks de 850; (b) o gateway injeta **21,6k tokens** por chamada (o `AGENTS.md` de 36 KB montado em `/workspace` + ferramentas) e o OWUI faz **5 chamadas por mensagem** → **432-588 s**; Ollama direto com os mesmos 6 chunks: **12-34 s**; (c) `qwen3:4b-64k` **inventou** no gabarito ("48 questões", "C") e o `qwen3:8b-extract` (16k, já residente) respondeu **honesto**; (d) a página do gabarito com a `26 = B` não veio no `top_k` 8 (tabela sem semântica) → busca híbrida. Detalhe em `docs/plans/DESENHO-INBOX-DOCUMENTS.md` §18. **Aplicado em seguida (4 decisões aprovadas):** segunda conexão do OWUI direto no Ollama (`qwen3:8b-chat-16k`, 16k ctx) para o chat de estudo (o gateway monta o repo e injeta o `AGENTS.md` de 36 KB = **21,6k tokens**/chamada), `tags`/`follow-up` desligados, `task.model.default` no modelo de estudo, busca híbrida ligada, `top_k=8` e nomes achatados (`tiradentes-bm-2026-prova.pdf`). Resultado: **29 s** por pergunta (era 432-588 s) e as duas perguntas do spike corretas, inclusive **50 questões / Q26 = B**; `OLLAMA_KEEP_ALIVE=30m` para a 1ª pergunta não pagar a carga do modelo. Suíte ganhou 10 checks (conexão local, modelo de estudo, splitter/chunk/top_k/híbrida, tags/follow-up/task model) |

| 2026-10-21 | **Eixo de estudos - Fase 2 (worker `rag-ingest`)** | `tools/rag_ingest.py` (host, só stdlib) + `tools/owui_upload.py` (dentro do container, sessão JWT): varre `~/documents`, ignora `_*`/`LEIA-ME.txt`, espera o arquivo estabilizar **30 s**, dedupa por **SHA-256** no `~/rag-state/manifest.csv` (10 colunas do desenho), sobe com nome **achatado** (`tiradentes-bm-2026-prova.pdf`) e grava `ingest.log` + `_relatorio/INGESTAO.md`. O share entra no OWUI como **`/documents:ro`** (compose + check). **Provado:** 16 PDFs (2020-2027) em **9m45s / 423 vetores**; 2ª execução **0 novo / 16 já ingerido** (16 files, 16 links, sem duplicata); `--remover <sha>` **17→16** sem linha órfã; PDF corrompido → `_rejeitados/` com `.motivo.txt` e **`file` descartado** (a base continua 16/16); `--dry-run` não escreve nada. **Limite medido:** com 16 documentos, "resposta da Q10 do gabarito de 2024" **não** trouxe o gabarito de 2024 (o ano está no *nome*, não no texto; `top_k=8` entre 423 vetores) — confirma que consulta por número/ano é do **banco de questões**, não do RAG. Suíte: 176 → **191** |

| 2026-10-21 | **Eixo de estudos - Fase 3 (worker no cron)** | o mesmo worker, agora **sozinho a cada 15 min**: `ops/bin/rag_ingest.sh` (instalado em `/usr/local/bin/rag-ingest`) reexecuta como `tlandskron` (como root, `_relatorio/` e `_rejeitados/` nasceriam de root no share), toma `flock -n` (`~/rag-state/ingest.lock`: um lote grande passa dos 15 min e não pode ser atropelado) e registra em `~/rag-state/cron.log` (rotação 5 MB); `ops/cron/rag-ingest.cron` → `/etc/cron.d/rag-ingest` (`*/15 * * * * tlandskron`, com `HOME`). **Provado disparando** (troca temporária para `* * * * *`): 00:40 ingeriu um `.txt` que o usuário tinha acabado de deixar no share (190 chars) e 00:41 respondeu `0 novo`, depois voltou para `*/15`. **Bug de falso alarme corrigido:** `aviso_extracao()` agora considera o tipo — `.txt` de 239 bytes com 190 chars é o arquivo inteiro (antes avisava "escaneado? OCR falhou?"); a suíte checa a função. Base: **17 documentos / 424 vetores**. Suíte: 194 → **200** |

| 2026-10-22 | **Varredura: queda de energia + versão nova** | host desligado de 01:09 a 09:22; ao voltar, **só o prometheus não subiu** (`Exited (255)` com `restart: unless-stopped`) → 7 FAIL e alertas cegos por 4 h; `docker compose up -d prometheus` resolveu. **Achado maior:** a correção do gabarito de 2022 (mesmo caminho, `.txt` com `34E` no lugar do `24E`) entrou como documento **novo** e a versão antiga ficou na base (duas citações com o mesmo nome, uma com a resposta errada) → agora **mesmo caminho + SHA novo = substituição** (sobe a nova, remove a antiga depois, marca `substituido`; `--substituir` virou no-op e a suíte prova num sandbox). O `--dry-run` voltou a mostrar no terminal (`[ -t 1 ]` → `tee`) e o `watch-alerts.ps1` **avisa** quando o Prometheus não responde: `$ErrorActionPreference='Stop'` derrubava o script no stderr do `ssh` antes do tratamento (provado com `-Remote 192.0.2.1`: notifica na 1ª, suprime na 2ª em 6 h). Base: **16 documentos / 424 vetores** (o PDF de OCR e a versão com o erro saíram). Suíte: 200 → **207**. **Fuso horário:** o dono estranhou os horários ("caí às 21:00, o log diz 01:09") — o host estava em `Etc/UTC` desde sempre, então o cron rodava 3 h deslocado (backup "03:30" à meia-noite) e todo log mentia; `sudo timedatectl set-timezone America/Sao_Paulo` + worker/logs em hora local com offset, com check novo na suíte. **Tarefas do Windows:** a de alertas (a cada 30 min) chamava `powershell.exe` direto e a janela do console roubava o foco de quem estava digitando → agora `wscript.exe` + `run-hidden.vbs` (zero janela, provado com `MainWindowHandle=0`), reaplicado pelo sync, e o toast passou a sair como **Hermes Lab** (AUMID próprio) |
| 2026-10-22 | **Fase 4 do eixo de estudos: o worker se torna observável** | o worker publica `hermes_rag_*` no textfile do node-exporter (`ci/textfile/hermes_rag.prom`, escrita atômica tmp+chmod+mv) ao fim de **toda** execução — inclusive a que falha: documentos na base, falhas ativas, rejeitados, aguardando, pendentes (arquivo no share há >1 h fora da base), idade do pendente mais antigo, timestamp/sucesso/duração. Quatro alertas `LabRag*`: **pendente > 24 h** (o pedido da fase), parado há 2 h, última execução com falha e métrica ausente. "Pendente" é documento que **não entrou** — cópia recém-caída (<1 h) entra na execução seguinte e não conta. Três painéis novos no dashboard `hermes-lab`; a suíte cobra o textfile com as métricas, a série no Prometheus e as 4 regras carregadas. Provado com valor sintético: a regra entra em `pending` em 2 scrapes e volta a inativa ao restaurar — sem toast (o watcher só olha `firing`). Suíte: 207 → **212** |
| 2026-10-22 | **Fase 5 do eixo: banco de questões (provas e gabaritos)** | `tools/questoes.py` (host, stdlib + `sqlite3`) lê `concurso/<slug>/<ano>/{prova,gabarito}-<ano>` com `pdftotext` e grava `~/rag-state/questoes.db` (entra no backup). **Medido antes de desenhar:** as 7 provas (2020–2026) têm **50 questões, 1..50, sem buraco**; o marcador varia (`Questão 1 –` em 2020/2021, `Questão 1.` em 2022/2023/2024, `Questão 1` sozinho em 2025/2026) e a alternativa é `(A)` em 2020/2021/2025 e `a)` em 2022/2023/2024/2026. **Três armadilhas reais:** (a) a indentação da alternativa varia **dentro do mesmo ano** (2021 Q6 tem 13 espaços; com `^\s{0,8}` a questão vinha **sem alternativa** e o ano ainda fechava 50/50); (b) cabeçalho/rodapé e número de página caíam no meio do enunciado (`Colégio Tiradentes … Página 1`); (c) texto após a última alternativa (`Responda às questões 02 a 25…`) era colado na letra (E) — linha em branco fecha a questão. **Gabaritos:** 2020/2021/2024/2026/2027 são texto; 2022 é `.txt` digitado; **2023 e 2025 são imagem** → OCR (`tesseract 5.5.0` + `por`, instalado no host). A tabela de 2025 sai no `--psm 6` (`1 C 26 c`); a **grade** de 2023 só pelas **coordenadas** das células (`--psm 11 tsv`) — `--psm 6` devolve `D E A D B C…` embaralhado (0 pares). Resultado: **350 questões / 1744 alternativas / 400 respostas**, 2020–2026 `ok`, 2027 `sem_prova` (tem gabarito, não tem prova). Regra: ano que não fechar 50/50 fica `revisar` e `questoes conferir` **falha** — o importador **não inventa**. Cron `5,35` (fora do minuto do `rag-ingest`) e publicação de `referencias/estatisticas-questoes.md`, que o worker ingere → o chat responde contagem **com citação**. Suíte: 212 → **225** |
| 2026-10-22 | **Apostilas do curso (Azambuja) organizadas em `concurso/tiradentes-bm/apostilas/<matéria>/` e cobertura provada página a página** | as 5 apostilas estavam soltas na raiz do concurso. Estrutura: `portugues/`, `matematica/`, `redacao/`, `provas-anteriores/` (a "APOSTILA REVISÃO - MÉDIO CTBM 2026" é, no conteúdo, **apostila de provas 2017–2021** — nome enganoso mantido) e `orientacao/` (Guia de Normas, Canva). **Mover não reingere:** a chave do "já ingerido" é o `sha256` (dry-run: "0 seria(m) ingerido(s), 22 já ingerido(s)"); o que ficou morto foi a coluna `origem` do manifest, reapontada **pelo sha**. **Cobertura medida:** 680 páginas nos 5 PDFs, `metadata.page` 0..N-1 presente em todos (152/178/33/305/12) → **nenhuma página faltando**; ~94% do volume de texto integral. Perda localizada em **tabelas** que o Docling converteu em `<!-- image -->`: na Matemática, 2 páginas só com imagem e 13 com <60% do texto (pior: p.160, a tabela de ângulos com `a=e`, `c=g`). Comparar `pdftotext` com o markdown do Docling acusa buraco **falso** (extratores diferentes) — o sinal confiável é página ausente ou <35% do volume. Busca provada por embedding nas três matérias. Armadilha nova: regravar o manifest com `csv.DictWriter` troca LF por CRLF e quebra `grep ',ok$'` (o CI avisou). Suíte: 225 → **227** (origem existente + manifest em LF) |
| 2026-10-23 | **Complemento de texto para as tabelas que o Docling perdeu (6 arquivos, 25 páginas)** | a opção "reconverter com modo de tabela preciso" **não funciona**: medido na p.160 da Matemática, `table_mode=accurate` dá o mesmo do `fast` (127 chars, 6 s), `force_ocr` idem, os quatro `pdf_backend` idem e `text`/`html` também descartam. Causa: o Docling **lê** os 45 textos da página, mas o layout marca a área como `picture` e **39 textos são filhos dela** — o exportador markdown escreve `<!-- image -->` e não desce nos filhos. Solução: `tools/rag_complemento.py` compara página a página com a base e grava `complemento-<documento>.md` ao lado do PDF (texto do próprio PDF via `pdftotext`); o worker ingere como documento normal. **6 complementos / 25 páginas**: 15 na Matemática, 2 em Português, 1 na apostila de provas, **5 no edital 2027** (p.21 = conteúdo programático de Matemática, 2438 chars → 46 na base) e 1 em cada gabarito (2020 p.1 = a tabela de respostas inteira, 0 na base). Base: 22 → **28 documentos / 1.948 vetores**. Recuperação provada por embedding (`Ângulos Correspondentes`, `a=e` no top-3). Suíte: 227 → **230** (todo complemento do share está na base + canário da p.160 + worker instalado) |
| 2026-10-23 | **Credenciais do dashboard (9119) saem do compose para o `.env`** | o dono do lab perguntou a senha do painel: o comentário do compose mandava procurar em `.hermes-dashboard.env` — arquivo que **nunca existiu** (usuário/senha/secret estavam escritos no `docker-compose.yml`, versionado). Movidos para `HERMES_DASHBOARD_BASIC_AUTH_{USERNAME,PASSWORD,SECRET}` no `.env`, com `${VAR:?...}` no compose (falha cedo e com mensagem) e `.env.example` documentando; `docker compose up -d --no-deps hermes-dashboard` aplica — o sync copia o `.env` mas **não** aplica compose. Provado com `--force-recreate`: env do container == `.env`, compose sem literal, healthy, login 200, LAN 302; os outros 11 containers intocados. Descoberta: o login é **formulário** (`POST /auth/password-login`, provider `basic`), não HTTP Basic — `curl -u` devolve 401 em tudo (só `/api/health` e `/api/status` são abertos). Suíte: 230 → **231** (senha/secret do dashboard fora do `.env` = vazamento) |
| 2026-10-23 | **Espelho público sanitizado do lab (`projeto-davy-jones-hermes-public`)** | pedido do dono: cópia pública do privado sem informação sensível, no molde do `projeto-medusa-public`. O inventário mostrou o problema que decide o desenho: a **senha e o secret do dashboard estão no 1º commit** (`15feb19`, hardcoded no compose; só saíram para o `.env` em 2026-10-23, e são as credenciais em uso) — então o público **não pode herdar história**. Desenho: `ops/deploy/make-public-repo.ps1` extrai `git archive HEAD` (110 arquivos, 0,71 MB, só rastreados — o `.env` nunca entra e o próprio publicador fica de fora), aplica a tabela de redação (e-mail pessoal do dono, e-mail do 2º usuário de teste e o caminho da pasta do usuário no Windows → placeholders `@example.com` e `C:\Users\usuario`; IP e hostname ficam, como no medusa), **varre o resultado** (valores do `.env`, `.env`/`.db`/`.key`/`.pem`, `BEGIN … PRIVATE KEY`, endereço de e-mail público, `API_SERVER_KEY` literal — interpolação `${VAR:?...}` não é achado) e só então commita, com autor neutro. `-Push` cria o repo e publica via `GIT_ASKPASS`. Provado byte a byte: 14 arquivos diferem e **só** nas três substituições (BOM e LF preservados, PDF idêntico por sha256). Suíte: 231 → **235** (script + card + tabela + snapshot sem `git clone` + varredura). |
| 2026-10-22 | **Apostilas novas no share: Docling estourava o timeout e 4 documentos caíam em `_rejeitados/`** | o usuário adicionou 5 apostilas + 1 guia (178, 33, 305 e 12 páginas). Com `DOCLING_SERVE_MAX_SYNC_WAIT=600`, quatro falharam (`Gateway Timeout - Conversion is taking too long`) e o CI ficou vermelho no check do `rag-ingest --dry-run` (falha ativa = FAIL). **Medido:** 178 p = **1123 s**, 305 p = **1501 s**, 12 p escaneadas = 34 s → ~6 s/página (OCR em CPU, 8 threads; o Docling fica em 900% de CPU). Correção: limite **3600 s** no `docker-compose.yml` **+ `docker compose up -d docling`** (o sync não aplica compose) **+ `rag-ingest --retentar`** (a execução normal **pula** o que está em `falhou`). Resultado: **22 documentos na base, 0 falhas**. `_rejeitados/` limpo à mão — o worker **não** remove a cópia velha quando o arquivo entra depois, e o metric `hermes_rag_rejeitados_total` passaria a mentir. Lição de método: esperar dentro do SSH não serve para retentativa longa — rode como unidade (`systemd-run --uid=tlandskron`), senão ela morre junto com a sessão |

| 2026-10-23 | **Inventário de hardware do servidor físico (duas peças)** | pedido do dono: fabricante e modelo de **placa-mãe, CPU, GPU, cooler/watercooler, fonte, gabinete, rede, USB 1/2/3 e portas serial/VGA/HDMI/PS-2/som**, com o comando disparado **do PowerShell do Windows** e o arquivo **dentro do projeto**. Desenho: `tools/inventario_hardware.sh` (DMI/SMBIOS + `lspci -vmmnn` + `lsusb` + `/sys`) roda **no host** e imprime Markdown na saída padrão; `tools/inventario-proxmox.ps1` envia por **base64** (o `ssh` do PS 5.1 mangla aspas), executa com `sudo -n` quando não é root e grava `docs/architecture/INVENTARIO-HARDWARE-PROXMOX.md`. O coletor vai por **stdin** (`bash <<< "$src"`): **nada é gravado no host**; a saída volta em **base64** para o console não estragar travessão/acento. **Duas armadilhas de parsing corrigidas antes de entregar:** o `-nn` anexa `[1002]` ao nome do fabricante e `[73ff]` ao do modelo (o id vazava para o nome; agora `semid()`/`ultimo()` separam) e o `$(printf ...)` comia a nova linha e **fundia as linhas do USB** (virou `$'\n'`). **O que software não vê** — e o documento diz na cara em vez de inventar: modelo de cooler/watercooler, fonte e gabinete (DMI tipos 27/39/3 vêm vazios em placa de consumidor). **Privacidade:** série/UUID/asset tag mascarados no coletor **e** conferidos de novo no `.ps1` (recusa gravar); MAC não é coletado — o arquivo pode ir para o espelho público sem redação extra. Escopo: o `.221` só aceita `publickey,password` e a chave `pve-lab` atende `192.168.15.10`, que é **VM** — a mecânica foi validada ponta a ponta nela (DMI QEMU: `pc-q35-11.0`, RX 6600 em *passthrough*), e o **ferro** é preenchido quando o dono rodar (ou cadastrar a chave). Suíte: 235 → **243** |

Evolução da suíte: **36 → 51 → 84 → 88 → 99 → 103 → 124 → 129 → 139 → 151 → 159 → 165 → 166 → 176 → 191 → 194 → 200 → 204 → 206 → 207 → 212 → 225 → 227 → 230 → 231 → 235 → **243** checks. Hoje: `PASS=243 / FAIL=0 / WARN=0`.
## 2.2 O que está de pé e funcionando (verificado)

**Stack (12 containers, todos `up` e com healthcheck onde existe):**
`qdrant` · `ollama` · `docling` · `open-webui` · `nginx` · `searxng` · `prometheus` ·
`node-exporter` · `cadvisor` · `grafana` · `hermes-agent` · `hermes-dashboard`.

- **memória multiusuário**: `user_id = e-mail`; `X-Hermes-Session-Key` presente; **nenhuma**
  memória com `user_id = hermes-user`; sem `MEM0_USER_ID` fixo.
- **mem0 provider ativo**; patch de identidade aplicado (`__init__.py`, backup `.bak-labpatch-20261009`).
- **`tools.tool_search.enabled = off`**; conexão do OWUI = `http://hermes:8642/v1` + header, **sem nuvem**.
- **`hermes-agent`** com linha em `model` + `access_grant` (`user`+`*`).
- **RAG**: Docling `healthy` (CPU), `VECTOR_DB=qdrant`, prefixo `owui_*`, `bge-m3` (1024d),
  extração `docling` efetiva em `rag.*`; E2E devolveu *"vigência de 24 meses … multa de 10% … [1]"*.
- **TLS**: `:443` OWUI, `:3001` Grafana, `:80` → 301; OWUI `:3000` só no loopback; certificado
  autoassinado com SAN (IP + hostnames), válido até **2029-01-20**. Renovação em 1 comando
  (`tools/make_tls_cert.sh --force --reload`), métrica diária e alerta aos **30 dias**.
- **Higiene da memória**: `mem0-maintenance` (03:00) dedupa por hash e por cosseno ≥ 0.97, aplica
  teto de 2000/usuário e publica `hermes_mem0_*`; TTL existe e vem **desligado** (decisão do
  escritório). A suíte exige **zero duplicatas exatas**.
- **Restore provado em ambiente limpo**: `tools/drill_restore_clean.sh` sobe Qdrant + OWUI novos,
  restaura snapshots e `webui.db` e derruba tudo (11/11 PASS). Prova os dados, não o SO.
- **Monitoramento**: Prometheus com **4 alvos `up`**; Grafana `database: ok` via TLS; dashboards
  **"Hermes Lab — Host & Containers"** (11 painéis, 4 do CI) e **"Hermes Lab — Alertas"**;
  **9 regras** no grupo `lab` (inclui TLS e manutenção do mem0).
- **Backup**: artefato diário com compose renderizado + `project-config.tgz` + `.hermes` (sem caches)
  + `webui.db` (.backup) + snapshots de **todas** as coleções + manifest; retenção 7/8;
  **restore testado**; pull agendado no Windows.
- **CI (Fase 7)**: `hermes-ci` roda a suíte, publica 7 métricas `hermes_ci_*` (node-exporter
  textfile → Prometheus → Grafana), guarda `~/ci/last-run.json` + logs (retenção 30) e grava o
  **hash da suíte** executada; `ops/deploy/sync-to-host.ps1` faz o deploy conferindo o hash dos dois lados.
- **Firewall**: `ufw` + cadeia `DOCKER-USER` (6333/11434 fechadas para a LAN), persistido por
  `docker-firewall.service`.
- **Higiene**: imagens pinadas (suíte falha se voltar tag flutuante); modelos experimentais e
  estados abandonados removidos.

## 2.3 Verificações reutilizáveis (copiar e colar)

```bash
# suíte (Windows → host)                  powershell -File tests/run-tests.ps1
# CI na hora (host)                       ssh davy-jones-hermes '/usr/local/bin/hermes-ci --quiet'
# deploy (Windows → host + CI)            powershell -File ops\deploy\sync-to-host.ps1
# estado dos containers                   ssh davy-jones-hermes "docker ps --format 'table {{.Names}}\t{{.Status}}'"
# isolamento no dado                      curl -s localhost:6333/collections/mem0_memories/points/scroll -X POST -H 'Content-Type: application/json' -d '{"limit":20,"with_payload":true}' | jq '.result.points[].payload.user_id'
# mem0 no gateway                         docker exec hermes-agent hermes memory status
# higiene do mem0 (sem apagar)            ssh davy-jones-hermes 'mem0-maintenance --dry-run'
# restore em ambiente limpo               ssh davy-jones-hermes 'bash /home/tlandskron/hermes-architect/tools/drill_restore_clean.sh'
# renovar o TLS                           ssh davy-jones-hermes 'bash /home/tlandskron/hermes-architect/tools/make_tls_cert.sh --force --reload'
# provar um upgrade do Qdrant             bash tools/verify_qdrant_upgrade.sh --image qdrant/qdrant:v1.19.2 --via qdrant/qdrant:v1.16.3
# limpar base de teste do OWUI            docker exec open-webui python /tmp/cleanup.py --dry-run (ver tools/cleanup_owui_test_kb.py)
# últimos resultados do CI                cat ~/ci/last-run.json; grep -E '^  (FAIL|WARN)' ~/ci/last.log
```

## 2.4 Compartilhamento da pasta do projeto (Windows / SMB)

A pasta do repositório no Windows é compartilhada na LAN como **`\\B550M-AORUS-ELI\davy-jones-hermes`**,
com acesso **somente** ao usuário `tlandskron` (leitura + gravação):

- **share**: 1 única regra — `B550M-AORUS-ELI\tlandskron` = **Change**; cache offline **desligado**
  (`CachingMode=None`);
- **NTFS**: herança **removida**; apenas `tlandskron` e **SISTEMA** (Controle Total); owner =
  `tlandskron`; `Administradores`/`Usuários`/`Todos`/`Usuários Autenticados` **fora da ACL**;
- aplicado por `tools\share-davy-jones-hermes.ps1` (exige elevação) e verificado por
  `powershell -File tools\verify-share-davy-jones-hermes.ps1` (**PASS=16 / FAIL=0 / WARN=1**);
- **firewall SMB deixado fechado por decisão** → hoje o share **não** é alcançável de outra máquina;
  para expor, liberar `FPS-SMB-In-TCP` no perfil **Privado** (e logar do cliente como
  `B550M-AORUS-ELI\tlandskron`);
- **caveat**: um administrador do Windows **pode assumir a posse** da pasta (`take ownership`) — a ACL
  barra o acesso normal, não a recuperação administrativa. É limite do próprio Windows.

---

# PARTE 3 — O QUE FOI EXECUTADO COM PROBLEMAS (e como resolvemos)

> **A lição que atravessa quase todos:** os bugs que escaparam **verificavam a existência, não o
> efeito**. "O arquivo do cron existe" ≠ "o cron roda". "O JSON do dashboard está no disco" ≠
> "o Grafana carregou o dashboard". "A senha está no `.env`" ≠ "o login funciona".
> **Regra prática adotada:** toda verificação nova pergunta pelo **efeito** (a API respondeu?
> o evento disparou? o dado chegou ao destino?), nunca só pela presença do artefato.

## 3.1 Síntese (sintoma → causa → correção)

### A. Armadilhas do software (breaking changes e quirks)

| Sintoma | Causa raiz | Correção adotada |
|---|---|---|
| Gateway `unhealthy`, porta 8642 fechada | `hermes plugins install --yes-deps` sequestra o `sys.path` (PM) e sobe sem `aiohttp` | **Nunca usar `--yes-deps`**; `mv /opt/data/installs /opt/data/installs.disabled-<data>` |
| Chat "trava", Ollama gerando sem parar | `tools.tool_search` em `auto` → tools *deferred* atrás da ponte; `qwen3:4b` não monta `calls` | `tools.tool_search.enabled: "off"` (`defer: []` **não** resolve) |
| Extração de fatos do mem0 devolvia `results: []` silenciosamente | `qwen3` gasta `max_tokens` pensando; mem0 pede JSON **sem `think=false`** | criado `qwen3:8b-extract` (template sem thinking) em `mem0.json` |
| `think:false` / `/no_think` "não funcionam" | Ollama 0.40.2 ignora o `TEMPLATE` do Modelfile (`/api/show` devolve o do registry) | não insistir: variante de modelo é o caminho |
| `mem0.search()` quebrava com `user_id` top-level | `mem0ai>=2` exige `filters={"user_id": …}` | adaptado o código de consulta |
| Usuário comum não via o modelo | duas coisas: linha em `model` **e** grant — com `principal_id='*'`, **não** `'anyone'` | `('model','hermes-agent','user','*','read')`; `MODELS_CACHE_TTL` ~1 s |
| Upload de documento "sumia" | processamento **assíncrono** (`status: pending`) | esperar `completed` antes de anexar/consultar |
| Falha de conversão deixava **linha órfã em `file`** (17 arquivos p/ 16 na base) | o upload do OWUI **aceita** o PDF corrompido; só o Docling falha depois | `owui_upload.py` **descarta** o arquivo (`DELETE /files/{id}`) quando `status=failed`/`file/add` falha; teste do corrompido confere `files` inalterado |
| `manifest.csv` "com cabeçalho inesperado" na suíte | o `csv.DictWriter` do Python escreve **CRLF** por default, mesmo no Linux | `lineterminator='\n'` na escrita; leitura com `utf-8-sig` (tolera BOM de editor) e checks com `tr -d '\r'` |
| Coleção `owui_<uuid>` não existia | multitenancy mode (default) usa coleções **fixas** + `tenant_id` | usar `owui_knowledge`/`owui_files` |
| Trocar env de RAG "não pegava" | `rag.*` são **PersistentConfig** (DB vence o env após o 1º boot) | `tools/set_owui_rag_config.py` + restart |
| Docling não subia: `RapidOCR artifacts not found` | `DOCLING_SERVE_ARTIFACTS_PATH` não baixa modelos | prefetch com `docling-tools models download` + `chown 1001:0` no volume |
| `403 "A human session is required."` (OWUI 0.12) | rota de conta passou a exigir JWT de **sessão** (`typ=session`); API key não vale | smoke assina JWT HS256 com `WEBUI_SECRET_KEY` (`/proc/1/environ`) + `session_stamp` |
| `SystemExit: WEBUI_SECRET_KEY is not set` | `docker exec` não herda a env gerada no start | ler de `/proc/1/environ` |
| `scp` recusava sobrescrever `searxng/settings.yml` | container toma posse do diretório (uid **977**) | copiar via `/tmp` + `sudo install` (o `sync-to-host.ps1` já faz) |
| Comandos morriam com quoting quebrado | **PowerShell 5.1 mangla aspas duplas** no `ssh` | enviar por **base64**; `python -c '…'` só com aspas simples |
| `Qdrant client 1.18 × server 1.15.2` (aviso) | diferença > 1 minor | **resolvido em 2026-10-20**: servidor subiu para 1.19.2 (cadeia 1.15.2 → 1.16.3 → 1.19.2, provada em cópia do volume) |

### B. Verificações fracas e suposições erradas (bugs de processo)

| Sintoma | Causa raiz | Correção adotada + testa em |
|---|---|---|
| **Grafana respondia `/api/health` ok, mas o dashboard não existia** | `monitoring/` estava `700` (umask do host) e o Grafana roda como **uid 472** → `failed to walk provisioned dashboards: permission denied`; o check antigo só olhava o JSON no disco | `chmod -R a+rX monitoring` (o sync força) + checks que **perguntam à API do Grafana** |
| **Senha admin do Grafana (a documentada) não entrava** | `GF_SECURITY_ADMIN_PASSWORD` só vale na **1ª criação do admin** no volume; o `.env` era ignorado depois | `grafana cli admin reset-admin-password` + restart; verificado por pbkdf2 **e** `GET /api/user`=200 (agora é check) |
| **Backup diário e CI nunca rodaram sozinhos** | o pacote **`cron` não estava instalado** (`dpkg` = `un`); a suíte checava o **arquivo** `/etc/cron.d/*`, não o daemon | `apt-get install -y cron` + `systemctl enable --now cron`; suíte checa `is-active`/`is-enabled`; provado disparando os dois |
| Suíte podia ficar **travada em vermelho para sempre** | o estado do CI é auto-referente: cada run verde reportaria o vermelho do anterior (`FAIL`) | criado `warn()`: **aviso não derruba** o CI; só fato estático é `FAIL` |
| Check do `bge-m3` dava falso negativo | timeout de 30 s; o Ollama **serializa** modelos e o *swap* de um `qwen3` residente mediu **63–90 s** | `--max-time 120` + retentativa; conferir `docker exec ollama ollama ps` |
| Check do Prometheus oscilava | comparava o **valor** recém-publicado (o scrape ainda não tinha lido) | invariante correto = a **série existir** (textfile → node-exporter → Prometheus) |
| `~/ci/last.log` apontava para o nada | symlink criado com o `basename` (log vive em `logs/`) | `ln -sfn "logs/$(basename …)"` |
| Bloqueio de login do Grafana "impossível de sair" | **5 logins errados** gravam em `login_attempt` e o bloqueio **sobrevive a restart** | parar o container, `delete from login_attempt`, subir; na suíte, **1 tentativa por execução** |
| Grafana em **crash-loop** (`unable to open database file (14)`) | `docker cp` de volta no `grafana.db` deixa o arquivo com o uid do **host** (1000) | sempre `chown 472:472` + `chmod 640` (ou usar container auxiliar com o volume) |
| Backup saía com erro de permissão / ~150 MB | `.hermes` tem arquivos de **root** e caches | `sudo tar` + excluir caches; e `docker exec -i` para heredoc no sqlite |
| "Fechei o firewall" e nada mudou | **o Docker ignora o ufw** (portas entram por `FORWARD`/`DOCKER-USER`) | regras em `DOCKER-USER` + `docker-firewall.service` (recriado a cada restart) |
| Firewall parecia não funcionar no teste | `curl` do host para o próprio IP passa por `OUTPUT` e **mente** | validar **de outra máquina** |
| `README`/docs diziam "cron diário" sem nunca ter rodado | confundimos "instalar a entrada" com "agendar de verdade" | **prova de disparo** (agendar a cada minuto → ver o evento → restaurar o horário) |
| Prova de disparo "não disparou nada" e o cron parecia quebrado | `sed 's|^\*/15 |* * * * * |'` troca **só o primeiro campo**: a linha ficou com **9 campos** (`* * * * * * * * * tlandskron …`) e o cron **ignora em silêncio** (nem erro no log) | para provar, troque a **linha inteira** (`sed 's|^\*/15 .*|* * * * * tlandskron /usr/local/bin/rag-ingest|'`); confira com `grep` antes de esperar |
| Gabarito 2022 digitado (`.txt`, 239 bytes) acusava "escaneado? OCR falhou?" | o aviso olhava só `chars < 200`, sem o **tipo** do arquivo: 190 chars de um `.txt` **é** o conteúdo inteiro | `aviso_extracao(sufixo, chars, tamanho)`: PDF avisa com < 200 chars; `.txt` só se extrair menos da metade dos bytes; a suíte testa os três casos |
| **Queda de energia** deixou 11 containers de volta e o **prometheus** `Exited (255)` | `restart: unless-stopped` não garante retomada quando o daemon encontra o estado "rodando" sem processo; ninguém notou por 4 h | `docker compose up -d prometheus`; a suíte pega (container `exited`) e o watcher agora avisa se o Prometheus não responde. **Todo reboot é motivo para rodar a suíte** |
| Horários do lab **3 h adiantados** ("caí às 21:00, o log diz 01:09") | host em **`Etc/UTC`** desde a instalação, sem `TZ` no compose e sem `/etc/timezone`: o cron usa a hora local, então o backup "das 03:30" rodava à meia-noite de Brasília | `sudo timedatectl set-timezone America/Sao_Paulo` (persistente, vale no próximo boot; o NTP já estava ok) + worker/logs gravando hora **local com offset**; a suíte falha se o fuso voltar para UTC |
| **Janela do console abrindo a cada 30 min** e engolindo teclas | a tarefa "Hermes Lab Alerts" (`InteractiveToken`) chamava `powershell.exe` direto: console abre ~1 s (até ~7 s ao notificar) e rouba o foco | `ops/windows/run-hidden.vbs` via `wscript.exe` (`Run cmd, 0, False`) nas **duas** tarefas, reaplicado pelo `sync-to-host.ps1`; provado com `MainWindowHandle=0`. `-WindowStyle Hidden` não bastava |
| Toast aparecia como **"Windows PowerShell"** | sem AUMID próprio, o Windows usa o do processo | `HKCU\SOFTWARE\Classes\AppUserModelId\Hermes.Lab.Alerts` (`DisplayName = Hermes Lab`) + `CreateToastNotifier` com esse id; a suíte cobra os marcadores |
| Métrica do RAG "verde" com o worker parado | o Prometheus mantém o último valor da série e `absent()` só cobre a série **sumir**, não "parou de atualizar" | alerta por **idade** (`time() - hermes_rag_ultima_execucao_timestamp_seconds > 2h`) **e** `absent()`; um gauge verde nunca prova que o cron rodou |
| `watch-alerts.ps1` nunca avisava host fora do ar | `$ErrorActionPreference='Stop'` + stderr do `ssh` = `NativeCommandError` **antes** do `if (-not $raw)`; e ali só logava | `'Continue'` em volta do comando nativo + checar `$LASTEXITCODE` + o branch de erro **notifica** (dedup 6 h). Provado com `-Remote 192.0.2.1` |
| Editar um documento **duplicava** na base | o mesmo caminho com SHA novo era "novo documento"; a antiga ficava marcada `substituido` só no manifest e continuava citável | substituição passou a ser o padrão (sobe a nova → remove a antiga; falha na remoção não perde a boa). `--substituir` = no-op |

### C. Limites de hardware (RX 6600, 8 GB)

| Sintoma | Causa raiz | Correção adotada |
|---|---|---|
| Modelo recusado no boot do Hermes (piso 64k) | `qwen3:8b` + 64K não cabe: llama.cpp reduz para **40.960** → reprovado | **`qwen3:4b-64k`** (65.536 reais; com KV q4_0: 5,6 GB, **100% GPU**, ~62 tok/s) |
| `qwen2.5` reprovados | contexto **nativo** 32.768 (não é VRAM) | só a família `qwen3` serve a 64K aqui |
| Latência alta (91 s/turno) | *thinking* do qwen3 + system prompt do Hermes de **~15,5k tokens** (~28 s antes do 1º token) | aceitar o trade-off; enxugar toolset economiza ~21 s (-23%) |
| `bge-m3` lento quando a GPU está ocupada | serialização de modelos no Ollama | timeout folgado + retentativa (ver Parte 3.B) |
| Prova responde "não encontrei" e um chunk tem 13 chars | `enable_markdown_header_text_splitter=true` fatia o markdown do Docling em **todo `##`** (cada questão vira cabeçalho) | desligado no spike; `CHUNK_SIZE=1200`, `CHUNK_OVERLAP=200`, `TOP_K=6` (config global do OWUI) |
| RAG de estudo leva 432-588 s por pergunta | gateway injeta **21,6k tokens** (AGENTS.md 36 KB + ferramentas) e o OWUI dispara **5 chamadas** (resposta, título, tags, follow-up, query-gen) | medido no spike: Ollama direto com os mesmos chunks = **12-34 s** (decisão pendente, §18 do desenho) |

## 3.2 O que **não** fazer (lista curta, aprendida na dor)

1. **Não** rodar `hermes plugins install --yes-deps` (derruba o gateway).
2. **Não** criar `mem0_memories` à mão (dims erradas quebram tudo) nem definir `MEM0_USER_ID` fixo.
3. **Não** confiar em `:main`/`:rocm`/`:latest` (pinagem é invariante testado).
4. **Não** verificar artefato em vez de efeito (Parte 3, cabeçalho).
5. **Não** generalizar permissão de segredo: `chmod -R a+rX` vale para `monitoring/`, **nunca** para `nginx/certs` (`.key`).
6. **Não** fazer `docker cp` de volta num banco do container sem acertar o **dono** (uid do processo).
7. **Não** embutir aspas duplas em comando `ssh` vindo do PowerShell (usar base64).
8. **Não** apagar/limpar nada sem backup e sem rodar a suíte antes/depois.

## 3.3 Riscos e pendências abertos

| Item | Situação |
|---|---|
| **Citação verificável** (o texto citado existe no chunk?) | **Parcial** — o smoke exige `[1]` e confere que todo **número** afirmado existe nas fontes recuperadas (teste negativo validado). Em produção ainda não há filtro: o OWUI não valida a citação sozinho |
| **Retenção/expurgo (LGPD/sigilo)** | **Pendente (política)** — o TTL do mem0 está implementado e **desligado** (`MEM0_RETENTION_DAYS`); falta o prazo de guarda do escritório. `DELETE /api/v1/files/{id}` já limpa vetores |
| **Backup off-site** | **Parcial** — `pull-backups.ps1` confere **SHA-256** contra o host e aceita `-ExtraDest` (HD externo); o destino padrão (`\\localhost`) é a mesma máquina |
| **Auditoria leve** (quem perguntou o quê) | **Pendente** |
| Patch do plugin mem0 | some se rodar `hermes plugins update mem0` → **reaplicar** (`__init__.py:237`) |
| **RAG por ano/número de questão** | **Limite medido (2026-10-21)** — com 16 documentos, "resposta da Q10 do gabarito de 2024" não trouxe o gabarito de 2024: o ano vive no **nome do arquivo** (metadado), não no texto, e `top_k=8` entre 423 vetores dilui. Consulta por número/ano é do **banco de questões** (decisão), não do RAG |
| Gabarito 2022 (só imagem) | **Parcial** — OCR trouxe a tabela pela metade (**780 chars**, 1 chunk) contra 7,2k do 2023. Vale redigitar a tabela ou re-escanear |
| Publicar Grafana em `/grafana` no `:443` | Opcional (hoje é porta dedicada com TLS) |
| Auditoria leve (quem perguntou o quê) | **Pendente** |

## 3.4 Onde estão os segredos e os endereços (não duplicar valores aqui)

| O quê | Onde |
|---|---|
| Senha admin do Grafana | host `/home/tlandskron/hermes-architect/.env` (`GRAFANA_ADMIN_PASSWORD`) |
| `API_SERVER_KEY` do gateway | `hermes-data/.env` / docs das fases |
| `WEBUI_SECRET_KEY` | gerado no start; ler de `/proc/1/environ` |
| Config do mem0 | `/home/tlandskron/.hermes/mem0.json` (+ `hermes-data/mem0.json` no repo) |
| Config do Hermes | `/home/tlandskron/.hermes/config.yaml` |
| Chave TLS privada | `nginx/certs/server.key` (host + repo — **não** abrir permissão) |

**Endereços:** Open WebUI `https://192.168.15.231` · Grafana `https://192.168.15.231:3001`
(admin / senha do `.env`) · `:80` → HTTPS · OWUI `:3000` **só loopback**.
Se o host não responder, ele provavelmente está **desligado** (não é IP novo).

---

## Anexo — Checklist a cada ciclo (do mapa mental, aplicado)

- [ ] Escrevi um teste que **falha primeiro**?
- [ ] O bug corrigido virou **check na suíte** (+ registro neste arquivo)?
- [ ] Rodei o **oráculo** antes e depois (e o resultado é do **efeito**, não da existência)?
- [ ] Persiste ao **restart** (container/cron/systemd habilitados)?
- [ ] **Backup** do estado novo feito e puxado para fora do host?
- [ ] O escritório consegue ver o estado **sem SSH** (Grafana)?
- [ ] Documentei em `AGENTS.md`/runbook/`ai-memory.md` e mantive o **contexto enxuto**?
