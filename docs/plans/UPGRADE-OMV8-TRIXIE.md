# Upgrade do host OMV: Debian 12 (bookworm) → Debian 13 (trixie) com OMV 7 → OMV 8 "Synchrony"

**Status:** **executado em 2026-10-21** (15:08–16:15) — Debian **13.7 trixie** / OMV
**8.5.12-1**. O plano original ficou como registro; o resultado medido, os desvios e os achados
estão na §0.
**Host alvo:** `openmediavault` (`100.68.139.36` via Tailscale, `192.168.15.11` na LAN).
**Medição base:** 2026-10-21, ~08:20–12:40, sessão por SSH com chave.
**Classificação das ações (§6.1 do `AGENTS.md`):** todo comando marcado como READ, WRITE ou
DESTRUCTIVE. As fases 1, 2, 4, 5 e 8 são WRITE; a fase 5 é **DESTRUCTIVE**.

> **Regra deste plano:** nenhuma fase começa sem o critério de aceite da anterior cumprido.
> O upgrade é **só para frente** — a fase 6 (rollback) explica por quê.

## 0. Execução (2026-10-21) — resultado medido

### 0.1 Antes → depois

| Item | Antes (§2) | Depois |
|---|---|---|
| Debian | 12.15 bookworm | **13.7 trixie** |
| OMV | 7.7.24-7 | **8.5.12-1** (`synchrony`) |
| Kernel | 6.12.95+deb12 (backports) | **6.12.113+deb13** (security) |
| PHP | `php8.2-fpm` | **`php8.4-fpm 8.4.24`** |
| Plugins (10) | 7.x | **10/10 em 8.x** (compose 8.2.3, cputemp 8.2.2, cterm 8.0.5, diskstats 8.0.2-1, iperf3 8.0, omvextrasorg 8.0.4, sharerootfs 8.0.1-1, timeshift 8.1.7, usbbackup 8.0.2-1, wol 8.0) |
| Docker / containerd / compose | 29.9.2 / 2.4.2 / 5.6.1 (`deb12`) | **`~debian.13~trixie`** |
| Samba | 4.17 (`deb12`) | **4.22.11+deb13u1** |
| Tailscale | 1.104.2 (suite bookworm) | 1.104.2 (suite trixie) — agora **direto**, sem DERP |
| Webmin | 2.670 | 2.670 |
| CasaOS | 6 serviços | **6 serviços** (mantido) |
| Portainer | up | up (`restart=always`, voltou sozinho nos dois reboots) |
| `/dados` | 30 entradas | **30 entradas** |
| Shares | 6 | **6** (`docker`, `dados`, `macos`, `eletronica`, `jdownloader`, `public`) |
| Disco raiz | 1,1 TB usados / 185 GB livres | **igual** |
| `dpkg -l \| grep +deb12` | — | **0** |
| `apt-get -s full-upgrade` | — | **0 pendentes** |
| Units falhas | 0 | **0** |
| UI OMV `:11080` / Webmin `:10000` / CasaOS `:81` | 200 / — / — | **200 / 200 / 200** |

### 0.2 O que rodou

1. **Fases 0–2** — estado congelado (`dpkg --audit` e `systemctl --failed` vazios, sem holds);
   `pre-omv8-config-2026-10-21-1508.tgz` (235 arquivos) em `/root` **e** no btrfs; 6 inventários
   `pre-omv8-*.txt`; `unattended-upgrades`, `daily-shutdown.timer` (o desligamento das 23:00) e
   os dois `apt-daily*` desativados; `tmux 3.3a` instalado.
2. **Fase 3 (ensaio)** — **831 `Inst` / 53 `Remv`**. As 53 remoções são só a transição `t64` do
   trixie (`libssl3`, `libglib2.0-0`, `libcurl4`, `libnettle8`, …) e `php8.2-*`; **nada** da lista
   proibida da §8.5; **10/10** plugins com build em `synchrony`; `openmediavault 8.5.12-1`.
3. **Fase 4** — `tailscale.list` de `bookworm` → `trixie`.
4. **Fase 5** — o script oficial **não** foi chamado: ele abre `whiptail` em `/dev/tty` e, sem TTY,
   sai sem fazer nada. Foi executada a **mesma sequência** dele — `omv-upgrade` → `pre.d` →
   `apt-get dist-upgrade` (`--force-confold --no-install-recommends --auto-remove`) → `post.d` →
   `omv-upgrade` — em `setsid nohup`, com log em `/root/omv8-upgrade.log`.
   **`dist-upgrade rc=0` em 39 min**; o `omv-upgrade` final: `0 upgraded, 0 newly installed,
   0 to remove`.
5. **Fase 6** — reboot; voltou em ~1 min, chave SSH intacta, zero units falhas.
6. **Fase 7** — verificação completa (§0.1).
7. **Fase 8** — security repo recriado pelo state da OMV, `full-upgrade` de 61 pacotes
   (security + firmware do backports), purga dos restos `deb12`, segundo reboot (kernel
   6.12.113) e timers religados.

### 0.3 Desvios conscientes do plano

| Decisão | Por quê |
|---|---|
| **CasaOS mantido** (o plano recomendava remover) | A autorização foi para *atualizar o host*; desinstalar um app não estava no escopo. Sobreviveu: 6 serviços ativos e `:81` em 200. |
| **`omv-release-upgrade` replicado, não chamado** | Sem TTY o `whiptail` falha e o script encerra. A sequência executada é a do próprio script (`/root/omv8-upgrade.sh`), com log integral. |
| **Kernel fixado na série 6.12** | O backports do OMV 8 oferece `7.2.9-1~bpo13+1` para o meta `linux-image-amd64`. Trocar de *major* na mesma janela do dist-upgrade, num host headless, é risco sem retorno. Um pin `90-kernel-seguro.pref` (prioridade 100 para `linux-image-*`/`linux-headers-*`/`linux-base` do backports) manteve a série **6.12** e trouxe o patch de **security 6.12.113**. |

### 0.4 Achados (o que o plano não previa)

1. **Security repo:** o risco #8 se confirmou — o `pre.d` apaga `openmediavault-os-security.list`
   e **nada** o recria ao fim do `dist-upgrade`. Quem recria é o state
   `omv-salt deploy run apt` (`/srv/salt/omv/deploy/apt/10default.sls`,
   `configure_apt_sources_list_os_security`), que o `post.d` só executa *depois* do upgrade.
   Rodar o state recriou o arquivo como `trixie-security` (prioridade 500). **Sem esse passo o
   host ficaria sem updates de segurança.**
2. **Locale pt-BR engana o ensaio:** `apt-cache policy` imprime `Candidato:`, não `Candidate:`.
   A receita original da §8.6 devolvia **10 linhas vazias** — falso alarme de "nenhum plugin tem
   build OMV 8". Corrigido na §8.6 com `LC_ALL=C`.
3. **Backports do kernel reativados pelo OMV 8:** o state recria
   `openmediavault-kernel-backports` (list + pin 500). Sem o pin da §0.3, o próximo `omv-upgrade`
   instala o **7.2.9**.
4. **Deriva no banco de rede da OMV (pré-existente):** `conf.system.network.interface` diz
   `enp2s0 static 192.168.1.11 gw 192.168.1.254`, enquanto o netplan aplicado — **byte a byte
   igual ao backup da fase 1** — diz `192.168.15.11/24 gw 192.168.15.1`. Não foi o upgrade: o
   `config.xml` difere do backup só por campos novos de schema (`notificationschedule`,
   `cpufreqgovernor`, `timemachinemaxsize`, `macoscompat`). **Risco:** *Rede → Aplicar* na UI
   regera o netplan a partir do banco e move o host para `192.168.1.11`.
5. **A LAN do host está em outro segmento L2 (pré-existente):** do Windows (`192.168.15.38`) o
   gateway `.1` é `84:0b:bb:13:19:18`; o host vê o `.1` como `d8:c6:78:a0:97:98`. O host alcança
   **só** o `.1` (ping em `.38` e `.231` falha; `ip neigh` marca `.38` como `FAILED`), não há
   `ufw` nem regra de `INPUT` bloqueando, e o netplan não mudou. São **dois roteadores com a mesma
   sub-rede**: o `192.168.15.11` nunca foi alcançável a partir deste PC — todo o acesso desta
   sessão foi por **Tailscale** (UI 200 e SMB listando `dados` pelo IP `100.68.139.36`).

### 0.5 Pendências e recomendações (não bloqueiam)

- **`192.168.1.11` no banco da OMV:** alinhar com a realidade (`omv-confdbadm update
  conf.system.network.interface <uuid> '{...}'` com `192.168.15.11/24` e gw `192.168.15.1`).
  Enquanto isso, **não** clicar em *Rede → Aplicar*.
- **Kernel 7.2 do backports:** quando houver janela com acesso físico, remover
  `/etc/apt/preferences.d/90-kernel-seguro.pref` e deixar o `omv-upgrade` instalar — com um
  pendrive live à mão.
- **Segmento L2:** se o `192.168.15.11` precisar ser alcançável na LAN (SMB/NFS/UI), mover o cabo
  para o mesmo switch/roteador do resto da rede ou corrigir o isolamento do AP. Não é regressão
  do upgrade — mas é a razão de tudo depender do Tailscale hoje.
- **CasaOS:** sem manutenção desde jun/2024 e agora sobre trixie; decidir entre remover ou
  congelar. Os 6 serviços subiram, mas não há garantia de suporte.

### 0.6 Artefatos deixados no host

| Caminho | O que é |
|---|---|
| `/root/pre-omv8-config-2026-10-21-1508.tgz` | config pré-upgrade (235 arquivos); cópia no btrfs |
| `/root/pre-omv8-*.txt` | 6 inventários (dpkg, portas, rede, tailscale, serviços, docker) |
| `/root/omv8-upgrade.sh` · `/root/omv8-upgrade.log` | sequência executada e transcrição completa |
| `/root/sim-trixie.txt` | saída do ensaio (831 `Inst` / 53 `Remv`) |
| `/tmp/omv8-sim/` | índices do ensaio (pode apagar) |
| `/etc/apt/preferences.d/90-kernel-seguro.pref` | pin do kernel na série 6.12 |
| `config.xml.7x.bak` | cópia automática do `pre.d/90-backup-config-db` |


## 1. Sumário executivo

Dá para migrar, e o caminho é **oficial**: o pacote da OMV 7 já embarca o script
`omv-release-upgrade` e, neste host, ele aponta para o alvo **8 / Synchrony** (base trixie).
O script cuida do essencial (repos OMV, repo do Docker, pins do omv-extras, `config.xml`), mas
**não** cobre três coisas que existem aqui: o repo do **Tailscale**, o **CasaOS** (fora do apt) e
o fato de **1,1 TB de dados morarem no sistema de arquivos raiz** (plugin `sharerootfs`), sem
backup e sem snapshot de sistema. São esses três pontos — não o Debian — que decidem o sucesso.

## 2. Estado medido (o que existe hoje)

| Item | Valor medido |
|---|---|
| Base | Debian 12.15 bookworm / `base-files 12.4+deb12u15` |
| OMV | `openmediavault 7.7.24-7`, `openmediavault-engined` active |
| Kernel | `6.12.95+deb12-amd64` (pacote `linux-image-amd64 6.12.95-1~bpo12+1`, **backports**) |
| Kernel reserva | `6.12.94+deb12-amd64` em `/boot`, `vmlinuz.old` aponta para ele |
| Plugins (10) | compose 7.6.13, cputemp 7.0.2, cterm 7.8.7, diskstats 7.0.4-1, iperf3 7.0.1, omvextrasorg 7.0.6, sharerootfs 7.0-1, timeshift 7.0.1, usbbackup 7.1.3-1, wol 7.0.2 |
| Container | `portainer` (`portainer-ce:2.26.1`), Docker `29.9.2`, containerd `2.4.2`, cgroup v2, driver `overlay2` |
| `/var/lib/docker` | 1,1 GB |
| Disco raiz | `sda1` ext4, 1,4 TB, **1,1 TB usados, 185 GB livres (86%)** |
| Disco de dados | `sdb` btrfs, 1,9 TB, 986 GB usados, 877 GB livres → `/srv/dev-disk-by-uuid-c8a8f050-…` |
| RAID | nenhum (`/proc/mdstat` vazio) |
| **Dados na raiz** | `/dados`, `/DATA`, `/docker`, `/eletronica`, `/macos`, `/export` no `sda1` (share via `sharerootfs`) |
| Rede | `netplan` + `systemd-networkd`, `enp2s0` (Broadcom `tg3`), LAN `192.168.15.11/24` |
| Tailscale | 1.104.2, repo suite **bookworm**, conexão via `DERP(sao)` (sem rota direta) |
| Webmin | 2.670, repo suite `stable` (genérica) |
| CasaOS | 6 serviços ativos, binários de jun/2024 em `/usr/bin/casaos*`, **fora do apt** |
| PHP | `php8.2-fpm 8.2.34`, `php-fpm 2:8.2+93` |
| usrmerge | **já feito** (`/lib -> usr/lib`, `/bin -> usr/bin`) |
| GRUB | `GRUB_TIMEOUT=5` |
| `unattended-upgrades` | `enabled` (roda ~07:0x) |
| TimeShift | instalado, `Device: Not Selected`, **nenhum snapshot** |
| Janela de energia | boot 07:00, shutdown 23:00, todos os dias (`last -x`) |
| Outros serviços | `smbd` (445/139), `nfs-server` (2049), `rsync` (873), `iperf3` (5201), nginx OMV (**11080, HTTP puro**), `rpcbind` (111) |

### 2.1 Repositórios ativos (todos terão de mudar de suite)

| Arquivo | Suite hoje | Suite alvo |
|---|---|---|
| `sources.list` | `bookworm`, `bookworm-updates` | `trixie`, `trixie-updates` |
| `openmediavault.list` | `sandworm` | `synchrony` |
| `openmediavault-os-security.list` | `bookworm-security` | **removido pelo script** — recriar como `trixie-security` |
| `openmediavault-kernel-backports.list` | `bookworm-backports` | **removido pelo script** (trixie já traz 6.12) |
| `omvdocker.sources` | `bookworm` | `trixie` (script cuida) |
| `omvextras.sources` | `sandworm` | `synchrony` (script cuida) |
| `tailscale.list` | `bookworm` | `trixie` (**script não cuida**) |
| `webmin.list` | `stable` | `stable` (não muda) |
| `openmediavault-local.list` | `file:/var/cache/openmediavault/archives` | não muda |

## 3. Como se chega ao host

```powershell
# do Windows; chave ed25519 em ~/.ssh/openmediavault, alias em ~/.ssh/config
ssh openmediavault            # root por chave, sem senha
ssh openmediavault 'comando'  # comando único, sem shell interativo
ssh -t openmediavault '...'   # -t é obrigatório para qualquer coisa com whiptail/tmux
```

## 4. O que o caminho oficial faz (lido do próprio host)

`/usr/sbin/omv-release-upgrade` (existe, 4.083 bytes, dez/2025):

```sh
OMV_UPGRADE_RELEASEVERSION=${OMV_UPGRADE_RELEASEVERSION:-"8"}
OMV_UPGRADE_RELEASENAME=${OMV_UPGRADE_RELEASENAME:-"Synchrony"}
...
OMV_UPGRADE_DEBIAN_RELEASENAME_CURRENT="bookworm"
OMV_UPGRADE_DEBIAN_RELEASENAME_NEXT="trixie"
```

Fluxo: *copia os próprios scripts para `/var/tmp` → `omv-upgrade` → `run-parts pre.d` →
`apt-get dist-upgrade` (`--force-confold`, `--no-install-recommends`) → `run-parts post.d` →
`omv-upgrade || :` → limpa `/var/tmp` → "reinicie"*.

| Script | Efeito | Nota neste host |
|---|---|---|
| `pre.d/05-install-usrmerge` | instala `usrmerge` | **no-op** (já convertido) |
| `pre.d/10-apt-purge-local-archive` | limpa `.deb` de `/var/cache/openmediavault/archives` e regenera `Packages` | inofensivo |
| `pre.d/10-disable-omv-mkaptidx` | diverte `omv-mkaptidx` | evita quebra no meio do dist-upgrade |
| `pre.d/10-stop-cron` / `-anacron` / `-stop-monit` | param os três | religados no `post.d` |
| `pre.d/20-apt-remove-kernel-backports` | apaga `.list` e `.pref` dos backports do kernel | resolve o pin do kernel 6.12 |
| `pre.d/20-apt-update-source-list` | `sed bookworm→trixie` em `sources.list`; reescreve `openmediavault.list` para `synchrony`; **apaga** `openmediavault-os-security.list`; comenta security/backports | ⚠️ deixa o host sem repo de security até o `post.d`/pacote novo |
| `pre.d/20-omvextras-sources-list` | Docker `bookworm→trixie`; omv-extras `bookworm→trixie` + `sandworm→synchrony`; pins idem; armbian/raspi/pve se existirem | ✅ cobre Docker e omv-extras |
| `pre.d/90-backup-config-db` | copia `config.xml` → `config.xml.7x.bak` (só se não existir) | ✅ config OMV salva |
| `pre.d/99-saltstack-issue-68460` | workaround do Salt (`/opt/saltstack/salt/bin/python3`) | — |
| `post.d/10-cleanup-root-profile` | remove `mesg n` de `/root/.profile` | — |
| `post.d/10-enable-omv-mkaptidx` | desfaz o divert | — |
| `post.d/20-start-*` | religa cron, anacron, monit | — |
| `post.d/30-remove-cpufrequtils` | mascara e purga `cpufrequtils` | **esperado** |
| `post.d/40-move-to-writecache` | se houver `openmediavault-flashmemory`, migra para `openmediavault-writecache` | não instalado |
| `post.d/50-set-dirty-*` | marca `nginx`, `phpfpm`, `cpupower` como *dirty* | é o que regera a UI |
| `post.d/70-deploy-config` | `omv-salt deploy run --append-dirty` | regera nginx/php/samba/nfs |
| `post.d/80-apt-autoremove`, `90-apt-clean` | `autoremove` + `clean` | **atenção**: `autoremove` pode levar PHP 8.2 |
| `post.d/95-apt-index` | `omv-mkaptidx` | — |
| `post.d/99-reboot-required` + `99-restart-omv-engined` | marca reboot e reinicia o engined | reboot final obrigatório |

## 5. Lacunas: o que o script **não** resolve

| # | Lacuna | Estado medido | Risco |
|---|---|---|---|
| 1 | Repo do **Tailscale** | `tailscale.list` → suite `bookworm` | Médio — nenhum `pre.d` toca nele |
| 2 | **CasaOS** | 6 serviços, binários jun/2024, fora do apt, gateway na `:81` | **Alto** — sem plano de upgrade, sem apt |
| 3 | **1,1 TB na raiz** via `sharerootfs` | `sda1` 86%, 185 GB livres | **Alto** para rollback |
| 4 | **Sem snapshot de sistema** | TimeShift sem device e sem snapshot | **Alto** |
| 5 | `unattended-upgrades` ativo | `enabled` | Médio |
| 6 | **Janela 07:00–23:00** | `last -x` diário | Médio/Alto |
| 7 | **Rede headless** | netplan + `systemd-networkd` + `tg3` | **Alto** se quebrar |
| 8 | Security repo apagado no `pre.d` | `openmediavault-os-security.list` é removido | Médio — conferir no fim |
| 9 | PHP 8.2 → 8.4 | `php8.2-fpm` instalado | Médio — `post.d` regera |
| 10 | UI em `:11080` HTTP | nginx `*:11080` | Baixo — conferir porta pós-upgrade |
| 11 | Webmin fora do alvo do script | suite `stable` | Baixo — provável restart manual |

## 6. Decisões bloqueantes (dependem do dono do host)

1. **CasaOS:** remover antes (`/usr/bin/casaos-uninstall`) ou manter sem suporte?
   Recomendação: **remover** — 2 anos parado, duplica a função da OMV, ocupa a `:81` e é a maior
   incerteza do upgrade.
2. **Acesso físico/console:** existe teclado+monitor (ou IPMI/KVM)? Sem isso, falha de rede =
   esperar alguém ir até a máquina.
3. **Backup externo:** existe destino fora do host para o que não couber nos 877 GB livres do
   `sdb`? Sem isso não há rollback.
4. **Janela:** reservar uma manhã (07:30–12:00) com o dono disponível; o host desliga às 23:00.

> **Como foi decidido na execução (2026-10-21):** CasaOS **mantido** (fora do escopo da
> autorização); janela usada das **15:08 às 16:15** com `daily-shutdown.timer` neutralizado
> (religado no fim); não havia backup externo — o upgrade seguiu **sem rollback de bloco**, com
> backup de config + inventário (§0.6) como única rede, e o dono autorizou explicitamente seguir
> sem perguntas.

## 7. Fases

### Fase 0 — Congelar o "antes" (READ, 10 min)

```sh
apt-mark showhold                       # nada pode estar em hold
dpkg --audit                            # nenhum pacote meio-instalado
apt-get -s dist-upgrade | tail -20      # o que falta hoje no bookworm
lsblk -f; mount | grep ' / '
readlink -f /lib                        # esperado: /usr/lib
systemctl --failed
docker inspect portainer --format '{{.HostConfig.RestartPolicy.Name}}'
systemctl list-units --type=service --all | grep -e casaos -e smbd -e nfs | head
```
**Aceite:** `dpkg --audit` vazio, `systemctl --failed` vazio, política de restart do Portainer
anotada (para saber se ele volta sozinho depois do reboot).

### Fase 1 — Backup antes de qualquer WRITE (WRITE, 30–90 min)

```sh
# 1) config: cobre o que dói se der errado
tar czf /srv/dev-disk-by-uuid-c8a8f050-3b16-4cb3-9fd4-2e27a7e2fd92/pre-omv8-config-$(date +%F).tgz \
    /etc/openmediavault /etc/apt /etc/network /etc/netplan /etc/fstab /etc/ssh \
    /etc/samba /etc/exports /etc/cron.d /var/lib/openmediavault /etc/default/grub

# 2) inventário auditável
dpkg -l > /root/pre-omv8-dpkg.txt
ss -tlnp > /root/pre-omv8-ports.txt
ip -br a > /root/pre-omv8-net.txt
tailscale status > /root/pre-omv8-tailscale.txt 2>/dev/null
systemctl list-units --type=service --state=running > /root/pre-omv8-services.txt
docker ps > /root/pre-omv8-docker.txt

# 3) dados: priorizar o insubstituível (1,1 TB não cabe nos 877 GB livres)
rsync -aHAX --info=progress2 --dry-run /dados/ /srv/<btrfs>/backup-pre-omv8/dados/
```
**Aceite:** `tar tzf` lista os arquivos; `rsync --dry-run` não acusa erro; os 6 arquivos de
inventário existem em `/root`.
**Rollback:** apagar os arquivos criados.

### Fase 2 — Neutralizar o que atrapalha (WRITE, 10 min)

```sh
systemctl stop unattended-upgrades
systemctl disable unattended-upgrades
apt-get install -y tmux                 # sessão persistente: NÃO é opcional
# descobrir o agendador do desligamento das 23:00 e desativá-lo na janela
grep -ri -e shutdown -e poweroff /etc/cron.d/ /etc/systemd/system/ 2>/dev/null
systemctl list-timers --all | grep -i -e shutdown -e poweroff
```
**Aceite:** `systemctl is-enabled unattended-upgrades` = `disabled`; `tmux -V` responde;
identificado (e desativado temporariamente) o que desliga às 23:00.

### Fase 3 — Ensaiar sem executar (detalhada na §8)

**Aceite:** o arquivo `/root/sim-trixie.txt` existe, mostra o `openmediavault` **8.x** e os
**10/10** plugins disponíveis na suite `synchrony`, e a lista de `Remv` não contém nenhum pacote
da lista "proibida" da §8.5. **Se um critério falhar, o upgrade não começa.**

### Fase 4 — Corrigir o que o script não corrige (WRITE, 5 min)

```sh
# Tailscale: o pre.d não cuida deste arquivo
sed -i 's/ bookworm / trixie /' /etc/apt/sources.list.d/tailscale.list
grep -c trixie /etc/apt/sources.list.d/tailscale.list   # esperado: 1
```
**Decisão CasaOS:** se remover, é **agora** (`/usr/bin/casaos-uninstall`), com o Portainer
decidido (ele é container e sobrevive ao upgrade do Docker).
**Aceite:** `tailscale.list` com `trixie`; se removeu o CasaOS, `systemctl list-units | grep -c
casaos` = 0.

### Fase 5 — Executar o upgrade oficial (DESTRUCTIVE, 60–120 min)

```sh
tmux new -s omv8
/usr/sbin/omv-release-upgrade        # whiptail: responder "Yes"
# se a sessão SSH cair:  tmux attach -t omv8    (o upgrade continua rodando)
```
**Aceite durante:** o `apt` não pede interação (o script passa `--force-confold`).
**Se travar:** `dpkg --configure -a` e `apt-get -f install`, seguindo **para frente**.
**Aviso:** esta é a única fase sem rollback barato neste host. Ver §10.

### Fase 6 — Reboot e primeiros 5 minutos (10 min)

```sh
reboot
# depois
uptime; cat /etc/debian_version; grep VERSION_ID /etc/os-release
systemctl --failed
ssh openmediavault 'echo chave-ok'     # do Windows: a chave tem de continuar valendo
```
**Aceite:** `VERSION_ID="13"`, `VERSION_CODENAME=trixie`, `systemctl --failed` vazio e SSH por
chave funcionando. Falha na chave = cenário de console físico.

### Fase 7 — Verificar serviços (READ, 30 min)

```sh
ss -tlnp | grep -E ':(22|11080|445|139|2049|873|10000|9443)\b'
systemctl is-active openmediavault-engined nginx php8.4-fpm smbd nfs-server webmin tailscaled docker
curl -sI http://127.0.0.1:11080/ | head -1
docker ps
tailscale status
ls /dados /DATA /eletronica > /dev/null && echo DADOS-OK
omv-confdbadm read conf.system.sharedfolder | head    # shares continuam definidos
showmount -e localhost; smbclient -L localhost -N 2>&1 | head
```
**Aceite:** mesma lista de portas da §2 (menos `:81` se o CasaOS saiu), UI respondendo, shares
listados, **e `/dados` intacto**.

### Fase 8 — Fechar (WRITE, 20 min)

```sh
apt-cache policy | grep -e trixie -e security    # conferir repo de security presente
apt-get update && apt-get -y full-upgrade
apt-get install -y openmediavault-usbbackup      # religar plugin que ficou fora, se for o caso
systemctl restart webmin
systemctl enable --now unattended-upgrades
tailscale version                                 # confirmar build trixie
dpkg -l | grep '+deb12' | wc -l                   # esperado: 0
```
**Aceite:** `trixie-security` nos repositórios; `dpkg -l` sem sufixo `+deb12`; plugins ativos.

## 8. Fase 3 em detalhe — o ensaio

### 8.1 Objetivo

Saber, **antes** de tocar em qualquer coisa, exatamente o que o `dist-upgrade` faria:
quantos pacotes instala, quantos remove, quanto baixa, e se `openmediavault 8.x` e os 10 plugins
existem na suite `synchrony`. O ensaio não substitui o backup — ele substitui o *achismo*.

### 8.2 Por que o ensaio precisa imitar o estado **depois** do `pre.d`

O `pre.d` **deleta** `openmediavault-os-security.list` e `openmediavault-kernel-backports.list`
antes de rodar o `dist-upgrade`. Se o ensaio usar um conjunto de repo "ideal" (com security), ele
mente: mostraria atualizações que não existirão na hora. O ensaio abaixo reproduz a lista **como
ela estará no instante do `dist-upgrade`**: trixie + trixie-updates, **sem** security e **sem**
backports, com os repositórios de terceiros nas suites novas.

### 8.3 Receita (monta tudo em `/tmp`, não altera fonte real)

```sh
mkdir -p /tmp/omv8-sim/parts /tmp/omv8-sim/lists/partial /tmp/omv8-sim/archives/partial

# --- lista principal: cópia da real, com a mesma edição que o pre.d faz ---
cp /etc/apt/sources.list /tmp/omv8-sim/trixie.list
sed -i 's/bookworm/trixie/g'                             /tmp/omv8-sim/trixie.list
sed -i -e '/security\.debian\.org/d' -e '/backports/d'    /tmp/omv8-sim/trixie.list

# --- repositórios de terceiros, já nas suites de destino ---
cp /etc/apt/sources.list.d/omvdocker.sources    /tmp/omv8-sim/parts/
cp /etc/apt/sources.list.d/tailscale.list       /tmp/omv8-sim/parts/
cp /etc/apt/sources.list.d/webmin.list          /tmp/omv8-sim/parts/
cp /etc/apt/sources.list.d/openmediavault.list  /tmp/omv8-sim/parts/
cp /etc/apt/sources.list.d/omvextras.sources    /tmp/omv8-sim/parts/
sed -i 's/bookworm/trixie/g'    /tmp/omv8-sim/parts/omvdocker.sources
sed -i 's/ bookworm / trixie /' /tmp/omv8-sim/parts/tailscale.list
sed -i 's/sandworm/synchrony/g' /tmp/omv8-sim/parts/openmediavault.list
sed -i -e 's/bookworm/trixie/g' -e 's/sandworm/synchrony/g' /tmp/omv8-sim/parts/omvextras.sources

# --- índices SÓ neste diretório: não polui /var/lib/apt/lists ---
SIM="-o Dir::Etc::sourcelist=/tmp/omv8-sim/trixie.list \
     -o Dir::Etc::sourceparts=/tmp/omv8-sim/parts \
     -o Dir::State::Lists=/tmp/omv8-sim/lists \
     -o Dir::Cache::archives=/tmp/omv8-sim/archives"
apt-get $SIM update
apt-get $SIM -s dist-upgrade | tee /root/sim-trixie.txt
```

> `Dir::State::Lists` aponta para `/tmp` de propósito: o `update` do ensaio **não** mistura os
> índices do trixie com os do bookworm usados pela produção. `Dir::State::status` continua sendo
> o `/var/lib/dpkg/status` real — por isso a simulação enxerga o host de verdade.

### 8.4 Como ler a saída

```sh
grep -c '^Inst' /root/sim-trixie.txt     # quantos instala/atualiza
grep -c '^Remv' /root/sim-trixie.txt     # quantos REMOVE  ← o número que importa
grep '^Remv' /root/sim-trixie.txt
grep -E 'Need to get|After this operation' /root/sim-trixie.txt
```

| Pergunta | Onde olhar | Resposta saudável |
|---|---|---|
| A OMV 8 existe no repo? | `apt-cache policy openmediavault $SIM` | `Candidate: 8.` e origem `synchrony` |
| Os 10 plugins têm build novo? | laço da §8.6 | 10/10 com versão `synchrony` |
| O que seria removido? | `grep '^Remv'` | **nada** da lista proibida da §8.5 |
| Quanto baixa? | `Need to get` | < 185 GB livres (folga enorme) |
| O PHP 8.4 entra? | `grep -i php` no `Inst` | `php8.4-*` instalados; `php8.2-*` removidos é esperado |
| O kernel troca? | `grep -i 'linux-image'` | sim, para o 6.12 do trixie — esperado |

### 8.5 Lista proibida (se aparecer em `Remv`, o upgrade para)

`openmediavault` · `openssh-server` · `systemd` · `netplan.io` · `grub-pc`/`grub-common` ·
`docker-ce` · `tailscale` · `samba`/`smbd` · `nfs-kernel-server` · `sudo` · `libc6` ·
`linux-image-amd64` (sem substituto) · `rsync` · `webmin` · qualquer `people`/dados — e,
principalmente, **nada** que resolva um caminho dentro de `/dados`, `/DATA`, `/eletronica`,
`/macos`, `/export` (o apt não toca nessas árvores; se aparecer algo ali, é sinal de que um
pacote "adotou" o diretório e o plano tem de parar).

### 8.6 Checagem dos 10 plugins

```sh
export LC_ALL=C   # sem isto, apt imprime "Candidato:" e o filtro devolve vazio
for p in openmediavault-compose openmediavault-cputemp openmediavault-cterm \
         openmediavault-diskstats openmediavault-iperf3 openmediavault-omvextrasorg \
         openmediavault-sharerootfs openmediavault-timeshift openmediavault-usbbackup \
         openmediavault-wol; do
  printf '%-34s %s\n' "$p" "$(apt-cache policy $SIM $p | awk '/Candidate:/{print $2}')"
done | tee /root/sim-plugins.txt
```

> **Armadilha medida em 2026-10-21:** o host está em **pt-BR**, então `apt-cache policy` escreve
> `Candidato:` e `Instalado:`. Sem `LC_ALL=C`, o `awk '/Candidate:/'` casa com nada e o laço
> imprime **dez linhas vazias** — que parecem "nenhum plugin tem build OMV 8". Foi exatamente o
> falso alarme que quase abortou o upgrade; a checagem correta devolveu 10/10 (`compose 8.2.3`,
> `cputemp 8.2.2`, `cterm 8.0.5`, `diskstats 8.0.2-1`, `iperf3 8.0`, `omvextrasorg 8.0.4`,
> `sharerootfs 8.0.1-1`, `timeshift 8.1.7`, `usbbackup 8.0.2-1`, `wol 8.0`).

**Aceite:** as 10 linhas com `8.x` (ou, no mínimo, versão existente na suite `synchrony`).
**Se um plugin não existir para OMV 8:** `apt-get purge` nele **antes** da fase 5, ou o
`dist-upgrade` corre o risco de derrubar o pacote `openmediavault` inteiro.
Se um plugin só existir em `synchrony-proposed`, há a opção de descomentar o repo *proposed* no
`openmediavault.list` — decisão consciente, com o custo de entrar em teste.

### 8.7 Limpeza do ensaio

```sh
rm -rf /tmp/omv8-sim            # nada fora de /tmp e /root/sim-* foi tocado
```
**Aceite:** `/tmp/omv8-sim` ausente; `apt-get -s dist-upgrade` sem os `-o` volta a mostrar a
realidade do bookworm (prova de que a produção não foi afetada).

### 8.8 O que o ensaio **não** prova

- Não prova que o `post.d` regera nginx/PHP corretamente (só o upgrade real faz isso).
- Não prova que o CasaOS sobrevive (ele nem entra na conta do apt).
- Não prova que a rede volta (netplan é pacote, verificação só no reboot real).
- Não prova compatibilidade de dados: `config.xml` e os shares ficam fora da conta do apt.

## 9. Riscos por impacto

| Risco | Prob. | Impacto | Mitigação |
|---|---|---|---|
| Rede não volta (netplan/systemd-networkd/`tg3`) | Média | Crítico | console físico à mão; `tmux`; saber reconfigurar `enp2s0` pelo console |
| Plugin OMV 7 sem build OMV 8 derruba `openmediavault` | Média | Alto | §8.6 antes de qualquer coisa |
| CasaOS quebra e polui portas/logs | Alta | Médio | remover na fase 4 |
| Tailscale permanece em build bookworm | Alta se não corrigir | Baixo | fase 4 |
| Security repo ausente após o `pre.d` | Alta | Médio | conferir na fase 8 |
| `autoremove` do `post.d` leva pacote útil | Média | Médio | comparar lista de remoção do ensaio com o log do `dist-upgrade` |
| Sem rollback real | **Certa** | **Crítico** | backup externo de `sda1` ou aceitar "só para frente" |
| Janela das 23:00 corta o processo | Média | Alto | janela matinal + desativar o agendador |
| SSH cai durante a fase 5 | Baixa | Alto | `tmux` + chave já provada + console |

## 10. Rollback: o que é e o que não é possível

| Cenário | O que dá para fazer |
|---|---|
| Erro **antes** da fase 5 | Reverter cada WRITE: religar `unattended-upgrades`, restaurar `tailscale.list` do backup da fase 1 |
| Erro **durante** o `dist-upgrade` | Só para frente: `dpkg --configure -a`, `apt-get -f install` |
| Erro **depois** do reboot | Console físico; reverter `config.xml` pelo `.7x.bak` criado pelo próprio script |
| Voltar a OMV 7 / Debian 12 | **Não há caminho suportado.** Exigiria imagem de bloco de `sda1` feita antes, e não cabe no espaço livre atual (1,1 TB usados, 185 GB livres) |

**Conclusão:** a fase 1 não é decoração. É a única rede de proteção que existe neste host.

## 11. Medido, esperado e hipótese

**Medido antes (2026-10-21, ~08:20–12:40):** tudo da §2, o conteúdo de `omv-release-upgrade` e dos
`pre.d`/`post.d`, o estado do TimeShift, os repositórios e suites, o consumo dos discos, a janela
de energia e o funcionamento do SSH por chave.

**Medido depois (2026-10-21, 15:08–16:15):** tudo da §0.1 — versões, plugins, portas, shares,
`/dados`, disco, units, UI/Webmin/CasaOS, repo de security, `+deb12` = 0 e `full-upgrade` = 0.

**Esperado e confirmado na execução:** reescrita dos repos pelo `pre.d`, `config.xml.7x.bak`,
`autoremove`, `reboot-required`; build OMV 8 para os **dez** plugins (10/10); PHP de destino 8.4;
netplan segue suportado; CasaOS continua funcional; UI volta na `:11080`.

**Hipótese derrubada:** que o pacote `openmediavault` recriasse o repo de security sozinho — quem
recria é o state `omv-salt deploy run apt` (§0.4, item 1).

## 12. Anexo — comandos de referência rápida

```powershell
# estado do host (READ)
ssh openmediavault 'cat /etc/debian_version; grep VERSION_ID /etc/os-release'
ssh openmediavault 'systemctl --failed; ss -tlnp | head -30'
ssh openmediavault 'apt-cache policy openmediavault'

# exportar a config antes de mexer (WRITE, fase 1)
ssh openmediavault 'tar czf /root/pre-omv8-config.tgz /etc/openmediavault /etc/apt'

# ensaio (fase 3): ver a §8.3 — tudo dentro de /tmp
```

Relacionado: `docs/README.md` (índice), `docs/runbooks/TROUBLESHOOTING.md` (triagem),
`AGENTS.md` §6.1 (READ/WRITE/DESTRUCTIVE).
