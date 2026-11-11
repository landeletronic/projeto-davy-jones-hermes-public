# Inventario de hardware — servidor fisico do lab

> Gerado em **2026-11-11T19:56:08-03:00** por `tools/inventario_hardware.sh` (somente leitura) no host
> `pve-tuf-x470` (`systemd-detect-virt = none`).
> Fontes: DMI/SMBIOS (`dmidecode`), `lspci`, `lsusb`, `ip`, `pveversion`.
> **Numeros de serie, UUID e asset tag foram omitidos de proposito.**

## Resumo

| Dispositivo | Fabricante | Modelo / descricao | Fonte |
|---|---|---|---|
| Placa-mae | ASUSTeK COMPUTER INC. | TUF X470-PLUS GAMING (rev. Rev X.0x) | DMI tipo 2 |
| Processador | Advanced Micro Devices, Inc. | AMD Ryzen 7 5700X 8-Core Processor — 8 nucleos / 16 threads | DMI tipo 4 |
| Memoria | Kingston | 2x 16 GB KF3200C16D4/16GX (3200 MT/s) — 31Gi visiveis | DMI tipo 17 |
| GPU | Advanced Micro Devices, Inc. [AMD/ATI] | Navi 14 [Radeon RX 5500/5500M / Pro 5500M]  [1002:7340] | `lspci` |
| GPU | Advanced Micro Devices, Inc. [AMD/ATI] | Navi 23 [Radeon RX 6600/6600 XT/6600M]  (ASRock Incorporation)  [1002:73ff] | `lspci` |
| Rede | Realtek Semiconductor Co., Ltd. | RTL8111/8168/8211/8411 PCI Express Gigabit Ethernet Controller  (ASUSTeK Computer Inc. Onboard RTL8111H Ethernet)  [10ec:8168] | `lspci` |
| USB 3.x | 12 porta(s) | root hub usb2,usb4 | `/sys` |
| USB 2.0 | 18 porta(s) | root hub usb1,usb3 | `/sys` |
| USB 3.x/USB4 | 2 controlador(es) | Advanced Micro Devices, Inc. [AMD] (sem nome no pci.ids) | `lspci` |
| Audio | Advanced Micro Devices, Inc. [AMD/ATI] | Navi 10 HDMI Audio | `lspci` |
| Audio | Advanced Micro Devices, Inc. [AMD/ATI] | Navi 21/23 HDMI/DP Audio Controller | `lspci` |
| Audio | Advanced Micro Devices, Inc. [AMD] | Starship/Matisse HD Audio Controller  (ASUSTeK Computer Inc.) | `lspci` |
| Cooler / watercooler | ver secao 6 | ver secao 6 | DMI tipo 27 / sensores / USB |
| Fonte (PSU) | ver secao 7 | ver secao 7 | DMI tipo 39 / IPMI |
| Gabinete | Default string | Desktop — Default string | DMI tipo 3 |
| Portas do painel | — | 14 porta(s) no DMI (serial, PS-2, USB, video, audio) | DMI tipo 8 |

## 1. Placa-mae

```text
Handle 0x0002, DMI type 2, 15 bytes
Base Board Information
	Manufacturer: ASUSTeK COMPUTER INC.
	Product Name: TUF X470-PLUS GAMING
	Version: Rev X.0x
	Serial Number: (omitido)
	Asset Tag: (omitido)
	Features:
		Board is a hosting board
		Board is replaceable
	Location In Chassis: Default string
	Chassis Handle: 0x0003
	Type: Motherboard
	Contained Object Handles: 0
```

ASUSTeK COMPUTER INC. **TUF X470-PLUS GAMING**, rev. Rev X.0x.

## 2. Processador

```text
Socket Designation: AM4
Type: Central Processor
Family: Zen
Manufacturer: Advanced Micro Devices, Inc.
Signature: Family 25, Model 33, Stepping 2
Version: AMD Ryzen 7 5700X 8-Core Processor
Max Speed: 4650 MHz
Current Speed: 3400 MHz
Core Count: 8
Core Enabled: 8
Thread Count: 16
```

Advanced Micro Devices, Inc. **AMD Ryzen 7 5700X 8-Core Processor** — 8 nucleos / 16 threads.

## 3. Memoria

```text
Form Factor: Unknown
Locator: DIMM_A1
Type Detail: Unknown
Size: 16 GB
Form Factor: DIMM
Locator: DIMM_A2
Type Detail: Synchronous Unbuffered (Unregistered)
Speed: 3200 MT/s
Manufacturer: Kingston
Part Number: KF3200C16D4/16GX
Configured Memory Speed: 3200 MT/s
Form Factor: Unknown
Locator: DIMM_B1
Type Detail: Unknown
Size: 16 GB
Form Factor: DIMM
Locator: DIMM_B2
Type Detail: Synchronous Unbuffered (Unregistered)
Speed: 3200 MT/s
Manufacturer: Kingston
Part Number: KF3200C16D4/16GX
Configured Memory Speed: 3200 MT/s
```

## 4. Placas de video

```text
09:00.0  Advanced Micro Devices, Inc. [AMD/ATI]  Navi 14 [Radeon RX 5500/5500M / Pro 5500M]   [1002:7340]
0d:00.0  Advanced Micro Devices, Inc. [AMD/ATI]  Navi 23 [Radeon RX 6600/6600 XT/6600M]  (ASRock Incorporation) [1002:73ff]
```
Driver em uso: **vfio-pci,vfio-pci**

> `vfio-pci` = a placa esta reservada para *passthrough* a uma VM: o servidor nao usa video proprio
> e o HDMI/DisplayPort da placa nao da imagem. O console e SSH/serial.

## 5. BIOS

```text
Handle 0x0000, DMI type 0, 26 bytes
BIOS Information
	Vendor: American Megatrends Inc.
	Version: 6254
	Release Date: 01/05/2026
	Address: 0xF0000
	Runtime Size: 64 kB
	ROM Size: 16 MB
	Characteristics:
		PCI is supported
		APM is supported
		BIOS is upgradeable
```

## 6. Cooler / watercooler

- **DMI tipo 27 (Cooling Device):** nada — a maioria das placas de consumidor nao publica esta secao
- **Ventoinhas / bombas (sensores):** `sensors` nao instalado ou sem leitura de RPM
- **USB com cara de controlador de AIO/cooler:** nenhum

> **Conclusao:** o modelo do cooler/watercooler **nao e exposto por software** neste host.
> Para registrar: ler a etiqueta do bloco de agua/radiador (ou o nome no proprio radiador).

## 7. Fonte (PSU)

- **DMI tipo 39 (System Power Supply):** nada — praticamente nenhuma placa-mae de consumidor publica esta secao
- **IPMI (se houver BMC):** `ipmitool` ausente ou sem sensor de fonte

> **Conclusao:** a fonte **nao e identificavel por software** — exige abrir o gabinete e ler a
> etiqueta (marca, modelo, potencia). Nenhuma ferramenta do SO ve isso em placa de consumidor.

## 8. Gabinete

```text
Handle 0x0003, DMI type 3, 22 bytes
Chassis Information
	Manufacturer: Default string
	Type: Desktop
	Lock: Not Present
	Version: Default string
	Serial Number: (omitido)
	Asset Tag: (omitido)
	Boot-up State: Safe
	Power Supply State: Safe
	Thermal State: Safe
	Security Status: None
```

Default string — Desktop (Default string).
> **Default string** = a placa-mae nao informa o gabinete (normal em maquina montada).
> Modelo so por inspecao fisica.

## 9. Rede

```text
03:00.0  Realtek Semiconductor Co., Ltd.  RTL8111/8168/8211/8411 PCI Express Gigabit Ethernet Controller [10ec:8168]
```
Driver: r8169
Interfaces fisicas: enp3s0 (UP)

## 10. USB

Geracao vem do *prog-if* do controlador (00=UHCI e 10=OHCI => USB 1.1; 20=EHCI => USB 2.0;
30/40=xHCI => USB 3.x/USB4).

| Slot | Fabricante | Controlador | Geracao | IDs |
|---|---|---|---|---|
| 01:00.0 | Advanced Micro Devices, Inc. [AMD] | (sem nome no pci.ids) | USB 3.x (xHCI) | [1022:43d0] |
| 0f:00.3 | Advanced Micro Devices, Inc. [AMD] | Matisse USB 3.0 Host Controller | USB 3.x (xHCI) | [1022:149c] |

Controladores PCI: **0** USB 1.1, **0** USB 2.0, **2** USB 3.x/USB4.
Portas por root hub: usb1: USB 2.0, 14 porta(s); usb2: USB 3.x, 8 porta(s); usb3: USB 2.0, 4 porta(s); usb4: USB 3.x, 4 porta(s)

> Onde o controlador PCI e um so (xHCI de chipset moderno), as portas USB 2.0 **nao**
> aparecem como EHCI: elas penduram no *root hub* USB 2.0 do proprio xHCI. E o caso das
> placas Alder Lake/Raptor Lake — por isso a contagem util e a de root hubs, acima.

Dispositivos conectados agora:

```text
Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
Bus 002 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
Bus 003 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
Bus 004 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
```

## 11. Portas do painel (DMI tipo 8)

| Designador externo | Conector | Tipo de porta |
|---|---|---|
| AUDIO | Other | Audio Port |
| DVI port | Other | Other |
| HDMI port | Other | Other |
| LAN | RJ-45 | Network Port |
| Not Specified | None | Audio Port |
| Not Specified | None | Other |
| Not Specified | None | SATA |
| Not Specified | None | Serial Port 16550A Compatible |
| Not Specified | None | USB |
| PS/2 Keyboard/Mouse | PS/2 | Keyboard Port |
| U31G1_56 | Access Bus (USB) | USB |
| U31G1_C7 | Access Bus (USB) | USB |
| U31G2_12 | Access Bus (USB) | USB |
| USB910 | Access Bus (USB) | USB |


> HDMI/DisplayPort nao aparecem no DMI: quem os expoe e a **GPU** (secao 4). Porta serial e PS-2,
> quando existem, ficam no Super I/O — so aparecem aqui.

## 12. Audio

```text
09:00.1  Advanced Micro Devices, Inc. [AMD/ATI]  Navi 10 HDMI Audio [1002:ab38]
0d:00.1  Advanced Micro Devices, Inc. [AMD/ATI]  Navi 21/23 HDMI/DP Audio Controller [1002:ab28]
0f:00.4  Advanced Micro Devices, Inc. [AMD]  Starship/Matisse HD Audio Controller [1022:1487]
```

## 13. Software do servidor (contexto)

```text
Linux 7.0.14-23-pve
Debian GNU/Linux 13 (trixie)
pve-manager/9.2.21/4f6e0ac86f9e8c7f (running kernel: 7.0.14-23-pve)
kvm/modulos: 6
```

---

## Anexo — saidas completas (series e UUID omitidos)

### dmidecode -t system
```text
Handle 0x0001, DMI type 1, 27 bytes
System Information
	Manufacturer: System manufacturer
	Product Name: System Product Name
	Version: System Version
	Serial Number: (omitido)
	UUID: (omitido)
	Wake-up Type: Power Switch
	SKU Number: SKU
	Family: To be filled by O.E.M.
```

### dmidecode -t baseboard
```text
Handle 0x0002, DMI type 2, 15 bytes
Base Board Information
	Manufacturer: ASUSTeK COMPUTER INC.
	Product Name: TUF X470-PLUS GAMING
	Version: Rev X.0x
	Serial Number: (omitido)
	Asset Tag: (omitido)
	Features:
		Board is a hosting board
		Board is replaceable
	Location In Chassis: Default string
	Chassis Handle: 0x0003
	Type: Motherboard
	Contained Object Handles: 0
```

### dmidecode -t chassis
```text
Handle 0x0003, DMI type 3, 22 bytes
Chassis Information
	Manufacturer: Default string
	Type: Desktop
	Lock: Not Present
	Version: Default string
	Serial Number: (omitido)
	Asset Tag: (omitido)
	Boot-up State: Safe
	Power Supply State: Safe
	Thermal State: Safe
	Security Status: None
	OEM Information: 0x00000000
	Height: Unspecified
	Number Of Power Cords: 1
	Contained Elements: 0
	SKU Number: Default string
```

### dmidecode -t 8 (port connector)
```text
Handle 0x0004, DMI type 8, 9 bytes
Port Connector Information
	Internal Reference Designator: PS/2 Keyboard/Mouse
	Internal Connector Type: None
	External Reference Designator: PS/2 Keyboard/Mouse
	External Connector Type: PS/2
	Port Type: Keyboard Port
Handle 0x0005, DMI type 8, 9 bytes
Port Connector Information
	Internal Reference Designator: USB910
	Internal Connector Type: None
	External Reference Designator: USB910
	External Connector Type: Access Bus (USB)
	Port Type: USB
Handle 0x0006, DMI type 8, 9 bytes
Port Connector Information
	Internal Reference Designator: DVI
	Internal Connector Type: None
	External Reference Designator: DVI port
	External Connector Type: Other
	Port Type: Other
Handle 0x0007, DMI type 8, 9 bytes
Port Connector Information
	Internal Reference Designator: HDMI
	Internal Connector Type: None
	External Reference Designator: HDMI port
	External Connector Type: Other
	Port Type: Other
Handle 0x0008, DMI type 8, 9 bytes
Port Connector Information
	Internal Reference Designator: U31G1_C7
	Internal Connector Type: None
	External Reference Designator: U31G1_C7
	External Connector Type: Access Bus (USB)
	Port Type: USB
Handle 0x0009, DMI type 8, 9 bytes
Port Connector Information
	Internal Reference Designator: U31G2_12
	Internal Connector Type: None
	External Reference Designator: U31G2_12
	External Connector Type: Access Bus (USB)
	Port Type: USB
Handle 0x000A, DMI type 8, 9 bytes
Port Connector Information
	Internal Reference Designator: U31G1_56
	Internal Connector Type: None
	External Reference Designator: U31G1_56
	External Connector Type: Access Bus (USB)
	Port Type: USB
Handle 0x000B, DMI type 8, 9 bytes
Port Connector Information
	Internal Reference Designator: LAN
	Internal Connector Type: None
	External Reference Designator: LAN
	External Connector Type: RJ-45
	Port Type: Network Port
Handle 0x000C, DMI type 8, 9 bytes
Port Connector Information
	Internal Reference Designator: AUDIO
	Internal Connector Type: None
	External Reference Designator: AUDIO
	External Connector Type: Other
	Port Type: Audio Port
Handle 0x000D, DMI type 8, 9 bytes
Port Connector Information
	Internal Reference Designator: SATA6G_1
	Internal Connector Type: SAS/SATA Plug Receptacle
	External Reference Designator: Not Specified
	External Connector Type: None
	Port Type: SATA
Handle 0x000E, DMI type 8, 9 bytes
Port Connector Information
	Internal Reference Designator: SATA6G_2
	Internal Connector Type: SAS/SATA Plug Receptacle
	External Reference Designator: Not Specified
	External Connector Type: None
	Port Type: SATA
Handle 0x000F, DMI type 8, 9 bytes
Port Connector Information
	Internal Reference Designator: SATA6G_3
(o DMI desta placa nao publica a secao 8)
```

### dmidecode -t 27 (cooling device) e -t 39 (power supply)
```text
(o DMI desta placa nao publica as secoes 27 e 39)
```

### lspci (todos os dispositivos)
```text
00:00.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Starship/Matisse Root Complex [1022:1480]
00:00.2 IOMMU [0806]: Advanced Micro Devices, Inc. [AMD] Starship/Matisse IOMMU [1022:1481]
00:01.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Starship/Matisse PCIe Dummy Host Bridge [1022:1482]
00:01.3 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] Starship/Matisse GPP Bridge [1022:1483]
00:02.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Starship/Matisse PCIe Dummy Host Bridge [1022:1482]
00:03.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Starship/Matisse PCIe Dummy Host Bridge [1022:1482]
00:03.1 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] Starship/Matisse GPP Bridge [1022:1483]
00:04.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Starship/Matisse PCIe Dummy Host Bridge [1022:1482]
00:05.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Starship/Matisse PCIe Dummy Host Bridge [1022:1482]
00:07.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Starship/Matisse PCIe Dummy Host Bridge [1022:1482]
00:07.1 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] Starship/Matisse Internal PCIe GPP Bridge 0 to bus[E:B] [1022:1484]
00:08.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Starship/Matisse PCIe Dummy Host Bridge [1022:1482]
00:08.1 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] Starship/Matisse Internal PCIe GPP Bridge 0 to bus[E:B] [1022:1484]
00:14.0 SMBus [0c05]: Advanced Micro Devices, Inc. [AMD] FCH SMBus Controller [1022:790b] (rev 61)
00:14.3 ISA bridge [0601]: Advanced Micro Devices, Inc. [AMD] FCH LPC Bridge [1022:790e] (rev 51)
00:18.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Matisse/Vermeer Data Fabric: Device 18h; Function 0 [1022:1440]
00:18.1 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Matisse/Vermeer Data Fabric: Device 18h; Function 1 [1022:1441]
00:18.2 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Matisse/Vermeer Data Fabric: Device 18h; Function 2 [1022:1442]
00:18.3 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Matisse/Vermeer Data Fabric: Device 18h; Function 3 [1022:1443]
00:18.4 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Matisse/Vermeer Data Fabric: Device 18h; Function 4 [1022:1444]
00:18.5 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Matisse/Vermeer Data Fabric: Device 18h; Function 5 [1022:1445]
00:18.6 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Matisse/Vermeer Data Fabric: Device 18h; Function 6 [1022:1446]
00:18.7 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Matisse/Vermeer Data Fabric: Device 18h; Function 7 [1022:1447]
01:00.0 USB controller [0c03]: Advanced Micro Devices, Inc. [AMD] Device [1022:43d0] (rev 01)
01:00.1 SATA controller [0106]: Advanced Micro Devices, Inc. [AMD] 400 Series Chipset SATA Controller [1022:43c8] (rev 01)
01:00.2 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 400 Series Chipset PCIe Bridge [1022:43c6] (rev 01)
02:00.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 400 Series Chipset PCIe Port [1022:43c7] (rev 01)
02:01.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 400 Series Chipset PCIe Port [1022:43c7] (rev 01)
02:02.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 400 Series Chipset PCIe Port [1022:43c7] (rev 01)
02:03.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 400 Series Chipset PCIe Port [1022:43c7] (rev 01)
02:04.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 400 Series Chipset PCIe Port [1022:43c7] (rev 01)
02:09.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 400 Series Chipset PCIe Port [1022:43c7] (rev 01)
03:00.0 Ethernet controller [0200]: Realtek Semiconductor Co., Ltd. RTL8111/8168/8211/8411 PCI Express Gigabit Ethernet Controller [10ec:8168] (rev 15)
07:00.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 10 XL Upstream Port of PCI Express Switch [1002:1478] (rev c5)
08:00.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 10 XL Downstream Port of PCI Express Switch [1002:1479]
09:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 14 [Radeon RX 5500/5500M / Pro 5500M] [1002:7340] (rev c5)
09:00.1 Audio device [0403]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 10 HDMI Audio [1002:ab38]
0b:00.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 10 XL Upstream Port of PCI Express Switch [1002:1478] (rev c7)
0c:00.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 10 XL Downstream Port of PCI Express Switch [1002:1479]
0d:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 23 [Radeon RX 6600/6600 XT/6600M] [1002:73ff] (rev c7)
0d:00.1 Audio device [0403]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 21/23 HDMI/DP Audio Controller [1002:ab28]
0e:00.0 Non-Essential Instrumentation [1300]: Advanced Micro Devices, Inc. [AMD] Starship/Matisse PCIe Dummy Function [1022:148a]
0f:00.0 Non-Essential Instrumentation [1300]: Advanced Micro Devices, Inc. [AMD] Starship/Matisse Reserved SPP [1022:1485]
0f:00.1 Encryption controller [1080]: Advanced Micro Devices, Inc. [AMD] Starship/Matisse Cryptographic Coprocessor PSPCPP [1022:1486]
0f:00.3 USB controller [0c03]: Advanced Micro Devices, Inc. [AMD] Matisse USB 3.0 Host Controller [1022:149c]
0f:00.4 Audio device [0403]: Advanced Micro Devices, Inc. [AMD] Starship/Matisse HD Audio Controller [1022:1487]
```
