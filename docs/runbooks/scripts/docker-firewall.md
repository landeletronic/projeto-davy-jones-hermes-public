# docker-firewall.sh — bloqueio real das portas publicadas pelo Docker

| | |
|---|---|
| Arquivo | `ops/bin/docker-firewall.sh` |
| Instalado como | `/usr/local/bin/docker-firewall.sh` |
| Unit | `ops/systemd/docker-firewall.service` (**`PartOf=docker.service`**) |
| Bloqueia | `6333` (Qdrant), `11434` (Ollama), `8642` (Hermes API) |
| Libera | 80/443/3001/9119 (seguem o caminho normal) |

## Por que existe

Porta publicada pelo Docker entra por `PREROUTING → FORWARD → DOCKER-USER` — **nunca pelo
INPUT do ufw**. Sem regra nessa cadeia, "fechei o firewall" não fecha nada. E a cadeia
`DOCKER-USER` é **recriada a cada restart do Docker**, por isso a unit reaplica no start.

## Rodar à mão

```bash
ssh davy-jones-hermes 'sudo /usr/local/bin/docker-firewall.sh'
ssh davy-jones-hermes 'sudo iptables -L DOCKER-USER -n --line-numbers'
```

Esperado: um `DROP` para cada uma das 3 portas, e o host continua acessando 8642 por
`127.0.0.1` (tráfego do host não passa por FORWARD).

## Se falhar

| Sintoma | Causa | Ação |
|---|---|---|
| `ERRO: cadeia DOCKER-USER ausente` | Docker parado | `systemctl start docker` |
| 6333/11434 acessível da LAN após reboot | unit sem `PartOf` / não habilitada | `systemctl enable --now docker-firewall` |
| `ufw allow 8642` "não resolveu" | ufw não governa porta do Docker | este script é quem manda |

## Reinstalar

```powershell
powershell -File ops\deploy\sync-to-host.ps1
```

O sync instala o script, a unit, faz `daemon-reload` e habilita/inicia o serviço.
