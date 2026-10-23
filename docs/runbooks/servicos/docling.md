# docling — conversão de PDF/DOCX para texto (ingestão da RAG)

| | |
|---|---|
| Imagem | `ghcr.io/docling-project/docling-serve-cpu:v1.37.0` |
| Porta | `127.0.0.1:5001` (só loopback; o OWUI fala pela rede `backend`) |
| Dados | volume `docling_cache` |
| Usado por | `open-webui` (`rag.content_extraction_engine = docling`) |
| Tempo máximo | `DOCLING_SERVE_MAX_SYNC_WAIT=3600` (1 h) — apostila de 305 páginas levou **1501 s** (medido 2026-10-22) |

## Verificar

```bash
docker inspect -f '{{.State.Health.Status}}' docling     # healthy
curl -s 127.0.0.1:5001/health | head -c 200
```

Depois de um upload, o log do OWUI deve citar `docling` — se citar `tika`/`default`, a
configuração de RAG não está efetiva (ver [open-webui](open-webui.md), `PersistentConfig`).

## Reiniciar

```bash
cd /home/tlandskron/hermes-architect && docker compose restart docling
```

## Sintomas típicos

- **Upload "conclui" mas não gera pontos** → o Docling devolveu erro (PDF escaneado sem OCR ou
  arquivo corrompido). Veja `docker logs --tail 50 docling`.
- **Primeira conversão muito lenta** → o modelo de layout é carregado na primeira chamada
  (cache em `docling_cache`); a segunda é rápida.
- **`connection refused` no OWUI** → o Docling subiu depois; `docker compose restart open-webui`.
- **`Gateway Timeout - Conversion is taking too long`** → o arquivo passou do `MAX_SYNC_WAIT`.
  Medido em 2026-10-22 (apostilas do eixo de estudos): 178 páginas = **1123 s**, 305 páginas =
  **1501 s** (~6 s/página; OCR em CPU). Com o limite antigo de 600 s, quatro apostilas foram para
  `_rejeitados/`; o limite agora é **3600 s**. Aumentar mais exige recriar o container
  (`docker compose up -d docling`), e **retentar** os arquivos em falha:
  `rag-ingest --retentar` (sem isso, a execução seguinte os pula).

## Teste isolado

`tools/test_docling_convert.sh` converte um PDF de exemplo e mostra o texto extraído.
`tools/wait_docling.sh` espera o serviço ficar pronto (útil em script).
