# qdrant — banco vetorial (memória do mem0 + RAG)

| | |
|---|---|
| Imagem | `qdrant/qdrant:v1.19.2` (pinada; upgrade **só** por degrau) |
| Porta | `6333` publicada, **bloqueada na LAN** pela cadeia `DOCKER-USER` |
| Dados | volume `qdrant_data` |
| Usam | `hermes-agent` (mem0) e `open-webui` (RAG) |
| Healthcheck | TCP em `127.0.0.1:6333` |

## Verificar

```bash
docker inspect -f '{{.State.Health.Status}}' qdrant        # healthy
curl -s localhost:6333/collections | python3 -m json.tool   # mem0_memories + owui_*
curl -s localhost:6333/collections/mem0_memories | python3 -m json.tool  # points_count
```

## Reiniciar

```bash
cd /home/tlandskron/hermes-architect && docker compose restart qdrant
```

## Não subir / perdido

- **Boot morre com `unknown variant 'rocks_db'`** → tentativa de upgrade direto. O volume só é
  lido pelo degrau seguinte (1.15.2 → 1.16.3 → 1.19.2). Restaure o volume anterior e use
  `tools/verify_qdrant_upgrade.sh --via`.
- **Volume vazio depois de recriar o container** → confira `docker volume ls | grep qdrant_data`;
  o compose usa volume nomeado, não bind-mount.
- **Coleção ausente** → ela é criada pelo primeiro `ADD` do mem0 (ou pelo upload do OWUI). Não
  crie à mão: o nome e a dimensão (`1024`) precisam bater.

## Backup / restore

O backup diário tira snapshot de **todas** as coleções (`qdrant-<coleção>.snapshot` dentro do tar).
Prova de restore: `tools/verify_backup_restore.sh` (coleção temporária) e
`tools/drill_restore_clean.sh` (Qdrant novo, volume vazio).
