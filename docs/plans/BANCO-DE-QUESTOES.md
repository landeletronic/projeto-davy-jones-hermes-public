# Banco de questões — provas e gabaritos do Colégio Tiradentes BM/RS

> **Fase 5 do eixo de estudos.** O RAG responde *"o que diz o edital"*; o banco de questões
> responde *"quantas questões de matemática caíram em 2025"*, *"qual a resposta da Q26 de 2024"*
> e *"como a prova de 2023 cobrou porcentagem"*. É derivado dos mesmos PDFs, em SQLite, no host.
>
> Implementação: `tools/questoes.py` (host, só stdlib) + wrapper `ops/bin/questoes.sh`
> (instalado como `/usr/local/bin/questoes`) + `ops/cron/questoes.cron` (a cada 30 min).
> Card operacional: [`../runbooks/scripts/questoes.md`](../runbooks/scripts/questoes.md).

## 1. Por que existe (a fronteira com o RAG)

Medido em 2026-10-21 (Fase 2 do eixo): com 16 documentos na base, perguntar *"a resposta da Q10 do
gabarito de 2024"* **não** trouxe o gabarito de 2024 — **o ano está no nome do arquivo, não no
texto**, e o `top_k=8` entre 424 vetores não tem como priorizar por número de questão. Não é
limite de modelo nem de chunking: é a natureza da busca semântica.

| Pergunta | Quem responde |
|---|---|
| "o que o edital de 2027 exige?" | **RAG** (leitura do documento) |
| "qual a resposta da Q26 de 2025?" | **banco de questões** (consulta exata) |
| "quantas questões de matemática por ano?" | **banco** → publicado como `.md` citável |
| "quais tópicos mais caem?" | banco (fase futura; hoje: contagem por disciplina) |

O banco **não substitui** o RAG: ele é construído *a partir* dos arquivos que o RAG já lê.

## 2. O material, medido (2026-10-22)

Sete provas (`prova-2020.pdf` … `prova-2026.pdf`) e oito gabaritos (2020–2027). Todas as provas
têm **50 questões, 1..50, sem buraco** (contado com `pdftotext -layout`).

| Ano | Prova | Marcador | Alternativas | Gabarito | Como é lido |
|---|---|---|---|---|---|
| 2020 | 50 | `Questão 1 – …` | `(A)` | PDF texto | `pdftotext` |
| 2021 | 50 | `Questão 1 – …` | `(A)` | PDF texto | `pdftotext` |
| 2022 | 50 | `Questão 1 - …` / `50.` | `a)` | `.txt` digitado | texto |
| 2023 | 50 | `Questão 1. …` | `a)` | **imagem (grade)** | **OCR** (`--psm 11` + coordenadas) |
| 2024 | 50 | `Questão 1. …` | `a)` | PDF texto | `pdftotext` |
| 2025 | 50 | `Questão 1` | `(A)` | **imagem (tabela)** | **OCR** (`--psm 6`) |
| 2026 | 50 | `Questão 1` | `a)` | PDF texto | `pdftotext` |
| 2027 | **sem prova** (só edital) | — | — | PDF texto | importa 50 respostas, fica `sem_prova` |

Achados que mudaram o desenho:

- **A indentação das alternativas varia dentro do mesmo ano** (3 espaços na Q7 de 2021, **13** na
  Q6). Regex com `^\s{0,8}` perdia a Q6 inteira → o parser usa `^\s*`.
- **Cabeçalho de página não é conteúdo**: `Colégio Tiradentes – Concurso de Admissão 2019/20 …
  Página 1` e `LÍNGUA PORTUGUESA e MATEMÁTICA – COLÉGIO TIRADENTES 23/24` entravam no meio do
  enunciado. O parser remove cabeçalho/rodapé e número de página das **bordas** de cada página.
- **Texto depois da última alternativa não é alternativa**: sem fechar a questão na linha em
  branco, a instrução *"Responda às questões 02 a 25…"* era colada na letra (E) da Q1 de 2020.
- **Disciplina por número (1–25 português, 26–50 matemática)**: confirmado pelo conteúdo das Q25
  e Q26 em todos os anos; o cabeçalho `MATEMÁTICA` (2024–2026) confirma quando existe. Cabeçalho
  em minúsculas no meio de um texto **não** troca a disciplina (2021 tem `língua portuguesa.`).
- **Nem toda questão tem 5 alternativas no PDF**: 2023 Q25 tem `a) b) c) e)` (falta a `d` no
  próprio documento); 2022 Q48 não tem alternativas em texto (são figura/tabela); 2020 Q29 e
  2023 Q47 têm as 5 letras com **conteúdo em imagem**. O banco registra o que existe — não
  completa.

## 3. Decisões (2026-10-22)

| Decisão | Escolha | Por quê |
|---|---|---|
| Gabaritos em imagem (2023/2025) | **OCR no host** (`tesseract-ocr` + `tesseract-ocr-por`) | 2025 sai como tabela (`1 C 26 c`); 2023 é grade com bordas, lida pelas **coordenadas** das células (TSV do `--psm 11`) |
| Estatísticas no chat | **publicar `referencias/estatisticas-questoes.md`** no share | o worker ingere como qualquer `.md`; o chat passa a responder contagens **com citação** |
| Atualização | **cron a cada 30 min** (`5,35`) | o import leva ~10 s; o offset evita o minuto exato do `rag-ingest` (`*/15`) e garante o `.md` estável (>30 s) antes da ingestão |
| `sympy` (verificar contas) | **fora desta entrega** | exige dependência no host e só parte das questões é verificável automaticamente; fica no backlog |

## 4. Desenho

```
~/documents/concurso/tiradentes-bm/<ano>/prova_gabarito/{prova,gabarito}-<ano>.<pdf|txt>
        │
        ├── questoes importar ──> pdftotext / pdftoppm+tesseract
        │                          │
        │                          ▼
        │                    ~/rag-state/questoes.db   (SQLite; entra no backup)
        │                          │
        │              ┌───────────┼─────────────┬──────────────────┐
        │              ▼           ▼             ▼                  ▼
        │          conferir    consultar    estatisticas       exportar
        │        (50/50, sai≠0) (ano/nº)   (--publicar)         (CSV)
        │                                      │
        ▼                                      ▼
 _relatorio/QUESTOES.md            referencias/estatisticas-questoes.md
 (situação por ano)                (vai ao RAG pelo worker de ingestão)
```

### Banco (`~/rag-state/questoes.db`)

| Tabela | Conteúdo |
|---|---|
| `arquivo` | caminho + SHA-256 → é o que torna o import **idempotente** |
| `prova` | ano, arquivo, sha, páginas, nº de questões |
| `questao` | ano, número, disciplina (`portugues`/`matematica`), enunciado, página |
| `alternativa` | ano, número, letra, texto (vazio = figura no PDF) |
| `gabarito` | ano, número, letra, **fonte** (`texto`/`txt`/`ocr-tabela`/`ocr-grade`) |
| `ano_status` | `ok` / `revisar` / `sem_prova` / `sem_gabarito` + detalhe |

### Comandos

```bash
questoes                       # importa o que mudou e publica as estatísticas (cron)
questoes importar --forcar     # reimporta mesmo sem mudança de arquivo
questoes conferir              # 50/50 por ano; exit != 0 se algum ano ficar `revisar`
questoes consultar --ano 2025 --disciplina matematica --numero 26
questoes consultar --texto porcentagem --limite 5
questoes estatisticas --publicar
questoes exportar --destino /var/tmp/questoes.csv
```

### Regra de ouro

**O importador não inventa.** Ano que não fechar 50 questões + 50 respostas fica `revisar`, o
relatório diz o que falta (`questões faltando 25,26…`) e `conferir` sai com código != 0 — a suíte
transforma isso em FAIL. Ano sem prova (2027) é `sem_prova`, não erro.

## 5. Prova de funcionamento (2026-10-22)

| Prova | Resultado |
|---|---|
| Import dos 8 anos | 2020–2026 `ok`, 2027 `sem_prova` |
| Questões | **350** (7 provas × 50), 175 português + 175 matemática |
| Respostas | **400** (8 gabaritos × 50) |
| Gabaritos em imagem | 2023 `ocr-grade` e 2025 `ocr-tabela` — 50/50 cada |
| OCR do 2023 conferido | transcrição independente da imagem bateu 50/50 com a do banco |
| Disciplina | Q25 português / Q26 matemática em **todos** os anos |
| Alternativas | 5 por questão, exceto os casos reais do §2 (2022 Q48 sem texto; 2023 Q25 sem `d`) |
| `questoes conferir` | exit 0, 8 anos |
| Idempotência | 2ª execução sem mudança não reescreve nada |
| Estatísticas | `.md` gerado e ingerido (SHA no manifest com estado `ok`) |

## 6. Limites conhecidos (honestos)

- **Fórmula/tabela em imagem não entra.** A Q29 de 2020 e a Q47 de 2023 têm as alternativas como
  figura; o banco guarda as letras e sinaliza `[figura/tabela no PDF]` na consulta. Resolver exige
  abrir o PDF — OCR de expressão matemática não é confiável.
- **2022 Q48**: as alternativas são um **gráfico**; a questão entra com 0 alternativas (enunciado
  e gabarito válidos).
- **2027**: há gabarito e edital, mas **não há prova publicada** → `sem_prova`. Quando a prova
  chegar ao share, o cron fecha 50/50 sozinho.
- **Sem tópico/assunto**: hoje a contagem é por ano e disciplina. Classificar por tópico
  (porcentagem, análise sintática…) é fase futura — exige vocabulário controlado ou modelo, e
  errar tópico é pior do que não ter.
- **`sympy`**: não verifica contas ainda (backlog).

## 7. Próximos passos (quando fizer sentido)

1. **Tópicos** por questão, com vocabulário fechado e revisão humana (não automática).
2. **`sympy`** para conferir a resposta de questões de matemática que sejam expressão/equação.
3. **Consulta no chat** para *"resposta da Q26"*: hoje o banco responde por CLI e as **contagens**
   vão ao RAG via `.md`; expor consulta exata ao chat exigiria ferramenta no gateway (o chat de
   estudo usa a conexão direta no Ollama, que não chama ferramenta).
