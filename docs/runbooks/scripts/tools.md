# tools/ — scripts sob demanda (à mão)

> `tools/` é o que **se roda à mão**: não instala nada, não agenda nada. Os que rodam sozinhos
> vivem em `ops/` e têm card em [`scripts/`](.). Regra do par documental: todo script novo aqui
> ganha uma entrada nesta tabela (o card completo é obrigatório para os destrutivos).

| Script | Para que serve | Quando usar |
|---|---|---|
| `make_tls_cert.sh` | gera/renova o certificado autoassinado e (com `--reload`) recarrega o nginx | cert <30 dias ou expirado |
| `verify_backup_restore.sh` | restaura os snapshots do último backup numa coleção temporária e apaga | validar um artefato |
| `drill_restore_clean.sh` | sobe Qdrant + OWUI **novos** em volumes vazios, restaura e derruba | provar recuperação de máquina limpa |
| `verify_qdrant_upgrade.sh` | testa um upgrade de Qdrant por degrau numa **cópia** do volume | antes de subir de versão |
| `qdrant_peek.sh` | mostra coleções/contagem/payload de amostra | conferir memória/RAG |
| `test_docling_convert.sh` | converte um PDF e imprime o texto extraído | suspeita de falha de ingestão |
| `wait_docling.sh` | espera o Docling responder (para uso em script) | automação local |
| `set_owui_rag_config.py` | grava `rag.*` no banco do OWUI (`PersistentConfig`) | env não vale mais |
| `rag_ingest.py` | worker do eixo de estudos: varre `~/documents`, dedupa por SHA-256 e sobe o que é novo para a base do OWUI (agendado a cada 15 min como `rag-ingest`; card: [`rag_ingest.md`](rag_ingest.md)) | drop novo no share; `--remover` apaga da base |
| `rag_complemento.py` | grava `complemento-<documento>.md` ao lado do PDF com o texto das páginas que o Docling perdeu (tabela virou figura); o worker ingere o `.md` como documento normal | página com tabela/quadro ausente na base; `--dry-run` lista as páginas |
| `questoes.py` | banco de questões do eixo de estudos: provas/gabaritos do share → SQLite (`importar`/`conferir`/`consultar`/`estatisticas`/`exportar`; agendado a cada 30 min como `questoes`; card: [`questoes.md`](questoes.md)) | consulta por ano/número, contagem por disciplina, reconstruir o banco |
| `owui_upload.py` | sobe **um** arquivo para a base (roda dentro do container; é chamado pelo `rag_ingest.py`) | nunca à mão — use o `rag_ingest.py` |
| `inspect_owui_db.py` | inspeciona tabelas do `webui.db` | diagnóstico de dados |
| `inspect_owui_state.py` | resumo do estado (usuário/modelo/conexão) | conferir configuração |
| `inspect_owui_rag_ready.py` | checa se a RAG está pronta (coleções/embedding) | upload não indexa |
| `cleanup_owui_leftovers.py` | remove `knowledge_file` órfãs e knowledge de teste | após excluir arquivos |
| `cleanup_owui_test_kb.py` | limpa bases de teste criadas por smoke | depois de `SMOKE_RAG=1` |
| `make_test_pdf.py` | gera PDF sintético para o smoke | testes de RAG |
| `test_searxng.py` | consulta o SearXNG e valida o JSON | conferir busca interna |
| `prom_targets.py` | lista alvos do Prometheus por SSH | alvo `down` |
| `get_digests.sh` | mostra os digests das imagens em uso | pinar/atualizar compose |
| `get_mon_digests.sh` | idem, para a stack de monitoramento | pinar monitoramento |
| `inventario_hardware.sh` | **coletor** do inventário de hardware: DMI/SMBIOS + `lspci`/`lsusb` → Markdown na saída padrão; somente leitura, mascara série/UUID/asset tag (card: [`inventario-proxmox.md`](inventario-proxmox.md)) | roda no host que se quer inventariar (o `.ps1` chama por você) |
| `inventario-proxmox.ps1` | **Windows**: envia o coletor ao Proxmox (`root@192.168.15.221`), executa e grava `docs/architecture/INVENTARIO-HARDWARE-PROXMOX.md`; `-DryRun` mostra sem gravar (card: [`inventario-proxmox.md`](inventario-proxmox.md)) | precisa do fabricante/modelo de placa-mãe, CPU, GPU, USB e portas do **ferro** |

## Os quatro destrutivos

`drill_restore_clean.sh`, `verify_backup_restore.sh` e `cleanup_owui_*.py` **apagam coisas** —
no lab isso é pré-autorizado, mas sempre rode o `--dry-run`/leitura primeiro quando existir.
`verify_qdrant_upgrade.sh` só toca uma **cópia** do volume; ainda assim, prefira rodá-lo com o
lab parado. `rag_ingest.py --remover <sha256>` apaga um documento da base do OWUI — é o **único**
caminho de remoção: o worker nunca apaga sozinho.

## Regras

- **`verify` é somente leitura**: script de verificação não instala, não cria arquivo, não corrige
  permissão.
- Todo script sai com exit code honesto (`0` ok) e mensagem no `stderr` quando falha.
- `--dry-run` quando a ação é irreversível.
