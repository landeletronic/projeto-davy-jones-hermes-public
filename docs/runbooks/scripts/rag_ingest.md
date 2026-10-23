# rag_ingest.sh — worker de ingestão do eixo de estudos (share → RAG)

| | |
|---|---|
| Arquivo | `ops/bin/rag_ingest.sh` |
| Instalado como | `/usr/local/bin/rag-ingest` |
| Agendamento | `ops/cron/rag-ingest.cron` → **a cada 15 min** (`*/15`) |
| Lógica | `tools/rag_ingest.py` (host, só stdlib) + `tools/owui_upload.py` (dentro do `open-webui`) |
| Estado | `~/rag-state/manifest.csv`, `~/rag-state/ingest.log`, `~/rag-state/cron.log` |
| Relatório | `~/documents/_relatorio/INGESTAO.md` (reescrito a cada execução) |
| Métricas | `~/hermes-architect/ci/textfile/hermes_rag.prom` → Prometheus/Grafana (`hermes_rag_*`) |
| Roda como | `tlandskron` (dono do share e do estado) |
| Horários | **locais, com offset** (`2026-10-22T10:47:57-03:00`) — o host está em `America/Sao_Paulo` e o cron usa a hora local |

## O que faz

1. Varre `~/documents` e ignora o que começa com `_` e o `LEIA-ME.txt`. Aceita o que o Docling
   lê (PDF, DOCX, TXT — o gabarito de 2022 entrou como `.txt` digitado).
2. Ignora arquivo com menos de **30 s** de idade (cópia em andamento no Explorer).
3. Calcula o **SHA-256** e compara com o `manifest.csv` (é o que impede duplicar).
4. Se é novo, sobe via `/documents/<caminho>` (o share entra **somente leitura** no container),
   com nome achatado (`tiradentes-bm-2026-prova.pdf`) na base do concurso (`Tiradentes BM`).
5. **Mesmo caminho com conteúdo novo = versão nova do mesmo documento:** a nova sobe e a antiga
   **sai da base** (marcada `substituido` no manifest). Sem isso o RAG citaria a resposta que você
   acabou de corrigir. A remoção da antiga vem **depois** da subida: se ela falhar, a versão boa
   está garantida e o log mostra o `--remover` exato.
6. Grava a linha no manifest e reescreve `_relatorio/INGESTAO.md`.
7. Falhou? Copia para `_rejeitados/` com `.motivo.txt` e **descarta** o arquivo do OWUI.
8. Arquivo que **sai** do share continua na base (conhecimento não desaparece sozinho) — remoção
   é explícita: `--remover <sha256>`. Vale para a versão `ok` e para a `substituido` (versão
   antiga que ainda esteja na base).

## Rodar à mão

```bash
ssh davy-jones-hermes 'rag-ingest --dry-run'          # mostra o que faria; não escreve nada
ssh davy-jones-hermes 'rag-ingest'                    # ingere o que é novo
ssh davy-jones-hermes 'rag-ingest --remover <sha256>' # remove um documento da base
ssh davy-jones-hermes 'rag-ingest --retentar'         # tenta de novo o que está em falhou
```

O SHA-256 de cada documento está em `~/rag-state/manifest.csv` (coluna 1). O `--dry-run` é a
forma de conferir antes de um lote grande — ele mostra `subiria` (documento novo) ou
`substituiria` (mesmo caminho, conteúdo novo).

## Editar um documento que já está na base

| O que você faz no Explorer | O que acontece |
|---|---|
| edita/salva o **mesmo** arquivo | em até 15 min a versão nova entra e a antiga **sai** da base (o nome na citação não muda) |
| salva com **outro nome** (ex.: `gabarito-2022-v2.txt`) | entra como documento novo; o antigo **fica** (use `--remover <sha256>` se quiser tirar) |
| **apaga** o arquivo do share | nada muda na base — conhecimento só sai com `--remover <sha256>` |
| **move** para outra pasta (ex.: `apostilas/matematica/`) | nada é reingresso: a chave é o `sha256` (o `--dry-run` continua dizendo "N já ingerido(s)"). Só a coluna `origem` do manifest fica apontando para o caminho velho — reapontar **pelo sha** e conferir com a suíte |

## Cobertura: o PDF entrou inteiro?

O OWUI grava `metadata.page` em cada chunk. Contar as páginas distintas por `metadata.file_hash`
no Qdrant e comparar com `pdfinfo` responde "entrou tudo?" sem depender de LLM. Medido em
2026-10-22 nas 5 apostilas (680 páginas): **todas as páginas estão na base**; a perda é de
**texto dentro de tabela**, que o Docling às vezes converte em `<!-- image -->` (2 páginas só com
imagem e ~13 com menos de 60% do volume, na apostila de Matemática). Não compare o texto do PDF
(`pdftotext`) com o markdown do Docling procurando trecho exato: são extratores diferentes e o
resultado é "buraco" falso.

### O que fazer quando a tabela não entrou

Parâmetro de conversão **não resolve** (medido em 2026-10-23 na p.160 da Matemática:
`table_mode=accurate` dá o mesmo resultado do `fast`, `force_ocr` também, os quatro `pdf_backend`
idem, e os formatos `text`/`html` também descartam). O Docling **lê** o texto (está em `texts`),
mas o layout marca a área como **figura** e o exportador joga os filhos fora.

O caminho é o **complemento**: `tools/rag_complemento.py` compara página a página com a base e
grava `complemento-<documento>.md` ao lado do PDF, com o texto das páginas que perderam mais de
40% do volume. O worker ingere esse `.md` como documento normal (a citação mostra o complemento).

```bash
python3 tools/rag_complemento.py --dry-run     # lista as páginas
python3 tools/rag_complemento.py              # grava os complementos
rag-ingest                                    # ou espere o cron (15 min)
```

Estado em 2026-10-23: **6 complementos, 25 páginas** (15 na Matemática, 2 em Português, 1 na
apostila de provas, 5 no edital de 2027 e 1 em cada um dos gabaritos de 2020/2025). Refazer se o
PDF mudar (o `.md` guarda o sha256 do PDF de origem). **Nunca editar o complemento à mão** — a
próxima geração sobrescreve.

## Por que 15 min (e não 1)

O Docling roda em CPU: **~1 min por prova** (16 PDFs = 9m45s). Um intervalo menor só encheria o
log; o wrapper toma `flock`, então um lote grande **não** é atropelado pela execução seguinte
(ela registra `skip` em `cron.log` e sai).

## Métricas e alertas (Fase 4)

O worker publica o próprio estado no **textfile do node-exporter** ao fim de cada execução
(inclusive quando falha). Não existe cron separado só para a métrica: quem roda a cada 15 min já
sabe o que aconteceu.

| Métrica | Significado |
|---|---|
| `hermes_rag_documentos_total` | documentos `ok` no manifest (na base) |
| `hermes_rag_falhas_total` | conteúdos cujo estado **atual** é `falhou` (só saem com `--retentar`) |
| `hermes_rag_rejeitados_total` | arquivos em `_rejeitados/` (cada um com `.motivo.txt`) |
| `hermes_rag_aguardando_total` | arquivos pulados **nesta** execução por cópia recente (< 30 s) |
| `hermes_rag_pendentes_total` | arquivos no share há **mais de 1 h** que não estão na base |
| `hermes_rag_pendente_mais_antigo_segundos` | idade do pendente mais antigo (`0` = nada pendente) |
| `hermes_rag_ultima_execucao_timestamp_seconds` | epoch da última execução |
| `hermes_rag_ultima_execucao_sucesso` | `1` sem falhas, `0` com falha (exit 1) |
| `hermes_rag_ultima_execucao_duracao_segundos` | quanto o lote levou |

Alertas (`monitoring/alert-rules.yml`): `LabRagPendente24h` (pendente há mais de **24 h**),
`LabRagParado` (sem execução há **2 h**), `LabRagFalhou` (última execução com falha) e
`LabRagMetricMissing` (textfile não publicado). "Pendente" é **documento no share que não entrou
na base** — a cópia recém-caída (< 1 h) não conta, ela entra na execução seguinte.

Conferir à mão:

```bash
ssh davy-jones-hermes 'cat ~/hermes-architect/ci/textfile/hermes_rag.prom'
ssh davy-jones-hermes "docker exec prometheus wget -qO- 'http://127.0.0.1:9090/api/v1/query?query=hermes_rag_pendente_mais_antigo_segundos'"
```

## Se falhar

| Sintoma | Causa provável | Ação |
|---|---|---|
| nada aparece no chat | cron parado | `systemctl is-active cron`; `tail -20 ~/rag-state/cron.log` |
| arquivo em `_rejeitados/` | PDF corrompido / Docling falhou | ler o `.motivo.txt`, corrigir o PDF e rodar `rag-ingest --retentar` |
| `skip` repetido em `cron.log` | execução anterior travada | `ps aux \| grep rag_ingest`; se não houver processo, o lock é liberado sozinho (flock) |
| `worker ausente em …/tools/rag_ingest.py` | sync não rodou | `powershell -File ops\deploy\sync-to-host.ps1` |
| `não tem … montado em /documents:ro` | container antigo (compose mudou) | `ssh davy-jones-hermes 'cd /home/tlandskron/hermes-architect && docker compose up -d open-webui'` |
| `_rejeitados/` ou `_relatorio/` com dono root | alguém rodou o worker como root | o wrapper já troca para `tlandskron`; corrija o passado com `sudo chown -R tlandskron:tlandskron ~/documents` |

## Reinstalar / desligar

```powershell
powershell -File ops\deploy\sync-to-host.ps1     # reinstala runner + entrada do cron
```

```bash
ssh davy-jones-hermes 'sudo rm /etc/cron.d/rag-ingest'   # desliga o agendamento (o share continua)
```
