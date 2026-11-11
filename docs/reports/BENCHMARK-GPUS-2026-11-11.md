# Benchmark das GPUs — 2026-11-11

## Objetivo

Validar as duas GPUs do `davy-jones-hermes` fora do Ollama antes de decidir como
expô-las ao runtime de inferência. O teste mede enumeração Vulkan, estabilidade,
repetibilidade, temperatura, potência e execução simultânea. Ele não prova suporte
ROCm, inferência de LLM, P2P nem soma das duas VRAMs.

## Estado inicial

- host: Ubuntu 26.04, kernel `7.0.0-43-generic`;
- RX 6600: PCI `0000:01:00.0`, ID `1002:73ff`, 8 GB;
- RX 5500 XT: PCI `0000:03:00.0`, ID `1002:7340`, 8 GB;
- as duas usam o driver de kernel `amdgpu` e aparecem como nós KFD;
- o oráculo estava vermelho porque o Ollama carregava `qwen3:4b-64k` em CPU;
- o container `ollama` foi parado durante todo o benchmark para não disputar GPU.

## Ferramentas instaladas no host

| Pacote | Versão |
|---|---|
| `mesa-vulkan-drivers` | `26.0.8-1ubuntu0.3` |
| `vulkan-tools` | `1.4.341.0+dfsg1-1` |
| `vkmark` | `2025.01-1build1` |

A instalação adicionou 21 pacotes e aproximadamente 176 MB. Nenhum serviço ou
container precisou ser reiniciado pela instalação.

## Método

O `vulkaninfo --summary` enumerou as duas placas pelo Mesa RADV 26.0.8:

```text
AMD Radeon RX 6600 (RADV NAVI23)   1002:73ff
AMD Radeon RX 5500 XT (RADV NAVI14) 1002:7340
```

Cada placa foi isolada pelo ID PCI com `MESA_VK_DEVICE_SELECT=<vendor:device>!`.
O `!` faz o Mesa expor somente o dispositivo escolhido. O `vkmark` usou o backend
`headless`, resolução 1920×1080 e seis cenas de 5 segundos: `vertex`, `texture`
com anisotropia 16, `shading` Phong, `effect2d` blur, `cube` e `clear`.

Exemplo reproduzível para a RX 6600:

```bash
MESA_VK_DEVICE_SELECT='1002:73ff!' vkmark --winsys headless --size 1920x1080 \
  -b vertex:duration=5 \
  -b texture:texture-filter=linear:anisotropy=16:duration=5 \
  -b shading:shading=phong:duration=5 \
  -b effect2d:background-resolution=1920x1080:kernel=blur:duration=5 \
  -b cube:duration=5 \
  -b clear:duration=5
```

Durante cada rodada, `gpu_busy_percent`, VRAM, temperatura edge/junction e potência
foram amostrados a cada 200 ms pelo `sysfs`. Foram executadas três rodadas isoladas
por placa e uma rodada com as duas em paralelo.

## Resultado isolado

| GPU | Rodada 1 | Rodada 2 | Rodada 3 | Média | Variação | Ocupação | Junction máx. | Potência máx. |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| RX 6600 | 31.096 | 30.862 | 30.482 | 30.813 | 1,99% | 99% | 75 °C | 100 W |
| RX 5500 XT | 23.842 | 23.839 | 23.694 | 23.792 | 0,62% | 99% | 79 °C | 128 W amostrados |

As três rodadas de cada placa terminaram com exit code zero. Não houve reset, timeout,
page fault ou novo erro `amdgpu`/KFD no kernel. A RX 5500 XT apresentou potência
amostrada de 128 W apesar de `power1_cap` publicar 120 W; esse contador é telemetria
do driver, não medição na tomada, e deve ser observado em testes longos.

## Resultado simultâneo

| GPU | Score simultâneo | Queda contra média isolada | Ocupação | Junction máx. | Potência máx. |
|---|---:|---:|---:|---:|---:|
| RX 6600 | 25.856 | 16,09% | 99% | 74 °C | 100 W |
| RX 5500 XT | 22.309 | 6,23% | 99% | 78 °C | 120 W |

As duas placas permaneceram em 99% ao mesmo tempo e ambos os processos terminaram
com exit code zero. A queda de desempenho indica compartilhamento de algum recurso
do host (CPU, PCIe, memória ou energia), mas o benchmark não isola qual deles. O
kernel informa que P2P entre `01:00.0` e `03:00.0` não é suportado pelo chipset;
este teste executou cargas independentes e não usou P2P.

## Achados e limites

1. **Estado comprovado:** as duas GPUs funcionam separadas e simultâneas via Vulkan/RADV.
2. **Estado comprovado:** o problema anterior de CPU no Ollama não é uma falha geral
   das placas, do driver `amdgpu` ou da alimentação sob esta carga.
3. **Ainda não comprovado:** a RX 5500 XT no ROCm empacotado pelo Ollama. O Ollama
   0.40.2 anunciava somente a RX 6600 na descoberta.
4. **Ainda não comprovado:** carga de VRAM próxima de 8 GB. O `vkmark` usou somente
   cerca de 68 MB na RX 6600 e 58 MB na RX 5500 XT.
5. **Ainda não comprovado:** dividir um modelo entre as placas. O benchmark valida
   cargas independentes; 8 GB + 8 GB não formam automaticamente 16 GB unificados.
6. O `vkmark 2025.01` imprimiu o mesmo `Device UUID` para as duas placas. A seleção
   foi validada pelo ID `1002:73ff`/`1002:7340`, nome RADV e telemetria do `card1`/
   `card2`; não usar esse UUID do `vkmark` como identidade neste host.
7. Medição posterior no Proxmox físico mostrou RX 6600 direta na CPU em PCIe 3.0
   ×8 (~7,88 GB/s por direção) e RX 5500 via chipset em PCIe 2.0 ×4 (~2,00 GB/s).
   Os slots têm tamanho físico ×16, mas o segundo é ×4 elétrico por projeto da ASUS
   TUF X470-PLUS GAMING. O `16 GT/s ×16` visto dentro da VM é topologia virtual e
   não deve ser usado para dimensionar multi-GPU.

## Falha reproduzida no Ollama após o benchmark

Ao restaurar o container sem filtro de dispositivo, o Ollama 0.40.2 passou a detectar
as duas placas. Como `HSA_OVERRIDE_GFX_VERSION=10.3.0` era global, o log anunciou
incorretamente tanto a RX 6600 quanto a RX 5500 XT como `gfx1030`. O runtime dividiu
o `qwen3:4b-64k` entre `ROCm0` e `ROCm1`; o `bge-m3` também tentou a RX 5500.
Ambos abortaram durante a carga com:

```text
HSA_STATUS_ERROR_MEMORY_APERTURE_VIOLATION
The agent attempted to access memory beyond the largest legal address.
```

Isso explica a diferença entre o benchmark Vulkan saudável e a falha do Ollama: o
hardware e o RADV funcionam, mas o override ROCm específico da RX 6600 é inválido
para a RX 5500 XT.

Correção aplicada: `ROCR_VISIBLE_DEVICES=0` no serviço `ollama`, fixando a produção
na RX 6600 (PCI `01:00.0`). A suíte ganhou um teste de regressão para impedir que a
RX 5500 volte a receber o override global. A segunda placa permanece disponível no
host para staging isolado.

## Gate ROCm isolado da RX 5500 XT

Depois de restaurar a produção na RX 6600, foi criado um container temporário com a
mesma imagem do Ollama, porta somente em `127.0.0.1:11435`, modelos produtivos
montados como somente leitura e `ROCR_VISIBLE_DEVICES=1`. O container não montou
bancos nem publicou porta na LAN e foi removido ao final.

Sem `HSA_OVERRIDE_GFX_VERSION`, o Ollama identificou corretamente a placa como
`gfx1012`, mas a descartou porque o rocBLAS da imagem não contém esse alvo:

```text
dropping ROCm device — no rocblas support for gfx target
gfx_target=gfx1012
supported=gfx1030,gfx1100,gfx1101,gfx1102,gfx1150,gfx1151,gfx1200,gfx1201,
          gfx908,gfx90a,gfx942,gfx950
```

O `bge-m3` respondeu com 1024 dimensões, porém `ollama ps` comprovou `100% CPU`.
Já o teste com `HSA_OVERRIDE_GFX_VERSION=10.3.0` havia abortado com
`MEMORY_APERTURE_VIOLATION`. Portanto:

- **Vulkan/RADV:** RX 5500 XT aprovada;
- **ROCm 7.2 da imagem Ollama atual:** RX 5500 XT reprovada;
- **fallback para CPU:** não é sucesso e não autoriza uso em produção;
- **produção:** somente RX 6600, comprovada com `qwen3:4b-64k` 5,6 GB/100% GPU e
  `bge-m3` 664 MB/100% GPU, ambos residentes ao mesmo tempo.

## Decisão recomendada

Não habilitar multi-GPU no Ollama. A produção deve permanecer restrita à RX 6600.
O próximo gate deve testar o runtime de
inferência de forma controlada:

1. RX 6600 isolada, exigindo modelo integral na GPU;
2. RX 5500 XT isolada, sem aceitar fallback para CPU;
3. não executar modelo na RX 5500 com esta imagem ROCm; um runtime Vulkan separado
   poderá ser avaliado futuramente;
4. divisão de um único modelo apenas como experimento posterior, porque não há P2P.

Em cada gate, a prova é o uso real de VRAM/processador e a taxa medida de tokens, não
apenas a enumeração do dispositivo.

## Validação final da stack

Após recriar somente o `ollama`, a suíte confirmou:

- `ROCR_VISIBLE_DEVICES=0` presente;
- `qwen3:4b-64k` integral na RX 6600, 5,6 GB e 100% GPU;
- `bge-m3` integral na RX 6600, 664 MB e 100% GPU;
- os dois modelos residentes simultaneamente;
- embedding com 1024 dimensões;
- Tutor Tiradentes e Apostilas Tiradentes aprovados.

Resultado: `PASS=268 / FAIL=2 / WARN=2`. As duas falhas remanescentes já existiam
antes do benchmark e não são de GPU: backup com aproximadamente 230 horas e poda de
retenção pendente. Os avisos são os alertas correspondentes e o CI atrasado desde o
período em que o host ficou desligado. Nenhum backup antigo foi apagado durante este
trabalho.
