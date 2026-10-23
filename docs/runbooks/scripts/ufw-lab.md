# ufw-lab.sh — política de portas de INPUT (ufw)

| | |
|---|---|
| Arquivo | `ops/bin/ufw-lab.sh` |
| Instalado como | `/usr/local/bin/ufw-lab.sh` |
| Executado por | `sync-to-host.ps1` (idempotente) |
| Libera no INPUT | `22` SSH · `80` Nginx HTTP · `443` Nginx HTTPS · `3001` Grafana TLS · `9119` dashboard |

## Regra de ouro

**Nunca** `ufw reset`. O script garante as regras esperadas **uma a uma**; um reset apagaria
regras que não são do lab. A lista usa separador `|` justamente porque os rótulos têm espaço
("Nginx HTTP" não pode virar duas regras).

## O que ele NÃO governa

Portas **publicadas pelo Docker** (6333, 11434, 8642) — elas entram por FORWARD/`DOCKER-USER`.
Quem manda nelas é [`docker-firewall.sh`](docker-firewall.md). O script ainda **remove** a regra
antiga `8642/tcp ALLOW`, que dava a impressão falsa de que a API estava exposta.

## Rodar / verificar

```bash
ssh davy-jones-hermes 'sudo /usr/local/bin/ufw-lab.sh'
ssh davy-jones-hermes 'sudo ufw status numbered'
ssh davy-jones-hermes 'sudo ufw show added'
```

Esperado: habilitado/ativo, as 5 portas acima e **nenhuma** menção a 8642.

## Se falhar

| Sintoma | Causa | Ação |
|---|---|---|
| `ERROR: Bad port` | rótulo com espaço dividido errado | usar o separador `|` do script, nunca espaço |
| SSH bloqueado após mexer | política padrão `deny incoming` sem a regra 22 | console do host / `ufw allow 22/tcp` |
| 8642 "liberada" | regra velha de outra época | o script remove; rode de novo |

## Reinstalar

```powershell
powershell -File ops\deploy\sync-to-host.ps1
```
