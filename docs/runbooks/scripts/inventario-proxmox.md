# inventario-proxmox.ps1 — inventário de hardware do servidor físico (Windows → Proxmox)

> Duas peças, como o resto do lab: **`tools/inventario_hardware.sh`** roda *no* servidor
> (coleta) e **`tools/inventario-proxmox.ps1`** roda no **Windows** (dispara, recebe e grava).
> O resultado é [`docs/architecture/INVENTARIO-HARDWARE-PROXMOX.md`](../../architecture/INVENTARIO-HARDWARE-PROXMOX.md).

## O que faz

1. Lê `tools/inventario_hardware.sh`, manda por **base64** ao host (o `ssh` do PowerShell 5.1
   mangla aspas) e executa com `bash` — ou `sudo -n bash` quando o login não é root.
2. O coletor joga o script por *stdin* (`bash <<< "$src"`): **não grava arquivo no host**.
3. A saída volta em **base64** e é decodificada no Windows — assim travessão e acento não
   dependem da página de código do console.
4. Grava o Markdown em UTF-8 **sem BOM** e imprime o bloco *Resumo* na tela.

## Como rodar

```powershell
powershell -File tools\inventario-proxmox.ps1            # root@192.168.15.221 (default)
powershell -File tools\inventario-proxmox.ps1 -DryRun    # coleta e mostra, não grava
powershell -File tools\inventario-proxmox.ps1 -Target root@192.168.15.221 -OutFile C:\temp\inv.md
```

## Pré-requisito: chave SSH (uma vez)

Sem chave, o `ssh` **pede a senha** — funciona, mas não é automatizável. Para cadastrar:

```powershell
type $env:USERPROFILE\.ssh\pve-lab.pub | ssh root@192.168.15.221 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

> A chave `pve-lab` já autentica em **192.168.15.10**, que é uma **VM** KVM — não o ferro.
> O ferro é o `.221`, e ele só aceita `publickey,password`.

## O que o software vê — e o que ele não vê

| Item | Dá para saber por software? | Fonte |
|---|---|---|
| Placa-mãe (fabricante/modelo) | **sim** | DMI tipo 2 |
| Processador | **sim** (nome comercial, núcleos, threads) | DMI tipo 4 |
| GPU | **sim** — modelo e **fabricante da placa parceira** (ex.: ASRock) | `lspci` (SVendor) |
| Rede / USB 1.1 / 2.0 / 3.x / áudio | **sim**, com geração pelo *prog-if* | `lspci` + `/sys` |
| Serial, PS-2, VGA/HDMI, portas do painel | **às vezes** | DMI tipo 8 |
| Gabinete | **quase nunca** (`Default string` na maioria das placas) | DMI tipo 3 |
| Cooler / watercooler | **não** (só marca se houver controlador USB ou sensor de RPM) | DMI tipo 27 / `sensors` / `lsusb` |
| Fonte (PSU) | **não** em placa de consumidor (só com BMC/IPMI) | DMI tipo 39 / `ipmitool` |

Os três últimos exigem **abrir o gabinete e ler a etiqueta**. O documento diz isso na cara
(seção 6/7/8) em vez de inventar.

## Privacidade: o que sai de propósito

**Número de série, UUID e asset tag são mascarados** (`(omitido)`) pelo coletor — identificam a
máquina e não respondem "fabricante e modelo". MAC address também não é coletado. Por isso o
arquivo pode ir para o espelho público sem redação extra; o `.ps1` **recusa gravar** se um
identificador não mascarado aparecer na saída.

## Diagnóstico

| Sintoma | Causa provável |
|---|---|
| `Permission denied (publickey,password)` e a senha não é pedida | rode sem `-BatchMode` (o script já tenta as duas formas); confira se o `ssh` abre prompt no console |
| `SINTAXE_FALHOU no coletor` | o `.sh` foi editado e quebrou — `bash -n tools/inventario_hardware.sh` no host |
| `placa-mae` e `fonte` vazios e `systemd-detect-virt = kvm` | você rodou numa **VM**; o inventário do ferro precisa do `.221` |
| `sensors`/`lsusb` ausentes | não são obrigatórios: o documento escreve "(nenhum dado)" e segue |
| Acentos estranhos no console | o arquivo está certo (base64 → UTF-8); é só a página de código do terminal |

## Reinstalar

Nada a instalar: são scripts de `tools/`, rodados à mão. O `sync-to-host.ps1` leva os dois para
o host (a suíte os confere lá), mas o `.ps1` roda **no Windows**.
