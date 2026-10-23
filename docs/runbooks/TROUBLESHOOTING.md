# TROUBLESHOOTING — por sintoma

> Ordem de leitura: **o que o usuário viu** → causa provável → o que rodar. Se o sintoma não
> estiver aqui, comece pela triagem abaixo: ela resolve 8 de cada 10 casos.

## Triagem em 3 comandos

```bash
ssh davy-jones-hermes 'cd /home/usuario/hermes-architect && docker compose ps'
ssh davy-jones-hermes 'bash /home/usuario/hermes-architect/tests/verify_stack.sh'   # o oráculo
ssh davy-jones-hermes '/usr/local/bin/hermes-ci --quiet'                               # o mesmo, via CI
```

- Container `unhealthy` ou ausente → card do serviço em [`servicos/`](servicos/).
- Suíte com FAIL → a mensagem diz qual invariante quebrou; o número do item aponta a seção.
- Suíte verde e o usuário reclamando de UI → é sessão/navegador/certificado, não o lab.

## Não consigo abrir o chat

| Causa provável | Como confirmar | Ação |
|---|---|---|
| Host desligado | `ping 192.168.15.231` falha | ligar o host (não é IP novo) |
| nginx fora | `curl -sk -o /dev/null -w '%{http_code}' https://192.168.15.231/` = 000/502 | [`servicos/nginx.md`](servicos/nginx.md) |
| OWUI fora | `docker inspect -f '{{.State.Health.Status}}' open-webui` ≠ healthy | [`servicos/open-webui.md`](servicos/open-webui.md) |
| Aviso de certificado | navegador mostra "não seguro" | esperado (autoassinado); reimportar o `.crt` após renovação |
| `:3000` no navegador de outra máquina | a porta é **loopback** | usar `https://192.168.15.231/` |

## Abre o chat, mas a resposta falha

| Sintoma | Causa | Ação |
|---|---|---|
| 502 no envio | gateway `hermes-agent` fora | `curl -s localhost:8642/health`; [`servicos/hermes-agent.md`](servicos/hermes-agent.md) |
| `model not found` | modelo apagado/volume recriado | `docker exec ollama ollama list`; [`servicos/ollama.md`](servicos/ollama.md) |
| Primeira resposta demora 60–90 s | swap de modelo (Ollama serializa) | normal; `docker exec ollama ollama ps` |
| Resposta cortada / contexto pequeno | piso de 64k | conferir `num_ctx` e o modelo (`qwen3:4b-64k`) |
| Raciocínio aparecendo como texto | modelo escreveu fora das tags | `temperature: 0.3` no `config.yaml`; smoke de RAG detecta |

## A memória não grava (ou grava na pessoa errada)

| Sintoma | Causa | Ação |
|---|---|---|
| Conversa some do histórico | gateway reiniciou / sessão nova | conferir `X-Hermes-Session-Key` na conexão do OWUI |
| Memória com `user_id = hermes-user` | chamada **sem** o header de sessão | mandar `X-Hermes-Session-Key: <email>`; conferir na coleção |
| Memória duplicada | mem0 é ADD-only | `mem0-maintenance --dry-run` → rodar sem dry-run (03:00) |
| Qdrant sem coleção | volume recriado | primeiro `ADD` recria; [`servicos/qdrant.md`](servicos/qdrant.md) |

```bash
ssh davy-jones-hermes "curl -s localhost:6333/collections/mem0_memories | python3 -m json.tool | head -20"
```

## Upload/RAG não responde com citação

| Sintoma | Causa | Ação |
|---|---|---|
| Upload "conclui" e nada é indexado | Docling falhou (PDF escaneado sem OCR) | `docker logs --tail 50 docling` |
| Responde sem `[1]` | `rag.*` voltou ao default | `PersistentConfig`: ajustar na UI ou `tools/set_owui_rag_config.py` |
| Cita número que não existe na fonte | lastro perdido | o smoke `SMOKE_RAG=1` pega isso; revisar chunk/fonte |
| `knowledge_file` com órfãs | bug conhecido do OWUI 0.12.3 | `tools/cleanup_owui_leftovers.py` |

## Grafana / alertas

| Sintoma | Causa | Ação |
|---|---|---|
| Dashboard `hermes-lab` ausente | `monitoring/` ilegível pelo uid 472 | `chmod -R a+rX monitoring`; [`servicos/grafana.md`](servicos/grafana.md) |
| Senha do `.env` não entra | só vale no 1º boot | `grafana cli admin reset-admin-password` + restart |
| "usuário bloqueado" | 5 erros de login persistem | apagar `login_attempt` (receita no card do Grafana) |
| Alerta novo não aparece | rules não relidas | `docker kill -s HUP prometheus` |
| Alerta de backup disparado | artefato >48h | `hermes-backup`; ver [`scripts/backup_stack.md`](scripts/backup_stack.md) |
| Aviso de certificado no Windows | cert expira em <30 dias | renovar (`tools/make_tls_cert.sh --force --reload`) |

## Backup e restore

| Sintoma | Causa | Ação |
|---|---|---|
| `hermes_backup_last_success` velho | cron parado | `systemctl is-active cron`; `/etc/cron.d/hermes-backup` |
| Backup "sem `grafana.db`" | `docker run` sem `-i` não lê stdin | conferir o script; [`scripts/backup_stack.md`](scripts/backup_stack.md) |
| Snapshot antigo não restaura | geração diferente do Qdrant | usar backup **posterior** ao upgrade; [`servicos/qdrant.md`](servicos/qdrant.md) |
| `database disk image is malformed` no restore | `-wal` velho | semear o volume **antes** do 1º boot |

## CI vermelho

```bash
ssh davy-jones-hermes 'sudo cat /var/log/hermes-ci.log | tail -40'
ssh davy-jones-hermes 'bash /home/usuario/hermes-architect/tests/verify_stack.sh'
```

- **WARN** de estado do CI é auto-referente: depois de um run vermelho, rode de novo para zerar.
- **FALHOU e passou 2 minutos depois** → swap de modelo (CI varia 6 s ↔ 126 s); não é regressão.
- **Código novo não aparece no CI** → faltou `powershell -File ops\deploy\sync-to-host.ps1`: o
  cron executa a **cópia sincronizada**, não o repo do Windows.

## Host inacessível / disco cheio

| Sintoma | Ação |
|---|---|
| `ssh` não conecta | host provavelmente **desligado** (não é IP novo). Ligar e esperar o boot. |
| `No space left on device` | `df -h /`; rotação de log é `10 MB × 3` (AGENTS §4). Limpar `_legacy/` e backups antigos. |
| Docker não sobe containers | `systemctl status docker`; daemon.json inválido quebra o start. |
| Porta 6333/11434/8642 acessível da LAN | cadeia `DOCKER-USER` caiu: `sudo systemctl restart docker-firewall` |

## Quando nada bate

1. `docker compose ps` — algum `unhealthy`?
2. `docker logs --tail 100 <container>` — a primeira linha de erro, não a última.
3. Suíte com `--verbose` (se aplicável) ou seção por seção.
4. Última mudança: `git log --oneline -5` no repo e `ls -lt ~/backups | head` no host.
5. Último recurso no lab (destrutivo, mas pré-autorizado): `tools/drill_restore_clean.sh` prova que
   o backup restaura numa máquina vazia **antes** de você mexer em produção.
