#!/usr/bin/env bash
# =============================================================================
# inventario_hardware.sh — inventario de hardware do servidor FISICO (Proxmox)
#
# Somente leitura: nao instala, nao altera, nao grava nada no host. Imprime um
# documento Markdown na saida padrao (o `inventario-proxmox.ps1` grava o arquivo
# no Windows).
#
#   sudo bash inventario_hardware.sh > inventario.md
#
# Fontes: DMI/SMBIOS (dmidecode), lspci, lsusb, ip, sensors/ethtool/ipmitool
# (quando existem) e pveversion.
#
# Numeros de serie, UUID e asset tag saem OMITIDOS de proposito: identificam a
# maquina e nao respondem "fabricante e modelo". Assim o arquivo pode ir para o
# espelho publico sem redacao extra.
# =============================================================================
set -uo pipefail

have() { command -v "$1" >/dev/null 2>&1; }

if [ "$(id -u)" -eq 0 ]; then DMI="dmidecode"; else DMI="sudo -n dmidecode"; fi
dmi() { $DMI -t "$1" 2>/dev/null; }

# valor de um campo DMI: ("Product Name: X" -> "X")
# O dmidecode preenche o valor com espacos a direita (o Part Number sai
# "KF3200C16D4/16GX        "): sem o trim, o resumo vira tabela torta.
campo() { printf '%s\n' "$1" | sed -n "s/^[[:space:]]*$2:[[:space:]]*//p" | head -1 | sed 's/[[:space:]]*$//'; }

# tira cabecalho do dmidecode
corpo() { printf '%s\n' "$1" | grep -vE '^(#|Getting SMBIOS|SMBIOS|$)' | sed 's/[[:space:]]*$//'; }

# esconde identificadores unicos
mask() { sed -E 's/^([[:space:]]*(Serial Number|UUID|Asset Tag):).*/\1 (omitido)/I'; }

bloco() { if vazio "$2"; then printf '```text\n(nenhum dado)\n```\n\n'; else printf '```text\n%s\n```\n\n' "$2"; fi; }
vazio() { [ -z "$(printf '%s' "$1" | tr -d '[:space:]')" ]; }
ou()    { if vazio "$1"; then printf '%s' "$2"; else printf '%s' "$1"; fi; }
campo_ou() { printf '%s' "$(ou "$1" '(nao informado)')"; }

# -----------------------------------------------------------------------------
# Dispositivos PCI por classe, via `lspci -vmmnn` (campos ja separados):
#   slot | fabricante | modelo | submodelo (placa parceira) | ids [vid:did]
# O `-nn` anexa "[1002]" ao nome do fabricante e "[73ff]" ao do modelo: o
# semid() tira esses ids do texto e o ultimo() os recolhe num campo proprio,
# senao o nome sai como "Advanced Micro Devices [AMD/ATI] [1002]".
# -----------------------------------------------------------------------------
lista_pci() {
  lspci -vmmnn -d "::$1" 2>/dev/null | awk '
    function semid(s) {
      sub(/ \[[0-9a-f]{4}:[0-9a-f]{4}\]$/, "", s)
      sub(/ \[[0-9a-f]{4}\]$/, "", s)
      if (s == "Vendor" || s == "Device") s = "(sem nome no pci.ids)"
      return s
    }
    function ultimo(s,   i) { i = match(s, /\[[0-9a-f]{4}\]$/); return (i ? substr(s, RSTART+1, 4) : "") }
    # fabricante da placa parceira (SVendor/SDevice); o QEMU nao informa modelo.
    # Se o SDevice repete o nome do proprio controlador (audio da GPU), descarta:
    # senao o resumo sai "... (AMD ... Navi 21/23 HDMI/DP Audio Controller)".
    # E se o SVendor e o mesmo do Vendor, tambem e ruido ("(AMD ... [AMD/ATI])").
    function subsis(   s) {
      s = semid(sdev)
      if (s == "(sem nome no pci.ids)") s = ""
      if (s != "" && index(dev, s) > 0) s = ""
      if (sven == "" || semid(sven) == semid(ven)) return s
      return (s == "" ? semid(sven) : semid(sven) " " s)
    }
    function emite() {
      if (slot == "") return
      printf "%s|%s|%s|%s|%s\n", slot, semid(ven), semid(dev), subsis(), (vid != "" ? "[" vid ":" did "]" : "")
    }
    /^Slot:/    { emite(); slot=$2; ven=""; dev=""; sven=""; sdev=""; vid=""; did=""; next }
    /^Vendor:/  { sub(/^Vendor:[ \t]*/, ""); ven=$0; vid=ultimo($0); next }
    /^Device:/  { sub(/^Device:[ \t]*/, ""); dev=$0; did=ultimo($0); next }
    /^SVendor:/ { sub(/^SVendor:[ \t]*/, ""); sven=$0; next }
    /^SDevice:/ { sub(/^SDevice:[ \t]*/, ""); sdev=$0; next }
    END { emite() }
  '
}

driver_de() {  # /sys/bus/pci/devices/0000:<slot>/driver -> nome do modulo
  local b
  b=$(readlink -f "/sys/bus/pci/devices/0000:$1/driver" 2>/dev/null)
  [ -n "$b" ] && basename "$b"
}

agora=$(date --iso-8601=seconds 2>/dev/null || date)
host=$(hostname 2>/dev/null || echo '?')
# `systemd-detect-virt` imprime "none" e SAI 1 quando nao ha virtualizacao: o `||`
# antigo colava "none" e "desconhecido" no cabecalho (visto no ferro em 2026-10-23).
virt=$(systemd-detect-virt 2>/dev/null); [ -n "$virt" ] || virt='desconhecido'

SIS=$(dmi 1); PLACA=$(dmi 2); CHASSI=$(dmi 3); CPU=$(dmi 4)
PORTS=$(dmi 8); COOLER=$(dmi 27); PSU=$(dmi 39); BIOS=$(dmi 0); MEM=$(dmi 17)

board_vendor=$(campo "$PLACA" 'Manufacturer')
board_name=$(campo "$PLACA" 'Product Name')
board_ver=$(campo "$PLACA" 'Version')
sys_vendor=$(campo "$SIS" 'Manufacturer')
sys_name=$(campo "$SIS" 'Product Name')
cpu_vendor=$(campo "$CPU" 'Manufacturer')
cpu_name=$(campo "$CPU" 'Version')
cpu_cores=$(campo "$CPU" 'Core Count')
cpu_threads=$(campo "$CPU" 'Thread Count')
cpu_socket=$(campo "$CPU" 'Socket Designation')
cpu_max=$(printf '%s\n' "$CPU" | awk -F': ' '/Max Speed/{print $2; exit}')
chassi_vendor=$(campo "$CHASSI" 'Manufacturer')
chassi_type=$(campo "$CHASSI" 'Type')
chassi_ver=$(campo "$CHASSI" 'Version')
mem_mods=$(printf '%s\n' "$MEM" | grep -cE '^[[:space:]]*Size: [0-9]+ (MB|GB)')
mem_total=$(free -h 2>/dev/null | awk '/^Mem:/{print $2}')
# primeiro modulo: normalmente os slots sao identicos (B660M-HDV: 2x Kingston 16 GB)
# (o trim e obrigatorio: o DMI alinha os valores com espacos a direita)
trim() { sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'; }
mem_fab=$(printf '%s\n' "$MEM" | awk -F': ' '/^[[:space:]]*Manufacturer:/{print $2; exit}' | trim)
mem_part=$(printf '%s\n' "$MEM" | awk -F': ' '/^[[:space:]]*Part Number:/{print $2; exit}' | trim)
mem_tam=$(printf '%s\n' "$MEM" | awk -F': ' '/^[[:space:]]*Size: [0-9]+ (GB|MB)/{print $2; exit}' | trim)
mem_vel=$(printf '%s\n' "$MEM" | awk -F': ' '/^[[:space:]]*Speed:/{print $2; exit}' | trim)

# GPU: VGA + 3D + display
GPU=$( { lista_pci 0300; lista_pci 0302; lista_pci 0380; } | sort -u)
gpu_drv=$(printf '%s\n' "$GPU" | while IFS='|' read -r s _ _ _ _; do [ -n "$s" ] && driver_de "$s"; done | paste -sd ', ' -)

# rede
NET=$(lista_pci 0200)
net_drv=$(printf '%s\n' "$NET" | while IFS='|' read -r s _ _ _ _; do [ -n "$s" ] && driver_de "$s"; done | paste -sd ', ' -)
# Interfaces FISICAS: so as que tem device no /sys (vmbr0/vmbr1/tap/veth sao virtuais).
fisicas=$(for i in /sys/class/net/*; do
            [ -e "$i/device" ] || continue
            st=$(cat "$i/operstate" 2>/dev/null | tr '[:lower:]' '[:upper:]')
            printf '%s (%s), ' "$(basename "$i")" "${st:-?}"
          done)
fisicas=${fisicas%, }

# audio
AUDIO=$(lista_pci 0403)

# USB: classe 0c03; a geracao vem do prog-if
USB_DEV=$(lista_pci 0c03)
usb_tab=""
# here-string: o loop roda no shell atual (com pipe seria subshell e usb_tab se perderia)
while IFS='|' read -r slot ven dev sdev ids; do
  [ -z "${slot:-}" ] && continue
  cls=$(cat "/sys/bus/pci/devices/0000:$slot/class" 2>/dev/null)
  case "$cls" in
    0x0c0300) g='USB 1.1 (UHCI)' ;;
    0x0c0310) g='USB 1.1 (OHCI)' ;;
    0x0c0320) g='USB 2.0 (EHCI)' ;;
    0x0c0330) g='USB 3.x (xHCI)' ;;
    0x0c0340) g='USB4' ;;
    *)        g="desconhecida ($cls)" ;;
  esac
  usb_tab="${usb_tab}${slot}	${ven}	${dev}	${g}	${ids}"$'\n'
done <<< "$USB_DEV"
usb_1=$(printf '%s\n' "$usb_tab" | grep -c 'USB 1\.1' || true)
usb_2=$(printf '%s\n' "$usb_tab" | grep -c 'USB 2\.0' || true)
usb_3=$(printf '%s\n' "$usb_tab" | grep -cE 'USB 3|USB4' || true)
# Portas por root hub. Numa B660M-HDV nao existe EHCI/UHCI: os 26 ports estao nos
# root hubs do UNICO xHCI (um USB 2.0 e um USB 3.x) — contar so o controlador PCI
# responderia "USB 1.1/2.0: nenhum", que e tecnicamente verdade e praticamente inutil.
usb_ports_texto=""
usb_tab_portas=""
for u in /sys/bus/usb/devices/usb*; do
  [ -r "$u/version" ] || continue
  # o sysfs escreve o version com espaco a esquerda (" 1.10"): sem o trim, todo
  # `case` cai no default e o documento sai "USB ( 1.10), 2 porta(s)" (visto no ferro).
  ver=$(cat "$u/version" 2>/dev/null | tr -d '[:space:]')
  mc=$(cat "$u/maxchild" 2>/dev/null | tr -d '[:space:]')
  case "$ver" in
    1.*) gen='USB 1.1' ;;
    2.*) gen='USB 2.0' ;;
    3.*) gen='USB 3.x' ;;
    *)   gen="USB ($ver)" ;;
  esac
  usb_ports_texto="${usb_ports_texto}$(basename "$u"): $gen, ${mc:-?} porta(s); "
  usb_tab_portas="${usb_tab_portas}${gen}	${mc:-0}	$(basename "$u")"$'\n'
done
usb_ports_texto=${usb_ports_texto%; }
usb_disp=$(lsusb 2>/dev/null)

# portas fisicas (DMI tipo 8)
portas=$(corpo "$PORTS" | awk -F': ' '
  /^Port Connector Information/ { if (ext != "") print ext "|" conn "|" tipo; ext=""; conn=""; tipo="" }
  /External Reference Designator/ { ext=$2 }
  /External Connector Type/       { conn=$2 }
  /^[[:space:]]*Port Type/        { tipo=$2 }
  END { if (ext != "") print ext "|" conn "|" tipo }
  ' | grep -v '^|' | sort -u)
n_portas=$(printf '%s\n' "$portas" | grep -c . || true)

# ventoinhas / todo e qualquer indicio de cooler ou AIO
fan_txt=""
if have sensors; then fan_txt=$(sensors 2>/dev/null | grep -iE 'fan|pump|rpm' | head -20); fi
cooler_dmi=$(corpo "$COOLER" | head -8)
usb_cooler=$(printf '%s\n' "$usb_disp" | grep -iE 'nzxt|corsair|asetek|lian ?li|cooler ?master|thermaltake|arctic|aquacomputer|hydro|kraken|fan' || true)

# fonte
psu_dmi=$(corpo "$PSU" | head -40)
ipmi_txt=""
if have ipmitool; then ipmi_txt=$(ipmitool sdr type 'Power Supply' 2>/dev/null | head -10); fi

# monta a tabela de dispositivos do resumo
tab_gpu=$(printf '%s\n' "$GPU" | awk -F'|' 'NF>2 && $1!="" {printf "| GPU | %s | %s%s%s | `lspci` |\n", $2, $3, ($4!=""?"  (" $4 ")":""), ($5!=""?"  " $5:"")}')
tab_net=$(printf '%s\n' "$NET" | awk -F'|' 'NF>2 && $1!="" {printf "| Rede | %s | %s%s%s | `lspci` |\n", $2, $3, ($4!=""?"  (" $4 ")":""), ($5!=""?"  " $5:"")}')
tab_audio=$(printf '%s\n' "$AUDIO" | awk -F'|' 'NF>2 && $1!="" {printf "| Audio | %s | %s%s | `lspci` |\n", $2, $3, ($4!=""?"  (" $4 ")":"")}')
# portas por geracao: e a resposta util para "usb1/2/3" (root hubs, nao so controlador)
tab_usb_portas=$(printf '%s' "$usb_tab_portas" | awk -F'\t' '
  NF > 2 { p[$1] += $2; h[$1] = h[$1] (h[$1] != "" ? "," : "") $3 }
  END {
    n = split("USB 3.x|USB 2.0|USB 1.1", o, "|")
    for (i = 1; i <= n; i++) if (o[i] in p)
      printf "| %s | %d porta(s) | root hub %s | `/sys` |\n", o[i], p[o[i]], h[o[i]]
  }')
usb_linha() {  # "rotulo" "padrao" -> 1 linha do resumo por controlador PCI
  local n ref
  n=$(printf '%s\n' "$usb_tab" | grep -cE "$2" || true)
  [ "${n:-0}" -eq 0 ] && return 0
  ref=$(printf '%s\n' "$usb_tab" | grep -E "$2" | head -1 | awk -F'\t' '{print $2 " " $3}')
  printf '| %s | %s controlador(es) | %s | `lspci` |\n' "$1" "$n" "$ref"
}
tab_usb_ctl=$( { usb_linha 'USB 1.1' 'USB 1\.1'; usb_linha 'USB 2.0' 'USB 2\.0'; usb_linha 'USB 3.x/USB4' 'USB 3|USB4'; } )
tab_usb=$tab_usb_portas
if [ -n "$tab_usb_portas" ] && [ -n "$tab_usb_ctl" ]; then
  tab_usb="${tab_usb}"$'\n'"${tab_usb_ctl}"
elif [ -z "$tab_usb_portas" ]; then
  tab_usb=$tab_usb_ctl
fi
[ -z "$tab_gpu" ]   && tab_gpu='| GPU | — | nenhuma placa de video PCI encontrada | `lspci` |'
[ -z "$tab_net" ]   && tab_net='| Rede | — | nenhuma interface PCI de rede encontrada | `lspci` |'
[ -z "$tab_audio" ] && tab_audio='| Audio | — | nenhum controlador de audio PCI encontrado | `lspci` |'
[ -z "$tab_usb" ]   && tab_usb='| USB | — | nenhum controlador USB PCI encontrado | `lspci` |'

# =============================================================================
cat <<FIM
# Inventario de hardware — servidor fisico do lab

> Gerado em **$agora** por \`tools/inventario_hardware.sh\` (somente leitura) no host
> \`$host\` (\`systemd-detect-virt = ${virt}\`).
> Fontes: DMI/SMBIOS (\`dmidecode\`), \`lspci\`, \`lsusb\`, \`ip\`, \`pveversion\`.
> **Numeros de serie, UUID e asset tag foram omitidos de proposito.**

## Resumo

| Dispositivo | Fabricante | Modelo / descricao | Fonte |
|---|---|---|---|
| Placa-mae | $(campo_ou "${board_vendor:-}") | $(campo_ou "${board_name:-}")$( [ -n "$board_ver" ] && printf ' (rev. %s)' "$board_ver" ) | DMI tipo 2 |
| Processador | $(campo_ou "${cpu_vendor:-}") | $(campo_ou "${cpu_name:-}")$( [ -n "$cpu_cores" ] && printf ' — %s nucleos / %s threads' "$cpu_cores" "${cpu_threads:-?}" ) | DMI tipo 4 |
| Memoria | $(ou "$mem_fab" '—') | $(ou "${mem_mods}x ${mem_tam:-?} ${mem_part:-}" 'modulos nao informados')$( [ -n "$mem_vel" ] && printf ' (%s)' "$mem_vel" ) — ${mem_total:-?} visiveis | DMI tipo 17 |
$tab_gpu
$tab_net
$tab_usb
$tab_audio
| Cooler / watercooler | $(ou "$(printf '%s\n' "$usb_cooler" | head -1 | sed -E 's/^.*ID [0-9a-f:]+ //')" 'ver secao 6') | $(ou "$(campo "$COOLER" 'Description')" 'ver secao 6') | DMI tipo 27 / sensores / USB |
| Fonte (PSU) | $(ou "$(campo "$PSU" 'Manufacturer')" 'ver secao 7') | $(ou "$(campo "$PSU" 'Model Part Number')" 'ver secao 7') | DMI tipo 39 / IPMI |
| Gabinete | $(campo_ou "${chassi_vendor:-}") | $(campo_ou "${chassi_type:-}")$( [ -n "$chassi_ver" ] && printf ' — %s' "$chassi_ver" ) | DMI tipo 3 |
| Portas do painel | — | ${n_portas} porta(s) no DMI (serial, PS-2, USB, video, audio) | DMI tipo 8 |

## 1. Placa-mae

$(bloco "" "$(corpo "$PLACA" | mask | head -20)")

$( if [ -z "${board_name:-}" ]; then
     printf '> Esta maquina **nao informa** a placa-mae no DMI (tipico de VM). Num servidor fisico\n> aparecem aqui *Manufacturer* e *Product Name*.\n'
   else
     printf '%s **%s**%s.\n' "$board_vendor" "$board_name" "$( [ -n "$board_ver" ] && printf ', rev. %s' "$board_ver" )"
   fi )

## 2. Processador

$(bloco "" "$(corpo "$CPU" | mask | grep -E 'Socket Designation|Type:|Family|Manufacturer|Version|Max Speed|Current Speed|Core Count|Thread Count|Core Enabled' | sed 's/^[[:space:]]*//' | head -20)")

$(ou "${cpu_vendor:-}" '?') **$(ou "${cpu_name:-}" '?')**$( [ -n "$cpu_cores" ] && printf ' — %s nucleos / %s threads' "$cpu_cores" "${cpu_threads:-?}" ).

## 3. Memoria

$(bloco "" "$(corpo "$MEM" | mask | grep -E '^[[:space:]]*(Size|Form Factor|Type:|Type Detail|Speed|Configured Memory Speed|Manufacturer|Part Number|Locator):' | sed 's/^[[:space:]]*//' | grep -vE 'Size: (No Module|0 MB)' | head -40)")

## 4. Placas de video

$(bloco "lspci -vmmnn -d ::0300,0302,0380" "$( { lista_pci 0300; lista_pci 0302; lista_pci 0380; } | awk -F'|' 'NF>2 && $1!="" {printf "%s  %s  %s  %s %s\n", $1, $2, $3, ($4!=""?"(" $4 ")":""), $5}' )")
Driver em uso: **$(ou "$gpu_drv" 'nenhum (sem modulo carregado)')**
$( printf '%s' "$gpu_drv" | grep -q 'vfio-pci' && printf '\n> `vfio-pci` = a placa esta reservada para *passthrough* a uma VM: o servidor nao usa video proprio\n> e o HDMI/DisplayPort da placa nao da imagem. O console e SSH/serial.\n' )

## 5. BIOS

$(bloco "" "$(corpo "$BIOS" | mask | head -12)")

## 6. Cooler / watercooler

- **DMI tipo 27 (Cooling Device):** $(ou "$cooler_dmi" 'nada — a maioria das placas de consumidor nao publica esta secao')
- **Ventoinhas / bombas (sensores):** $(ou "$fan_txt" '`sensors` nao instalado ou sem leitura de RPM')
- **USB com cara de controlador de AIO/cooler:** $(ou "$usb_cooler" 'nenhum')

$( if vazio "${usb_cooler:-}${fan_txt:-}${cooler_dmi:-}"; then
     printf '> **Conclusao:** o modelo do cooler/watercooler **nao e exposto por software** neste host.\n> Para registrar: ler a etiqueta do bloco de agua/radiador (ou o nome no proprio radiador).\n'
   else
     printf '> Modelo exato: so o que aparece acima. Em geral isso identifica **marca e tipo** (AIO x air),\n> nao o modelo comercial — a etiqueta fisica continua sendo a fonte definitiva.\n'
   fi )

## 7. Fonte (PSU)

- **DMI tipo 39 (System Power Supply):** $(ou "$psu_dmi" 'nada — praticamente nenhuma placa-mae de consumidor publica esta secao')
- **IPMI (se houver BMC):** $(ou "$ipmi_txt" '`ipmitool` ausente ou sem sensor de fonte')

$( if vazio "${psu_dmi:-}"; then
     printf '> **Conclusao:** a fonte **nao e identificavel por software** — exige abrir o gabinete e ler a\n> etiqueta (marca, modelo, potencia). Nenhuma ferramenta do SO ve isso em placa de consumidor.\n'
   else
     printf '> Fonte identificada acima pelo DMI.\n'
   fi )

## 8. Gabinete

$(bloco "" "$(corpo "$CHASSI" | mask | head -12)")

$(ou "${chassi_vendor:-}" '?') — $(ou "${chassi_type:-}" 'tipo nao informado')$( [ -n "$chassi_ver" ] && printf ' (%s)' "$chassi_ver" ).
$( printf '%s' "${chassi_vendor:-}" | grep -qiE 'default|to be filled|o\.e\.m|chassis' && printf '> **Default string** = a placa-mae nao informa o gabinete (normal em maquina montada).\n> Modelo so por inspecao fisica.\n' )

## 9. Rede

$(bloco "lspci -vmmnn -d ::0200" "$(printf '%s\n' "$NET" | awk -F'|' 'NF>2 && $1!="" {printf "%s  %s  %s %s\n", $1, $2, $3, $5}')")
Driver: $(ou "$net_drv" '?')
Interfaces fisicas: $(ou "$fisicas" '?')

## 10. USB

Geracao vem do *prog-if* do controlador (00=UHCI e 10=OHCI => USB 1.1; 20=EHCI => USB 2.0;
30/40=xHCI => USB 3.x/USB4).

| Slot | Fabricante | Controlador | Geracao | IDs |
|---|---|---|---|---|
$(printf '%s\n' "$usb_tab" | awk -F'\t' 'NF>3 && $1!="" {printf "| %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5}')
$( [ -z "$usb_tab" ] && printf '| — | — | nenhum controlador USB PCI | — | — |\n' )
Controladores PCI: **${usb_1}** USB 1.1, **${usb_2}** USB 2.0, **${usb_3}** USB 3.x/USB4.
Portas por root hub: $(ou "$usb_ports_texto" 'nenhum root hub em /sys')

> Onde o controlador PCI e um so (xHCI de chipset moderno), as portas USB 2.0 **nao**
> aparecem como EHCI: elas penduram no *root hub* USB 2.0 do proprio xHCI. E o caso das
> placas Alder Lake/Raptor Lake — por isso a contagem util e a de root hubs, acima.

Dispositivos conectados agora:

$(bloco "lsusb" "$(ou "$usb_disp" 'lsusb nao instalado')")

## 11. Portas do painel (DMI tipo 8)

| Designador externo | Conector | Tipo de porta |
|---|---|---|
$( if [ -n "$portas" ]; then
     printf '%s\n' "$portas" | awk -F'|' 'NF>=2 && $1!="" {printf "| %s | %s | %s |\n", $1, $2, $3}'
   else
     printf '| — | — | o DMI desta placa nao publica a secao 8 |\n'
   fi )

$( [ -z "$portas" ] && printf '> Sem a secao 8, serial/PS-2/video so por inspecao fisica: essas portas ficam no\n> Super I/O e nao aparecem no `lspci`.\n' )
> HDMI/DisplayPort nao aparecem no DMI: quem os expoe e a **GPU** (secao 4). Porta serial e PS-2,
> quando existem, ficam no Super I/O — so aparecem aqui.

## 12. Audio

$(bloco "lspci -vmmnn -d ::0403" "$(printf '%s\n' "$AUDIO" | awk -F'|' 'NF>2 && $1!="" {printf "%s  %s  %s %s\n", $1, $2, $3, $5}')")

## 13. Software do servidor (contexto)

$(bloco "" "$( { uname -sr; grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '\"'; pveversion 2>/dev/null | head -1; printf 'kvm/modulos: '; lsmod 2>/dev/null | grep -cE '^(kvm|vfio)' ; } )")

---

## Anexo — saidas completas (series e UUID omitidos)

### dmidecode -t system
\`\`\`text
$(corpo "$SIS" | mask | head -25)
\`\`\`

### dmidecode -t baseboard
\`\`\`text
$(corpo "$PLACA" | mask | head -25)
\`\`\`

### dmidecode -t chassis
\`\`\`text
$(corpo "$CHASSI" | mask | head -20)
\`\`\`

### dmidecode -t 8 (port connector)
\`\`\`text
$(corpo "$PORTS" | mask | head -80 | { read -r l && printf '%s\n' "$l"; cat; } || printf '(o DMI desta placa nao publica a secao 8)\n')
\`\`\`

### dmidecode -t 27 (cooling device) e -t 39 (power supply)
\`\`\`text
$( { corpo "$COOLER"; corpo "$PSU"; } | mask | head -30 | { read -r l && printf '%s\n' "$l"; cat; } || printf '(o DMI desta placa nao publica as secoes 27 e 39)\n')
\`\`\`

### lspci (todos os dispositivos)
\`\`\`text
$(lspci -nn 2>/dev/null)
\`\`\`
FIM
