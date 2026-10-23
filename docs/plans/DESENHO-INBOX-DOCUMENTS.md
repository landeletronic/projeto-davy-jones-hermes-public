# Desenho — `documents/` (inbox controlado) e ingestão na RAG

> **Status: desenho fechado; árvore criada; share SMB provado; Fase 0 (spike) concluída.**
> Decisões de 2026-10-21 aplicadas: **uma árvore só, no host, compartilhada por SMB**;
> uma base no OWUI **por concurso** (hoje `Tiradentes BM`; depois magistratura, HCPA…);
> pasta do concurso `tiradentes-bm`.
> **Eixo:** estudos — Colégio Tiradentes (BM/RS), ingresso **2028**.
> **Resultado do spike (medido):** ingestão ~2,3 s/página (Docling em CPU), chat de estudo em
> **~29 s** por pergunta (conexão direta no Ollama), com citação e lastro — ver §18.

## 1. O problema

Hoje o RAG é alimentado pelo botão de upload da UI do OWUI. Funciona, mas:

- não há **registro** do que já entrou (e o OWUI 0.12.3 deixa linha órfã ao excluir);
- o arquivo perde a **taxonomia** (vira "edital (1).pdf");
- não dá para **reprocessar** tudo quando o modelo de embedding/extrator mudar;
- ninguém sabe **onde está** o PDF original depois de subir.

O objetivo é um **inbox controlado**: uma pasta centralizada no servidor, uma taxonomia que faz
sentido para cada concurso, e um processo que ingere **uma vez**, registra e sabe repetir.

## 2. Decisão estrutural: uma árvore só, no host

| Onde | Papel |
|---|---|
| **Host (`/home/usuario/documents`)** | **fonte única** — os arquivos vivem aqui, são processados aqui e entram no backup daqui |
| **Windows / outros PCs** | acessam a mesma pasta por **SMB** (`\\192.168.15.231\documentos`), como uma unidade de rede |
| **Repositório** | **nada** de documentos: a árvore sincronizada é código (check de 1 MB) e vai ao GitHub |

Por que centralizar no servidor:

- **uma cópia** de cada arquivo (nada de duplicar PC ↔ servidor e sincronizar conflito);
- **backup único** e já provado (o diário das 03:30 passa a incluir essa pasta);
- o RAG e os arquivos ficam **na mesma máquina** — o worker lê por caminho, sem cópia;
- o PC do usuário pode estar desligado: o lab continua servindo e processando;
- vários usuários (você, depois outras pessoas) gravam na mesma árvore, com login próprio.

**Por que não no repositório:** prova de concurso é binário de alguns MB — derruba o check de
1 MB, vai para o GitHub privado sem necessidade e faz o `sync-to-host.ps1` copiar 100 MB a cada
deploy.

## 3. A árvore

```
/home/usuario/documents/               ← RAIZ DO SHARE "documentos"
├── LEIA-ME.txt                           ← as regras desta pasta (este resumo, em 10 linhas)
├── concurso/
│   └── tiradentes-bm/
│       ├── 2027/                         ← ano do EDITAL (prova em 18/10/2026)
│       │   ├── edital/
│       │   └── prova_gabarito/
│       ├── 2028/                         ← alvo (edital ainda não publicado)
│       │   ├── edital/
│       │   └── prova_gabarito/
│       └── apostilas/                    ← material de curso preparatório (NÃO é prova da banca)
│           ├── portugues/
│           ├── matematica/
│           ├── redacao/
│           ├── provas-anteriores/        ← compilado de provas antigas (2017–2021)
│           └── orientacao/               ← normas e orientação do curso (para a família)
├── referencias/                          ← material de apoio seu (resumos, mapas)
├── incoming/                             ← "não sei onde isso vai ainda"
├── _rejeitados/                          ← O PROCESSO ESCREVE: o que falhou + <arquivo>.motivo.txt
└── _relatorio/                           ← O PROCESSO ESCREVE: INGESTAO.md (o que entrou, quando)
```

Fora do share, onde o usuário não mexe:

```
/home/usuario/rag-state/
├── manifest.csv      ← o que já foi ingerido (sha256, base, file_id, data)
└── ingest.log        ← log técnico de cada execução
```

**Convenção que o worker usa:** pasta ou arquivo começando com `_` **não é ingerido**
(`_rejeitados`, `_relatorio`), e `LEIA-ME.txt` é ignorado. Tudo o mais em `concurso/`,
`referencias/` e `incoming/` é candidato.

## 4. A árvore, pasta por pasta

| Pasta | Para que serve | Quem escreve |
|---|---|---|
| `concurso\<concurso>\<ano>\edital\` | edital e retificações daquele ano | **usuário** |
| `concurso\<concurso>\<ano>\prova_gabarito\` | prova + gabarito daquele ano, lado a lado | **usuário** |
| `concurso\<concurso>\apostilas\<matéria>\` | apostila de curso preparatório (não é documento da banca) | **usuário** |
| `...\complemento-<documento>.md` | **gerado** por `tools/rag_complemento.py`: texto das páginas que o Docling perdeu (tabela virou figura) | **processo** |
| `referencias\` | resumos, mapas, material de apoio | usuário |
| `incoming\` | triagem: o que ainda não tem lugar | usuário |
| `_rejeitados\` | arquivo que não pôde ser lido + motivo | **processo** |
| `_relatorio\` | `INGESTAO.md`: última execução, pendentes, falhas | **processo** |

**Apostila ≠ prova.** O material de curso (`apostilas/`) entra na **mesma** base do concurso,
porque serve de apoio ao estudo — mas o **banco de questões** só lê
`<ano>/prova_gabarito/{prova,gabarito}-<ano>`; apostila nunca vira questão. Dentro de
`apostilas/` a divisão é por matéria (`portugues`, `matematica`, `redacao`), mais
`provas-anteriores` (compilados de provas de anos que não vieram soltos) e `orientacao`
(normas do curso). Apostila nova: criar a pasta da matéria se ainda não existir.

**Convenção do ano:** o ano é o do **edital/processo**, não o da data da prova.
O edital **2027** teve prova em 18/10/2026 → vai em `2027\`. O alvo é `2028\`.

**Outros concursos** (magistratura, HCPA…) ganham pasta irmã em `concurso/` e **base própria** no
OWUI. Nada muda no processo.

## 5. Convenção de nome (a "etiqueta" que vira citação)

```
<tipo>-<ano>[-<disciplina>][-<detalhe>].pdf     ← no share
<concurso>-<ano>-<resto>.pdf                    ← nome achatado dentro da base
```

| Tipo | No share | Vira citação no chat como |
|---|---|---|
| `edital` | `concurso\tiradentes-bm\2027\edital\edital-2027.pdf` | `tiradentes-bm-2027-edital.pdf` |
| `edital` (retificação) | `...\edital\edital-2027-retificacao-01.pdf` | `tiradentes-bm-2027-edital-retificacao-01.pdf` |
| `prova` | `...\2027\prova_gabarito\prova-2027-matematica.pdf` | `tiradentes-bm-2027-prova-matematica.pdf` |
| `gabarito` | `...\2027\prova_gabarito\gabarito-2027-matematica.pdf` | `tiradentes-bm-2027-gabarito-matematica.pdf` |
| `resumo` | `referencias\resumo-2027-portugues.pdf` | `tiradentes-bm-referencias-2027-resumo-portugues.pdf` |
| triagem | `incoming\anotacoes.pdf` | `tiradentes-bm-incoming-anotacoes.pdf` |

O nome na base é **achatado** (sem pasta, sem acento, sem espaço): é o que o OWUI mostra na
citação e cabe numa citação só. O caminho relativo **não se perde** — ele é a coluna `origem`
do `manifest.csv` (§7), que é como você acha o arquivo no Explorer.

Regras: minúsculas, sem acento, sem espaço (`-` no lugar), sempre o **ano de 4 dígitos**.
Nome fora do padrão **não é rejeitado** — entra como está; a única consequência é uma citação
menos legível. Rejeição é só para falha técnica: arquivo corrompido, formato não suportado,
texto ilegível.

## 6. O caminho de um arquivo (do drop à citação)

1. Você copia `prova-2027-matematica.pdf` para `T:\concurso\tiradentes-bm\2027\prova_gabarito\`
   (T: = o share `documentos`).
2. O worker roda **a cada 15 min** (cron no host) — ou na hora, com `rag-ingest`.
3. Ele lista os candidatos e **ignora** o que começou a ser copiado agora: só processa arquivo
   com tamanho e data **estáveis há 30 s** (cópia grande não é lida pela metade).
4. Calcula o **SHA-256** e compara com o `manifest.csv` (fora do share).
5. Se é novo, chama o upload dentro do container:
   `docker exec open-webui python /tmp/owui_upload.py --path /documents/<caminho> --name <achatado> --kb "<concurso>"`
   — a pasta entra no container como **somente leitura** (`/documents:ro`).
6. Dentro do container, o `owui_upload.py` abre uma **sessão JWT** assinada com a
   `WEBUI_SECRET_KEY` do processo (o mesmo mecanismo do `tests/smoke_rag.py`), sobe o arquivo com
   `process=true` e espera Docling + `bge-m3` terminarem.
7. O host confere o resultado (arquivo virou pontos no Qdrant? a linha `knowledge_file` existe?),
   grava a linha no `manifest.csv` e no `ingest.log`.
8. Falhou? O arquivo é **copiado** para `_rejeitados/` com `<arquivo>.motivo.txt` (as 3 últimas
   linhas do erro) — você vê no Explorer e corrige.
9. No chat você escolhe a base **`Tiradentes BM`**; a resposta cita o nome achatado (§5), então
   fica claro se veio do edital ou da prova.

## 7. O `manifest.csv` (a memória do processo)

Uma linha por documento ingerido — é o que impede duplicar e o que permite reprocessar.

| Coluna | Exemplo | Serve para |
|---|---|---|
| `sha256` | `9f2c…` | identidade do conteúdo (não do nome) |
| `bytes` | `1842113` | tamanho |
| `origem` | `concurso/tiradentes-bm/2027/prova_gabarito/prova-2027-matematica.pdf` | caminho relativo no share (é como você acha o arquivo) |
| `tipo` | `prova` | derivado do nome |
| `ano` | `2027` | derivado do caminho |
| `knowledge_id` | `b1d0…` | base no OWUI |
| `file_id` | `c7a2…` | arquivo no OWUI (para remover/substituir) |
| `ingerido_em` | `2026-11-02T14:08:11Z` | quando |
| `duracao_s` | `41` | custo de processamento (planejar lote) |
| `estado` | `ok` / `substituido` / `removido` / `falhou` | histórico sem apagar linha |

## 8. Os três casos chatos (decididos agora, para não improvisar depois)

| Caso | Comportamento |
|---|---|
| **Mesmo arquivo de novo** (mesmo SHA-256) | não sobe; só registra "já ingerido" no log |
| **Mesmo nome, conteúdo novo** (SHA-256 diferente) | ingere a versão nova e a antiga **sai da base** (marcada `substituido`; §20.4) — atualização do mesmo documento, não documento novo |
| **Apagou do share** | **nada** é apagado da base automaticamente. Remoção é explícita: `rag-ingest --remover <sha256>` |

Regra de ouro: **o processo nunca apaga conhecimento sozinho.** Apagar é decisão sua.

O que já falhou fica em `estado=falhou` e **não** é retentado a cada execução (evita loop com
PDF corrompido): depois de corrigir o arquivo, `rag-ingest --retentar` tenta de novo.

## 9. A base no OWUI

- **Uma base por concurso**: `Tiradentes BM` hoje; `Magistratura RS`, `HCPA` depois. O worker
  procura pelo nome e só cria se não existir (idempotente).
- Não uma por ano: perguntas do tipo "compare o que caiu em 2026 e 2027" precisam das provas juntas.
- O **nome do arquivo dentro da base** é o nome achatado do §5 (`tiradentes-bm-2027-prova.pdf`) —
  é isso que aparece na citação; o caminho relativo fica no manifest.
- `access_control` da base tem de incluir a sua conta (senão o chat não a enxerga). O worker
  ajusta isso na criação.
- O chat **não** usa a base por padrão: você escolhe a base ao abrir a conversa de estudo (evita
  o modelo citar edital quando a pergunta é de matemática).

## 10. O que entra × o que não entra

| Entra | Por quê |
|---|---|
| edital + retificações | regras, conteúdo programático, prazos |
| provas anteriores (2017 → 2027) | treino, calibragem, padrão da banca |
| gabaritos | correção e conferência da prova |
| resumos seus | reforço, linguagem sua |

| **Não** entra | Por quê |
|---|---|
| PDF escaneado ilegível (OCR erra > 20%) | a citação vira ruído; refazer o scan ou digitar o trecho |
| livro/apostila de terceiros | direito autoral + ruído (não é a banca) |
| dados pessoais (documentos seus) | não têm relação com o conteúdo; ficam fora do RAG |
| prova de outro concurso sem etiqueta | confunde o modelo; se entrar, vai em `referencias/` |

**Escaneado:** o Docling roda em CPU e faz OCR, mas devagar (dezenas de segundos por página).
Medir no spike (§13, Fase 0). Se um dia entrar material com figura/tabela essencial, a decisão já
tomada é: **modelo de visão na ingestão em lote, nunca no chat**.

## 11. Compartilhamento SMB (como o Windows enxerga)

**Serviço:** Samba no host (`smbd`), instalado por `apt` e **config versionada** em `ops/samba/`
(como o `cron` e o `ufw` já são). Não é container: é serviço de host, ao lado do `cron`.

`/etc/samba/smb.conf` (esboço):

```ini
[global]
   server string = hermes-lab documentos
   workgroup = WORKGROUP
   server min protocol = SMB2_10      # nunca SMB1
   hosts allow = 192.168.15.0/24      # só a LAN
   hosts deny = 0.0.0.0/0
   map to guest = never               # sem acesso anônimo

[documentos]
   path = /home/usuario/documents
   valid users = usuario
   read only = no
   create mask = 0644
   directory mask = 0755
```

- **Firewall:** `ufw allow from 192.168.15.0/24 to any port 445 proto tcp` — 445 **só da LAN**.
  Isso muda a política de INPUT do lab (hoje 22/80/443/3001/9119): passa a ter 6 portas, e a
  suíte passa a exigir a regra **restrita à sub-rede** (não `Anywhere`).
- **No Windows, uma vez só:** Explorer → *Mapear unidade de rede* → `\\192.168.15.231\documentos`
  → marcar *Conectar usando credenciais diferentes* → usuário `usuario` + a senha SMB.
  Também funciona por `net use T: \\192.168.15.231\documentos /user:usuario`.
- **Senha SMB é separada da senha do Linux** (`smbpasswd`), e fica só no host (nunca no repo).
- **Mais usuários depois:** cada pessoa ganha conta SMB própria; o share continua um só (mesma
  árvore), e a autoria fica no dono do arquivo.

## 12. Segurança

- **SMB:** usuário nominal, senha própria, SMB ≥ 2.1, sem guest, `hosts allow` na sub-rede **e**
  ufw restrito (duas camadas). O share aponta só para `~/documents`, **nunca** para o home.
- **Nenhuma API key nova:** o upload assina um JWT de sessão dentro do container, lendo a
  `WEBUI_SECRET_KEY` de `/proc/1/environ` — exatamente o que `tests/smoke_rag.py` já faz desde a
  0.12.3 (API key **não** vale como sessão humana).
- O container recebe a pasta como **`:ro`** — o RAG lê, não escreve.
- O worker **não** lê o `.env`, **não** usa o `docker.sock` e **não** tem o repo montado.
- `_rejeitados/` e `_relatorio/` são escritos pelo host (usuário `usuario`), não pelo container.

## 13. Fases (cada uma com prova)

| Fase | O que faz | Prova de que funcionou |
|---|---|---|
| **0 — spike** (1 tarde) | 3 arquivos reais (edital, prova, gabarito) ingeridos **à mão** | pergunta cuja resposta só existe na prova → citação `[1]` com o caminho certo; tempo por página medido |
| **1 — share** | Samba + árvore + `LEIA-ME.txt` + mapeamento no Windows | criar um arquivo pelo Explorer e vê-lo no host; portas 445 fechadas fora da LAN |
| **2 — worker manual** | `rag-ingest` + manifest + `_rejeitados` | 2ª execução não duplica; arquivo corrompido aparece em `_rejeitados` com motivo |
| **3 — agendado** | cron 15 min + `_relatorio/INGESTAO.md` | drop no Explorer → no chat em ≤ 15 min, sem tocar em nada |
| **4 — operação** | métrica `hermes_rag_*`, alerta "pendente > 24 h" | Prometheus mostra pendentes; alerta dispara em teste |

Cada fase entra na suíte (regra do projeto: invariante novo = check novo). A Fase 1 já implica
checks: `smbd` ativo/habilitado, share existe e aponta para `~/documents`, 445 restrito à LAN,
config versionada em `ops/samba/`.

## 14. Riscos e limites conhecidos

| Risco | Mitigação |
|---|---|
| Cópia grande lida pela metade | só processa arquivo estável há 30 s (§6.3) |
| Docling lento em prova escaneada | medir na Fase 0; lote noturno; OCR só onde precisa |
| OWUI 0.12.3 deixa `knowledge_file` órfã | o worker confere a linha e limpa (`tools/cleanup_owui_leftovers.py` já existe) |
| Citação sem lastro (afirmação sem número) | o smoke verifica números; no uso diário, sempre abrir a fonte citada |
| Base grande dilui a busca | uma base por concurso; não jogar "tudo" dentro |
| Nome fora do padrão | não bloqueia; só piora a citação |
| Samba como serviço novo | config versionada + ufw restrito + suíte cobrando; desligar é `systemctl stop smbd` |
| Senha SMB esquecida | `sudo smbpasswd -a usuario` no host (documentado no card do serviço) |

## 15. Alternativas descartadas

| Alternativa | Por que não |
|---|---|
| documentos no repositório | quebra o check de 1 MB, vai ao GitHub e o deploy copiaria 100 MB |
| árvore no Windows + push por `scp` | duas cópias para sincronizar e conflito quando o PC está desligado; centralizar no host é mais simples |
| montar o share do Windows no host (CIFS) | exige credencial em arquivo no host e depende de o PC estar ligado |
| Samba em container | mais um serviço para pinar/atualizar no compose e um 13º container na suíte; Samba de host é o mesmo padrão do `cron` |
| subir tudo pela UI do OWUI | sem manifest, sem versão, sem reprocessar, nome vira "edital (1).pdf" |
| um banco de questões agora | o RAG responde "o que diz o edital"; contagem/estatística é do banco |

**Fronteira com o banco de questões (decisão anterior):** `documents/` alimenta a **leitura**
(RAG). O banco de questões (SQLite + verificação com `sympy`) é construído *a partir* desses
arquivos e serve para **treinar e corrigir**. Não peça ao RAG "quantas questões de matemática
caíram em 2025" — isso é consulta ao banco.

## 16. Decisões tomadas

| # | Decisão | Data |
|---|---|---|
| 1 | Árvore **no host**, compartilhada por SMB; nada de documentos no repo | 2026-10-21 |
| 2 | Usuários gravam direto no share (sem push do Windows) | 2026-10-21 |
| 3 | **Uma base no OWUI por concurso** (Tiradentes BM, depois magistratura, HCPA…) | 2026-10-21 |
| 4 | Pasta do concurso: `tiradentes-bm` | 2026-10-21 |
| 5 | O processo **nunca** apaga conhecimento sozinho | 2026-10-21 |

## 17. Situação da execução

| # | Item | Estado |
|---|---|---|
| 1 | Árvore `~/documents` + `LEIA-ME.txt` | **feito** (2026-10-21) |
| 2 | Samba instalado + `smb.conf` versionado + `smbd` habilitado | **feito** (2026-10-21) |
| 3 | ufw 445 restrito à sub-rede + checks na suíte | **feito** (2026-10-21) |
| 4 | `~/documents` no backup diário (`documents.tgz`) | **feito** (2026-10-21) |
| 5 | Senha SMB do `usuario` | **feito** (2026-10-21) |
| 6 | Mapear `\\192.168.15.231\documentos` no Windows | **feito** (`T:`, SMB3, 2026-10-21) |
| 7 | Fase 0 — spike de ingestão | **feito** (2026-10-21) — resultado em §18 |
| 8 | Fase 2 — worker `rag-ingest` + manifest | **feito** (2026-10-21) — resultado em §19 |
| 9 | Fase 3 — cron 15 min + `_relatorio/INGESTAO.md` | **feito** (2026-10-21) — resultado em §20 |
| 10 | Fase 4 — métrica `hermes_rag_*` + alerta "pendente > 24 h" | **feito** (2026-10-22) — resultado em §21 |
| 11 | Fase 5 — **banco de questões** (provas/gabaritos → SQLite) | **feito** (2026-10-22) — plano e medições em [`BANCO-DE-QUESTOES.md`](BANCO-DE-QUESTOES.md) |

## 18. Fase 0 — o que o spike provou (2026-10-21)

Spike rodado no host, dentro do container `open-webui`, com dois arquivos reais de 2026
(`prova-2026.pdf`, 20 páginas; `gabarito-2026.pdf`, 3 páginas) na base **`Tiradentes BM`**.

### 18.1 Ingestão — aprovada

| Etapa | Prova | Custo medido |
|---|---|---|
| Upload + Docling (prova, 20 pág.) | 30 chunks, texto do artigo presente ("Lua de Sangue", "eclipse") | **45,4 s** (~2,3 s/página) |
| Upload + Docling (gabarito, 3 pág.) | 3 chunks, tabela de respostas presente | **20,3 s** |
| Chunk + `bge-m3` + Qdrant (`file/add`) | 33 vetores na coleção, `tenant_id` = id da base | 1,7 s / 0,3 s |

Métricas de última geração do spike (não de estimativa): Docling em CPU é o gargalo do lote
(~46 s por prova); para as 16 provas do acervo, ~15 min de processamento — cabe num `cron` noturno.

### 18.2 O chunking estava destruindo o documento (corrigido)

O padrão do OWUI 0.12.3 (`enable_markdown_header_text_splitter = true`) quebra o markdown do
Docling em **cada `##`** — e o Docling transforma cada questão em `## Questão N`:

| Configuração | Chunks da prova | Média | Pior chunk |
|---|---|---|---|
| padrão (header splitter ligado, 1000/100) | 88 | **281 chars** | 13 chars (`## Questão 26`) |
| splitter desligado, **1200/200**, `top_k` 6 | 30 | **850 chars** | questão completa |

A correção foi aplicada **globalmente** no OWUI (é `PersistentConfig`, gravado na tabela
`config`, via `POST /api/v1/retrieval/config/update`):

```
ENABLE_MARKDOWN_HEADER_TEXT_SPLITTER = false
CHUNK_SIZE = 1200
CHUNK_OVERLAP = 200
TOP_K = 6
```

Vale para **toda** ingestão futura; o que já estava vetorizado precisa ser reingerido para
herdar o novo tamanho (a base `Tiradentes BM` foi refeita no spike).

### 18.3 O chat pelo gateway Hermes é inviável para estudo (medido)

O OWUI fala com o `hermes-agent` (gateway `:8642`). O gateway monta o repositório em `/workspace`
e injeta no prompt o **`AGENTS.md` (36 KB) + esquemas de ferramentas**:

| Caminho | Prompt por chamada | Tempo de uma pergunta |
|---|---|---|
| gateway, pergunta trivial ("2+2") | **21.626 tokens** | 65–91 s |
| gateway + RAG (caminho do OWUI) | 21,6k × 5 chamadas | **432 s e 588 s** |
| Ollama direto + mesmos 6 chunks | 1.750–2.432 tokens | **12–34 s** |

As 5 chamadas são: resposta + título + tags + follow-up + geração de query (config `task.*` do
OWUI; `follow_up`, `tags` e `query.retrieval` estão ligados).

### 18.4 Qualidade: 4b a 64k mente; 8b a 16k é honesto

| Modelo | Prova (Texto 1) | Gabarito (Q26) |
|---|---|---|
| `qwen3:4b-64k` (65k ctx, 13% em CPU) | correto, 34 s | **inventou** ("48 questões", "C"); em duas tentativas gastou 14k chars de raciocínio e devolveu vazio |
| `qwen3:8b-extract` (16k ctx, 100% GPU, já residente p/ mem0) | correto, **12 s** | **honesto**: "50 questões; a resposta da 26 não está no gabarito fornecido" |

O `qwen3:4b-64k` foi para 64k de contexto e por isso perde 13% das camadas para a CPU — o que o
deixa lento — e, quando o dado não está no contexto, ele **completa com invenção**. O 8b a 16k
(5,7 GB, 100% GPU) responde melhor e ainda não disputa VRAM com a extração do mem0.

### 18.5 Ainda não funciona: tabela no gabarito

A página 1 do gabarito (onde está `26 B`) **não apareceu nem no `top_k` 8**: o chunk é só a
tabela (`12 B`, `13 A`, …), sem texto semântico, e a busca densa não casa "resposta da questão 26"
com ele. Consequências:

- **busca híbrida** (BM25 + vetor) é a candidata óbvia — `ENABLE_RAG_HYBRID_SEARCH=true`
  exige **reingerir** a base (a coleção passa a ter vetor esparso);
- e "qual é a resposta da 26" é, por decisão anterior (§15), pergunta do **banco de questões**,
  não do RAG. O RAG serve para *ler* o gabarito, não para consultá-lo por número.

### 18.6 Citação mostra o nome do arquivo, não o caminho

O `metadata` de cada chunk traz `source: <filename do upload>` e `page: N` — a citação do OWUI
sai como `prova-2026.pdf` (página N). O caminho relativo inteiro **não** aparece. Ajuste no §5:
o worker sobe com nome **achatado e informativo** (`tiradentes-bm-2026-prova.pdf`) e o caminho
completo fica no `manifest.csv`.

### 18.7 Decisões aplicadas (2026-10-21) e o resultado

| # | Decisão | Aplicado | Resultado medido |
|---|---|---|---|
| 1 | Conexão extra do OWUI **direto no Ollama** (`http://ollama:11434/v1`), modelo `qwen3:8b-chat-16k` (16k ctx, 5,2 GB, 100% GPU); gateway Hermes segue para o agente | sim | **328 s → 29 s** (a 1ª pergunta ainda paga a carga do modelo; daí `OLLAMA_KEEP_ALIVE: 30m`) |
| 2 | Desligar `tags` e `follow_up` do OWUI; `task.model.default` = modelo de estudo (nunca o gateway) | sim | menos 2 chamadas de LLM por mensagem |
| 3 | Busca híbrida (BM25 + vetor) | sim | ativa (`rank_bm25` já existe na imagem; **não** exigiu reingestão) — mas o BM25 do OWUI tokeniza por espaço, então não acha `26` em `26?`; sozinha não resolveu |
| 4 | Nome achatado na citação | sim | base refeita com `tiradentes-bm-2026-prova.pdf` e `tiradentes-bm-2026-gabarito.pdf` |

O que **realmente** trouxe a resposta da Q26 para o contexto foi `top_k = 8` (§18.5): com 3/6 a
página do meio do gabarito ficava fora; com 8 ela entra em 5º. Provas finais na base definitiva:

| Pergunta | Resposta do modelo (8b/16k, OWUI) | Tempo |
|---|---|---|
| Texto 1 (prova 2026) | eclipse lunar total / Lua de Sangue, com a explicação da atmosfera, `[1]` | 28,8 s |
| Gabarito 2026 (total e Q26) | **50 questões; questão 26 = B**, `[1]` | 328 s (frio) → ~29 s (quente) |

Estado final da base `Tiradentes BM`: **33 vetores** (30 da prova + 3 do gabarito), `top_k` 8,
splitter desligado, 1200/200, híbrida ligada.

**Ainda em aberto (não bloqueia a Fase 2):** o teto de `top_k=8` funciona para uma base pequena;
numa base com as 16 provas, a página do gabarito pode voltar a cair. A resposta por número de
questão continua sendo trabalho do **banco de questões** (§15), não do RAG.

## 19. Fase 2 — o worker em produção (2026-10-21)

Dois scripts, duas fronteiras:

| Script | Onde roda | O que faz |
|---|---|---|
| `tools/rag_ingest.py` | **host** (usuario, só stdlib) | varre o share, dedupa por SHA-256, chama o uploader, grava manifest/log/relatório, move falha para `_rejeitados/` |
| `tools/owui_upload.py` | **container `open-webui`** | sessão JWT, cria/reusa a base, upload `process=true`, `file/add`, confere `knowledge_file` e vetores, **descarta** o arquivo se o Docling falhar |

O share entra no container como **`/documents:ro`** (`docker-compose.yml`) — o worker não copia
arquivo e o RAG não tem como escrever no share.

### 19.1 Números medidos (não estimados)

| Item | Medida |
|---|---|
| 16 PDFs (2020–2027, 6,9 MB) | **9m45s** no total, **423 vetores**, 16 arquivos / 16 vínculos |
| Prova (~20 pág.) | 41–69 s cada (Docling em CPU) |
| Edital 2027 (107 k chars) | **125,8 s** (o maior documento) |
| Gabaritos | 5–21 s |
| `bge-m3` + Qdrant por documento | ~1–2 s |

### 19.2 Provas da fase

| Caso | Resultado |
|---|---|
| **2ª execução** | `0 novo / 16 já ingerido`; base continua **16 files / 16 links** (sem duplicata) |
| **Arquivo corrompido** (5 KB de `urandom` com `.pdf`) | falha no Docling → copiado para `_rejeitados/` + `.motivo.txt` com as 3 últimas linhas; **arquivo descartado** do OWUI (base segue 16/16); 2ª execução **não retenta** (`estado=falhou`), `--retentar` reabre |
| **Remoção explícita** (`--remover <sha>`) | 17 → **16** arquivos, linha `knowledge_file` limpa, manifest marca `removido` |
| **`--dry-run`** | lista as ações e **não escreve nada** (nem o log) — é o que a suíte checa |
| **Relatório** | `_relatorio/INGESTAO.md` reescrito a cada execução (contagens, falhas, pendentes) |

### 19.3 O que a base cheia mostrou (limite, não regressão)

Com 423 vetores, a pergunta "qual a resposta da questão 10 do gabarito de 2024" **não** recuperou
o gabarito de 2024: o ano está no **nome** do arquivo (metadado da citação), não no texto da
tabela; e `top_k=8` entre 423 chunks dilui. O modelo foi honesto ("não está no contexto") em vez
de inventar. Consequências:

- perguntas do tipo "o que diz o edital de 2027" ou "como era a redação de 2025" funcionam —
  o **texto** casa com a pergunta;
- perguntas por **número/ano de questão** são do **banco de questões** (§15) — confirma a
  fronteira decidida antes do worker existir;
- a suíte cobre o caminho do arquivo (mount `:ro`, manifest, dry-run), não a qualidade da busca.

### 19.4 O que a suíte passou a exigir

Mount `/documents:ro` presente e **não gravável**; os dois scripts instalados no host; linha na
tabela `docs/runbooks/scripts/tools.md`; `--dry-run` sai 0 e **não altera** o manifest; cabeçalho
do manifest com as 10 colunas do §7. Total: **194 PASS**.

## 20. Fase 3 — o worker no cron (2026-10-21)

O worker da Fase 2 passou a rodar sozinho, a cada 15 min. Não há lógica nova: o que o cron precisa
é um **wrapper** e uma **entrada de cron**, ambos versionados.

| Peça | Arquivo | Instalado como |
|---|---|---|
| Wrapper | `ops/bin/rag_ingest.sh` | `/usr/local/bin/rag-ingest` |
| Agendamento | `ops/cron/rag-ingest.cron` | `/etc/cron.d/rag-ingest` (`*/15 * * * * usuario`) |
| Lógica | `tools/rag_ingest.py` (sem mudança de fluxo) | — |

O wrapper existe por três motivos, e nenhum é cosmético:

1. **roda como `usuario`**, não root: é o dono do share e do `~/rag-state`. Como root,
   `_relatorio/` e `_rejeitados/` nasceriam de root dentro do share e o usuário não conseguiria
   abrir/renomear. O wrapper reexecuta como `usuario` se for chamado como root.
2. **`flock -n`** em `~/rag-state/ingest.lock`: o lote inicial levou **9m45s**; um lote maior passa
   dos 15 min e a execução seguinte **não** pode atropelar — ela registra `skip` e sai.
3. **log em `~/rag-state/cron.log`** (rotação em 5 MB): cron sem MTA não manda e-mail; o log é o
   único lugar onde "o disparo aconteceu" fica registrado.

### 20.1 Prova de disparo (o efeito prova, não o arquivo)

Depois do deploy, a entrada foi trocada **temporariamente** para `* * * * *` (prática do projeto:
agendamento novo se prova disparando) e as duas execuções seguintes apareceram no log:

```
2026-10-22T00:40:01Z  == rag-ingest (cron)
2026-10-22T00:40:01Z  == execução: 16 documento(s) no share
2026-10-22T00:40:02Z  [novo] .../2022/prova_gabarito/gabarito-2022.txt -> tiradentes-bm-2022-gabarito.txt (base "Tiradentes BM", 424 vetores, 0.5s, 190 chars)
2026-10-22T00:40:02Z  == resumo: 1 novo(s), 15 já ingerido(s), 0 aguardando, 0 falha(s)
2026-10-22T00:41:01Z  == rag-ingest (cron)
2026-10-22T00:41:01Z  == resumo: 0 novo(s), 16 já ingerido(s), 0 aguardando, 0 falha(s)
```

O primeiro minuto ingeriu **um arquivo que o usuário tinha acabado de deixar no share** (o gabarito
de 2022, redigitado como `.txt`); o segundo **não duplicou nada**. Depois a entrada voltou para
`*/15` (`sudo install -m 644 <repo>/ops/cron/rag-ingest.cron /etc/cron.d/rag-ingest`).

Estado da base após a prova: **17 documentos / 424 vetores** (o `.txt` novo convivendo com o
`gabarito-2022.pdf` antigo, lido pela metade pelo OCR — o processo **não** apaga sozinho). Em
2026-10-22 o dono decidiu remover o PDF: `rag-ingest --remover 3def7204…` → base de volta a 16.

### 20.2 O que a suíte passou a exigir

| Check | Por quê |
|---|---|
| `/usr/local/bin/rag-ingest` executável | arquivo ausente = cron sem runner |
| `/etc/cron.d/rag-ingest` com `*/15` e usuário `usuario` | usuário errado = arquivos de root no share |
| `HOME=/home/usuario` na entrada | o CLI do `docker` herda `$HOME` do cron |
| relatório reescrito há **≤ 45 min** | prova pelo efeito; cron parado/host desligado = **WARN** (estado do ambiente, não regressão) |
| `aviso_extracao()` por tipo de arquivo | PDF escaneado avisa; `.txt` curto **não** (era falso alarme de "OCR falhou" no gabarito digitado) |

Falha de conteúdo (arquivo em `_rejeitados/`) continua sendo **WARN/alarme do usuário**, nunca
FAIL: o worker não apaga nada sozinho.

### 20.3 O que o usuário vê

Copia o PDF em `T:\concurso\tiradentes-bm\<ano>\...` no Explorer → em **≤ 15 min** ele está na
base `Tiradentes BM` e citável no chat de estudo, sem tocar em nada. `T:\_relatorio\INGESTAO.md`
mostra a última execução; `T:\_rejeitados\` é onde uma falha aparece (com `.motivo.txt`).

As Fases 0–4 estão concluídas. O que sobrou do plano era o **banco de questões** — Fase 5, também
**feita** em 2026-10-22: desenho, medições e limites em
[`BANCO-DE-QUESTOES.md`](BANCO-DE-QUESTOES.md); operação em
[`../runbooks/scripts/questoes.md`](../runbooks/scripts/questoes.md).

### 20.4 Editar um documento é versão nova, não documento novo (2026-10-22)

A primeira correção real do dono expôs a lacuna: ele digitou o gabarito de 2022 como `.txt`, viu que
havia errado a numeração (`24E` onde era `34E`) e **salvou o mesmo arquivo**. O cron fez o que o
código mandava — subiu a versão nova e **deixou a antiga na base**, marcada `substituido` só no
manifest. Resultado: **duas citações com o mesmo nome**, uma delas com a resposta errada.

Decisão (aprovada pelo dono): **mesmo caminho + SHA-256 diferente = substituição**, não duplicata.

| Antes | Agora |
|---|---|
| `--substituir` opcional apagava a antiga; sem a flag, ficavam as duas | a substituição é o **padrão**; a linha antiga vira `substituido` no manifest |
| remoção antes da subida (falha do Docling = documento fora da base) | **sobe primeiro, remove depois** — se a remoção falhar, a versão boa está garantida e o log mostra o `--remover` exato |
| arquivo apagado do share | continua igual: nada sai da base sem `--remover` (remoção é decisão do escritório) |

`--substituir` continua aceito como **no-op** (scripts antigos não quebram) e o `--dry-run` diz
`substituiria` nesse caso — é o que a suíte prova, num sandbox em `/var/tmp` com manifest falso
(três checks: conteúdo novo substitui; mesmo SHA não substitui; a versão `substituido` aceita
`--remover`).

### 20.5 Varredura de 2026-10-22 (o que a suíte não vê sozinha)

| Achado | Evidência | Correção |
|---|---|---|
| **Prometheus fora do ar há 4 h** | host ficou desligado de 01:09 a 09:22 (queda/quebra de energia); 11 containers voltaram, o prometheus ficou `Exited (255)` apesar de `restart: unless-stopped`; 7 FAIL na suíte e alertas cegos | `docker compose up -d prometheus` → `Up (healthy)`; suíte verde. Registrado como armadilha no `AGENTS.md` |
| **Watcher do Windows não avisava** | `$ErrorActionPreference='Stop'` transforma o stderr do `ssh` que não conecta em exceção: o script morria **antes** do `if (-not $raw)` (e mesmo ali só logava) — provado com `-Remote 192.0.2.1` (rc=1 sem log) | `$ErrorActionPreference='Continue'` em volta do `ssh` + branch que **notifica** (`PrometheusSemResposta(critical)`, dedup 6 h). Provado: 1ª chamada notifica, 2ª suprime; suíte cobra os marcadores |
| **`--dry-run` mudo no terminal** | o wrapper mandava toda a saída para `cron.log` | `[ -t 1 ]` → `tee` no terminal; no cron continua só no log |
| **Fuso horário em `Etc/UTC`** | "caí às 21:00 e voltei às 06:00" vs. host `01:09 → 09:22`; o cron rodava 3 h deslocado (backup "03:30" à meia-noite) e todo log aparecia 3 h adiantado | `sudo timedatectl set-timezone America/Sao_Paulo`; worker e wrapper gravam hora **local com offset**; a suíte falha se o fuso voltar para UTC |
| **Falso alarme de OCR em `.txt`** | 190 chars num arquivo de 239 bytes é o conteúdo inteiro | `aviso_extracao()` considera o tipo (ver §20.2) |

## 21. Fase 4 — operação: métricas e alerta (2026-10-22)

A Fase 3 deixou o worker rodando sozinho; faltava **enxergar** o que ele faz sem abrir o
Explorer. A Fase 4 fecha o ciclo: o próprio worker publica o estado, o Prometheus mostra e o
watcher do Windows avisa.

### 21.1 O que foi decidido

| Decisão | Por quê |
|---|---|
| quem publica é o **worker** (não um cron novo) | ele já sabe documentos/falhas/pendentes no fim de cada execução; um segundo processo varreria o share de novo e poderia divergir |
| **textfile do node-exporter** (`ci/textfile/hermes_rag.prom`) | mesmo caminho de `hermes_ci_*`, `hermes_backup_*`, `hermes_tls_*` e `hermes_mem0_*`; zero infra nova |
| escrita **atômica** (`tmp` + `chmod 644` + `mv`) | o scrape pode cair no meio da escrita; o Prometheus lê o arquivo inteiro ou o anterior |
| "pendente" = **arquivo no share há > 1 h fora da base** | é o que dói: você colocou e não entrou. Cópia recém-caída (< 1 h) entra na execução seguinte e não é pendência |
| alerta em **24 h** | tempo de alguém notar; menos que isso é ruído de um lote grande do Docling |

### 21.2 Métricas publicadas

| Métrica | Tipo | Significado |
|---|---|---|
| `hermes_rag_documentos_total` | gauge | documentos `ok` no manifest (na base) |
| `hermes_rag_falhas_total` | gauge | conteúdos cujo estado **atual** é `falhou` |
| `hermes_rag_rejeitados_total` | gauge | arquivos em `_rejeitados/` |
| `hermes_rag_aguardando_total` | gauge | pulados nesta execução por cópia recente (< 30 s) |
| `hermes_rag_pendentes_total` | gauge | arquivos no share há > 1 h que não estão na base |
| `hermes_rag_pendente_mais_antigo_segundos` | gauge | idade do pendente mais antigo (`0` = nada) |
| `hermes_rag_ultima_execucao_timestamp_seconds` | gauge | epoch da última execução |
| `hermes_rag_ultima_execucao_sucesso` | gauge | `1` sem falhas, `0` com falha (exit 1) |
| `hermes_rag_ultima_execucao_duracao_segundos` | gauge | duração do último lote |

### 21.3 Alertas (grupo `lab`)

| Alerta | Expressão | Para quê |
|---|---|---|
| `LabRagPendente24h` | `hermes_rag_pendente_mais_antigo_segundos > 24 * 3600` | documento no share há mais de 24 h sem entrar na base |
| `LabRagParado` | `time() - hermes_rag_ultima_execucao_timestamp_seconds > 2 * 3600` | cron/wrapper/host parado |
| `LabRagFalhou` | `hermes_rag_ultima_execucao_sucesso == 0` | última execução rejeitou arquivo |
| `LabRagMetricMissing` | `absent(hermes_rag_ultima_execucao_timestamp_seconds)` | textfile não publicado (alertas acima cegos) |

### 21.4 Provas da fase (o que a suíte cobra)

| Prova | Como |
|---|---|
| métricas publicadas | `hermes_rag.prom` existe com as 6 métricas essenciais e é reescrito há < 45 min |
| série viva | `hermes_rag_documentos_total` responde no Prometheus |
| regras ativas | as 4 `LabRag*` aparecem em `/api/v1/rules` (o HUP do deploy é obrigatório) |
| alerta dispara em teste | arquivo `hermes_rag.prom` sintético com `pendente_mais_antigo` alto → a regra entra em `pending` em ≤ 2 scrapes; removido, volta a inativo |
| falha visível | execução com `_rejeitados/` sai `success=0` no textfile e `hermes-ci`/suíte viram WARN (estado do ambiente, não regressão) |

Limite conhecido: o `pendente` olha o **share** (mtime), não o Docling. Um PDF que o Docling
extrai vazio entra na base e não é pendente — para isso existe o aviso de extração curta no log e
no relatório.

