# Inventario de hardware — servidor fisico do lab

> Gerado em **2026-10-23T13:54:46-03:00** por `tools/inventario_hardware.sh` (somente leitura) no host
> `pve-aorus` (`systemd-detect-virt = none`).
> Fontes: DMI/SMBIOS (`dmidecode`), `lspci`, `lsusb`, `ip`, `pveversion`.
> **Numeros de serie, UUID e asset tag foram omitidos de proposito.**

## Resumo

| Dispositivo | Fabricante | Modelo / descricao | Fonte |
|---|---|---|---|
| Placa-mae | ASRock | B660M-HDV | DMI tipo 2 |
| Processador | Intel(R) Corporation | 13th Gen Intel(R) Core(TM) i7-13700 — 16 nucleos / 24 threads | DMI tipo 4 |
| Memoria | Kingston | 2x 16 GB KF3200C16D4/16GX (2400 MT/s) — 31Gi visiveis | DMI tipo 17 |
| GPU | Advanced Micro Devices, Inc. [AMD/ATI] | Navi 23 [Radeon RX 6600/6600 XT/6600M]  (ASRock Incorporation)  [1002:73ff] | `lspci` |
| Rede | Intel Corporation | Ethernet Connection (17) I219-V  (ASRock Incorporation)  [8086:1a1d] | `lspci` |
| USB 3.x | 10 porta(s) | root hub usb2 | `/sys` |
| USB 2.0 | 16 porta(s) | root hub usb1 | `/sys` |
| USB 3.x/USB4 | 1 controlador(es) | Intel Corporation Alder Lake-S PCH USB 3.2 Gen 2x2 XHCI Controller | `lspci` |
| Audio | Intel Corporation | Alder Lake-S HD Audio Controller  (ASRock Incorporation) | `lspci` |
| Audio | Advanced Micro Devices, Inc. [AMD/ATI] | Navi 21/23 HDMI/DP Audio Controller | `lspci` |
| Cooler / watercooler | ver secao 6 | ver secao 6 | DMI tipo 27 / sensores / USB |
| Fonte (PSU) | ver secao 7 | ver secao 7 | DMI tipo 39 / IPMI |
| Gabinete | To Be Filled By O.E.M. | Desktop — To Be Filled By O.E.M. | DMI tipo 3 |
| Portas do painel | — | 0 porta(s) no DMI (serial, PS-2, USB, video, audio) | DMI tipo 8 |

## 1. Placa-mae

```text
Handle 0x0002, DMI type 2, 15 bytes
Base Board Information
	Manufacturer: ASRock
	Product Name: B660M-HDV
	Version:
	Serial Number: (omitido)
	Asset Tag: (omitido)
	Features:
		Board is a hosting board
		Board is replaceable
	Location In Chassis:
	Chassis Handle: 0x0003
	Type: Motherboard
	Contained Object Handles: 0
```

ASRock **B660M-HDV**.

## 2. Processador

```text
Socket Designation: CPUSocket
Type: Central Processor
Family: Core i7
Manufacturer: Intel(R) Corporation
Signature: Type 0, Family 6, Model 183, Stepping 1
Version: 13th Gen Intel(R) Core(TM) i7-13700
Max Speed: 5200 MHz
Current Speed: 2079 MHz
Core Count: 16
Core Enabled: 16
Thread Count: 24
```

Intel(R) Corporation **13th Gen Intel(R) Core(TM) i7-13700** — 16 nucleos / 24 threads.

## 3. Memoria

```text
Size: 16 GB
Form Factor: DIMM
Locator: Controller0-ChannelA-DIMM0
Type Detail: Synchronous
Speed: 2400 MT/s
Manufacturer: Kingston
Part Number: KF3200C16D4/16GX
Configured Memory Speed: 2400 MT/s
Size: 16 GB
Form Factor: DIMM
Locator: Controller1-ChannelA-DIMM0
Type Detail: Synchronous
Speed: 2400 MT/s
Manufacturer: Kingston
Part Number: KF3200C16D4/16GX
Configured Memory Speed: 2400 MT/s
```

## 4. Placas de video

```text
03:00.0  Advanced Micro Devices, Inc. [AMD/ATI]  Navi 23 [Radeon RX 6600/6600 XT/6600M]  (ASRock Incorporation) [1002:73ff]
```
Driver em uso: **vfio-pci**

> `vfio-pci` = a placa esta reservada para *passthrough* a uma VM: o servidor nao usa video proprio
> e o HDMI/DisplayPort da placa nao da imagem. O console e SSH/serial.

## 5. BIOS

```text
Handle 0x0000, DMI type 0, 26 bytes
BIOS Information
	Vendor: American Megatrends International, LLC.
	Version: 20.01
	Release Date: 11/27/2025
	Address: 0xF0000
	Runtime Size: 64 kB
	ROM Size: 16 MB
	Characteristics:
		PCI is supported
		BIOS is upgradeable
		BIOS shadowing is allowed
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
	Manufacturer: To Be Filled By O.E.M.
	Type: Desktop
	Lock: Not Present
	Version: To Be Filled By O.E.M.
	Serial Number: (omitido)
	Asset Tag: (omitido)
	Boot-up State: Safe
	Power Supply State: Safe
	Thermal State: Safe
	Security Status: None
```

To Be Filled By O.E.M. — Desktop (To Be Filled By O.E.M.).
> **Default string** = a placa-mae nao informa o gabinete (normal em maquina montada).
> Modelo so por inspecao fisica.

## 9. Rede

```text
00:1f.6  Intel Corporation  Ethernet Connection (17) I219-V [8086:1a1d]
```
Driver: e1000e
Interfaces fisicas: enp0s31f6 (UP)

## 10. USB

Geracao vem do *prog-if* do controlador (00=UHCI e 10=OHCI => USB 1.1; 20=EHCI => USB 2.0;
30/40=xHCI => USB 3.x/USB4).

| Slot | Fabricante | Controlador | Geracao | IDs |
|---|---|---|---|---|
| 00:14.0 | Intel Corporation | Alder Lake-S PCH USB 3.2 Gen 2x2 XHCI Controller | USB 3.x (xHCI) | [8086:7ae0] |

Controladores PCI: **0** USB 1.1, **0** USB 2.0, **1** USB 3.x/USB4.
Portas por root hub: usb1: USB 2.0, 16 porta(s); usb2: USB 3.x, 10 porta(s)

> Onde o controlador PCI e um so (xHCI de chipset moderno), as portas USB 2.0 **nao**
> aparecem como EHCI: elas penduram no *root hub* USB 2.0 do proprio xHCI. E o caso das
> placas Alder Lake/Raptor Lake — por isso a contagem util e a de root hubs, acima.

Dispositivos conectados agora:

```text
Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
Bus 002 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
```

## 11. Portas do painel (DMI tipo 8)

| Designador externo | Conector | Tipo de porta |
|---|---|---|
| — | — | o DMI desta placa nao publica a secao 8 |

> Sem a secao 8, serial/PS-2/video so por inspecao fisica: essas portas ficam no
> Super I/O e nao aparecem no `lspci`.
> HDMI/DisplayPort nao aparecem no DMI: quem os expoe e a **GPU** (secao 4). Porta serial e PS-2,
> quando existem, ficam no Super I/O — so aparecem aqui.

## 12. Audio

```text
00:1f.3  Intel Corporation  Alder Lake-S HD Audio Controller [8086:7ad0]
03:00.1  Advanced Micro Devices, Inc. [AMD/ATI]  Navi 21/23 HDMI/DP Audio Controller [1002:ab28]
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
	Manufacturer: ASRock
	Product Name: B660M-HDV
	Version: To Be Filled By O.E.M.
	Serial Number: (omitido)
	UUID: (omitido)
	Wake-up Type: Power Switch
	SKU Number: To Be Filled By O.E.M.
	Family: To Be Filled By O.E.M.
```

### dmidecode -t baseboard
```text
Handle 0x0002, DMI type 2, 15 bytes
Base Board Information
	Manufacturer: ASRock
	Product Name: B660M-HDV
	Version:
	Serial Number: (omitido)
	Asset Tag: (omitido)
	Features:
		Board is a hosting board
		Board is replaceable
	Location In Chassis:
	Chassis Handle: 0x0003
	Type: Motherboard
	Contained Object Handles: 0
```

### dmidecode -t chassis
```text
Handle 0x0003, DMI type 3, 22 bytes
Chassis Information
	Manufacturer: To Be Filled By O.E.M.
	Type: Desktop
	Lock: Not Present
	Version: To Be Filled By O.E.M.
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
	SKU Number: To Be Filled By O.E.M.
```

### dmidecode -t 8 (port connector)
```text
(o DMI desta placa nao publica a secao 8)
```

### dmidecode -t 27 (cooling device) e -t 39 (power supply)
```text
(o DMI desta placa nao publica as secoes 27 e 39)
```

### lspci (todos os dispositivos)
```text
00:00.0 Host bridge [0600]: Intel Corporation Raptor Lake-S Host Bridge/DRAM Controller [8086:a703] (rev 01)
00:01.0 PCI bridge [0604]: Intel Corporation Raptor Lake PCI Express 5.0 Graphics Port (PEG010) [8086:a70d] (rev 01)
00:14.0 USB controller [0c03]: Intel Corporation Alder Lake-S PCH USB 3.2 Gen 2x2 XHCI Controller [8086:7ae0] (rev 11)
00:14.2 RAM memory [0500]: Intel Corporation Alder Lake-S PCH Shared SRAM [8086:7aa7] (rev 11)
00:15.0 Serial bus controller [0c80]: Intel Corporation Alder Lake-S PCH Serial IO I2C Controller #0 [8086:7acc] (rev 11)
00:16.0 Communication controller [0780]: Intel Corporation Alder Lake-S PCH HECI Controller #1 [8086:7ae8] (rev 11)
00:17.0 SATA controller [0106]: Intel Corporation Alder Lake-S PCH SATA Controller [AHCI Mode] [8086:7ae2] (rev 11)
00:1f.0 ISA bridge [0601]: Intel Corporation B660 Chipset LPC/eSPI Controller [8086:7a86] (rev 11)
00:1f.3 Audio device [0403]: Intel Corporation Alder Lake-S HD Audio Controller [8086:7ad0] (rev 11)
00:1f.4 SMBus [0c05]: Intel Corporation Alder Lake-S PCH SMBus Controller [8086:7aa3] (rev 11)
00:1f.5 Serial bus controller [0c80]: Intel Corporation Alder Lake-S PCH SPI Controller [8086:7aa4] (rev 11)
00:1f.6 Ethernet controller [0200]: Intel Corporation Ethernet Connection (17) I219-V [8086:1a1d] (rev 11)
01:00.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 10 XL Upstream Port of PCI Express Switch [1002:1478] (rev c7)
02:00.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 10 XL Downstream Port of PCI Express Switch [1002:1479]
03:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 23 [Radeon RX 6600/6600 XT/6600M] [1002:73ff] (rev c7)
03:00.1 Audio device [0403]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 21/23 HDMI/DP Audio Controller [1002:ab28]
```
