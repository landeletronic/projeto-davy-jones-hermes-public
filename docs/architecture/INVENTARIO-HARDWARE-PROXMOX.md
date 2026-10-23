# Inventário de hardware — servidor físico (Proxmox)

> **Status: pendente de execução no ferro.** Este arquivo é o *destino* do coletor; enquanto
> ninguém o rodar no servidor físico ele não contém medição nenhuma. O preenchimento é feito por:
>
> ```powershell
> powershell -File tools\inventario-proxmox.ps1
> ```
>
> (coletor: `tools/inventario_hardware.sh`; dispara do Windows e conecta em `root@192.168.15.221`;
> card: [`../runbooks/scripts/inventario-proxmox.md`](../runbooks/scripts/inventario-proxmox.md))

## Por que ainda não está preenchido

O acesso ao `192.168.15.221` exige senha (`Permission denied (publickey,password)`): não há chave
cadastrada para o ferro. A chave `pve-lab` autentica em `192.168.15.10`, que é uma **VM** KVM —
lá o DMI responde `QEMU` / `pc-q35`, o que não serve como inventário do servidor.

O coletor foi validado ponta a ponta nessa VM (mesma mecânica: base64, `sudo -n`, retorno em
base64), e o que saiu de lá está no [`README.md`](../../README.md) como retrato da **VM**.

## O que este documento terá quando for gerado

| Seção | Conteúdo |
|---|---|
| Resumo | uma linha por dispositivo: placa-mãe, CPU, memória, GPU, rede, USB 1.1/2.0/3.x, áudio, gabinete, portas do painel |
| 1–3 | placa-mãe, processador e módulos de memória (DMI tipos 2, 4 e 17) |
| 4–5 | GPUs com *driver* em uso (marca `vfio-pci` quando a placa está em *passthrough*) e BIOS |
| 6–8 | **cooler, fonte e gabinete** — o que o software consegue ver e o aviso explícito quando não há dado |
| 9–12 | rede, USB (tabela por controlador), portas do painel (serial/PS-2/VGA…) e áudio |
| 13 | software do servidor (`uname`, distro, `pveversion`) |
| Anexo | saídas completas do `dmidecode` e do `lspci`, com **série/UUID/asset tag omitidos** |

## Invariantes

- **Somente leitura:** o coletor não instala, não altera e não deixa arquivo no host.
- **Sem identificadores únicos:** número de série, UUID e asset tag saem como `(omitido)`; MAC
  address não é coletado. O `.ps1` recusa gravar o arquivo se a máscara falhar.
- **Não inventa:** campo que a placa não publica vira `(nenhum dado)` / `(nao informado)`, nunca
  um palpite.
