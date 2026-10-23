# questoes.sh — banco de questões do eixo de estudos (share → SQLite)

| | |
|---|---|
| Arquivo | `ops/bin/questoes.sh` |
| Instalado como | `/usr/local/bin/questoes` |
| Agendamento | `ops/cron/questoes.cron` → **a cada 30 min** (`5,35`) |
| Lógica | `tools/questoes.py` (host, só stdlib + `sqlite3`) |
| Leitura dos PDFs | `pdftotext` (poppler); gabarito em imagem: `pdftoppm` + `tesseract` (OCR) |
| Banco | `~/rag-state/questoes.db` (entra no backup diário, junto com `rag-state.tgz`) |
| Estado/log | `~/rag-state/questoes.log`, `~/rag-state/questoes.lock` |
| Relatório | `~/documents/_relatorio/QUESTOES.md` (situação por ano) |
| Documento citável | `~/documents/referencias/estatisticas-questoes.md` → ingerido pelo `rag-ingest` |
| Roda como | `usuario` (dono do share e do estado) |
| Plano | [`../../plans/BANCO-DE-QUESTOES.md`](../../plans/BANCO-DE-QUESTOES.md) |

## O que faz

1. Varre `~/documents/concurso/<slug>/<ano>/` procurando `prova-<ano>.<pdf|txt>` e
   `gabarito-<ano>.<pdf|txt>`.
2. Lê a prova com `pdftotext -layout` e extrai **questão, enunciado, alternativas, disciplina e
   página**. A disciplina vem do cabeçalho (`MATEMÁTICA` / `PROVA DE MATEMÁTICA`) ou, quando não
   há, do número (1–25 português, 26–50 matemática).
3. Lê o gabarito em texto; se o PDF for **imagem**, roda OCR a 300 dpi: tabela de duas colunas
   (`1 C 26 c`) pelo texto corrido e **grade** (números numa linha, letras na de baixo) pelas
   coordenadas das células.
4. Grava no SQLite **em transação por ano**. O SHA-256 do arquivo fica em `arquivo`: rodar de novo
   sem mudança não reescreve nada (idempotente).
5. Reescreve `_relatorio/QUESTOES.md`; com `estatisticas --publicar` (o cron faz sozinho), escreve
   `referencias/estatisticas-questoes.md`, que o worker de ingestão leva ao RAG — **o chat passa a
   responder "quantas questões de matemática caíram em 2025" com citação**.
6. **Não apaga nada do share.** O banco é derivado: pode ser apagado e reconstruído com
   `questoes importar --forcar`.

## Regra de ouro

Ano que não fechar **50 questões (1–50) e 50 respostas** fica `revisar`; o relatório diz o que
falta e `questoes conferir` **falha**. Ano com gabarito e sem prova (2027) fica `sem_prova` — não
é erro, é o estado do material.

## Rodar à mão

```bash
ssh davy-jones-hermes 'questoes'                         # importa o que mudou + publica estatísticas
ssh davy-jones-hermes 'questoes importar --forcar'       # reimporta tudo (após mexer no parser)
ssh davy-jones-hermes 'questoes conferir'                # 50/50 por ano (exit != 0 se faltar)
ssh davy-jones-hermes 'questoes consultar --ano 2025 --numero 26'
ssh davy-jones-hermes 'questoes consultar --texto porcentagem --limite 5'
ssh davy-jones-hermes 'questoes estatisticas --publicar'
ssh davy-jones-hermes 'questoes exportar --destino /var/tmp/questoes.csv'
```

Consulta por número é exata: `--ano 2024 --numero 26` devolve o enunciado, as alternativas e o
gabarito. Alternativa cujo conteúdo é figura no PDF aparece como `[figura/tabela no PDF]` — abra
o PDF para resolver.

## Leitura direta do banco

```bash
ssh davy-jones-hermes "python3 - <<'PY'
import sqlite3
c = sqlite3.connect('/home/usuario/rag-state/questoes.db')
for r in c.execute('select ano, status, detalhe from ano_status order by ano'):
    print(r)
PY"
```

## Se falhar

| Sintoma | Causa provável | Ação |
|---|---|---|
| ano com status `revisar` | PDF sem texto, gabarito ilegível ou questão faltando | ver o detalhe em `_relatorio/QUESTOES.md`; se o gabarito é imagem ruim, digitar `gabarito-<ano>.txt` |
| `OCR leu N de 50 respostas` | gabarito em imagem de baixa qualidade | digitar o `.txt` (como o de 2022); o importador aceita |
| `tesseract não está instalado` | host reinstalado | `sudo apt-get install -y tesseract-ocr tesseract-ocr-por` |
| estatísticas não aparecem no chat | worker de ingestão não rodou ainda | `rag-ingest --dry-run`; em ≤ 15 min entra |
| `skip` repetido em `questoes.log` | execução anterior travada | `ps aux \| grep questoes`; o `flock` libera sozinho |
| arquivo do share com dono root | alguém rodou o worker como root | o wrapper troca para `usuario`; corrija com `sudo chown -R usuario:usuario ~/documents` |

## Reinstalar / desligar

```powershell
powershell -File ops\deploy\sync-to-host.ps1     # reinstala runner + entrada do cron
```

```bash
ssh davy-jones-hermes 'sudo rm /etc/cron.d/questoes'   # desliga o agendamento (o banco continua)
```
