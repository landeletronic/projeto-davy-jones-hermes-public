# samba — share `documentos` (SMB), o Windows grava direto no servidor

| | |
|---|---|
| Serviço | `smbd` (serviço de **host**, não container — ao lado do `cron`) |
| Config | `ops/samba/smb.conf` → `/etc/samba/smb.conf` (instalada pelo sync) |
| Share | `\\192.168.15.231\documentos` → `/home/tlandskron/documents` |
| Usuário | `tlandskron` (senha **própria**, definida com `smbpasswd`) |
| Porta | `445/tcp` — liberada **só** para `192.168.15.0/24` (ufw) **e** `hosts allow` no Samba |

## Para que existe

Os documentos de estudo (editais, provas, gabaritos) vivem no **servidor** — fonte única, dentro
do backup diário — e o Windows os acessa como unidade de rede. Nada disso fica no repositório.
Desenho completo: `docs/plans/DESENHO-INBOX-DOCUMENTS.md`.

## Verificar

```bash
systemctl is-active smbd && systemctl is-enabled smbd     # active / enabled
sudo testparm -s                                          # config válida
sudo testparm -s --section-name=documentos --parameter-name=path
#   /home/tlandskron/documents
sudo smbstatus --shares                                   # sessões abertas agora
smbclient -L //127.0.0.1 -U tlandskron                    # pede a senha SMB
sudo ufw status | grep 445                                # 445 ALLOW 192.168.15.0/24
```

## Reiniciar / recarregar

```bash
sudo systemctl restart smbd     # derruba sessões abertas (o Explorer reconecta)
sudo systemctl reload smbd      # recarrega smb.conf sem derrubar
```

## Definir / trocar a senha SMB

A senha do Samba é **separada** da senha do Linux (e da do Windows):

```bash
sudo smbpasswd -a tlandskron    # cria (pede a senha duas vezes)
sudo smbpasswd tlandskron       # troca
sudo smbpasswd -x tlandskron    # remove o acesso SMB (sem apagar o usuário Linux)
```

Depois de trocar, no Windows: `net use * /delete` e mapear de novo (o Windows guarda a senha
velha e devolve "acesso negado" mesmo com a senha certa).

## Mapear no Windows (uma vez)

Explorer → *Este Computador* → *Mapear unidade de rede* → `\\192.168.15.231\documentos` →
*Conectar usando credenciais diferentes* → usuário `tlandskron` + senha SMB.

Ou no PowerShell:

```powershell
net use T: \\192.168.15.231\documentos /user:tlandskron *   # * pede a senha
net use T: /delete                                          # desfazer
```

Use o **IP**, não o nome: o `smb.conf` desliga o NetBIOS (`disable netbios = yes`).

## Sintomas típicos

| Sintoma | Causa | Ação |
|---|---|---|
| `0x80070035` (caminho não encontrado) | nome não resolve / host desligado | usar `\\192.168.15.231`; `ping` no host |
| "acesso negado" com a senha certa | credencial velha em cache no Windows | `net use * /delete` e mapear de novo |
| "múltiplas conexões com o mesmo usuário" | já existe sessão com outra credencial | `net use * /delete` e reconectar |
| Só lê, não grava | permissão do diretório | `ls -ld ~/documents` (dono `tlandskron`, 755) |
| 445 inacessível de outra sub-rede | **por desenho** | a regra é `ufw allow from 192.168.15.0/24` |
| `smbd` não sobe | `smb.conf` inválida | `sudo testparm -s` mostra a linha |
| Log | — | `/var/log/samba/log.<máquina>` |

## Reinstalar

O **pacote** é instalado uma vez à mão (o sync não instala pacotes):

```bash
ssh davy-jones-hermes 'sudo apt-get install -y samba'
```

A partir daí, todo deploy aplica a config e reinicia o serviço:

```powershell
powershell -File ops\deploy\sync-to-host.ps1
```

O sync valida com `testparm` **antes** de reiniciar — config quebrada não derruba o share.

## Backup

`~/documents` entra no tar diário (`documents.tgz`). Restaurar = extrair o `.tgz` de volta em
`/home/tlandskron/` (o diretório é recriado com o mesmo caminho relativo).
