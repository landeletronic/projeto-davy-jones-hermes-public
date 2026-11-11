# Plano de uso das duas GPUs

> Estado: proposta, não implementação. Baseado nas medições de 2026-11-11 em
> [`../reports/BENCHMARK-GPUS-2026-11-11.md`](../reports/BENCHMARK-GPUS-2026-11-11.md).

## 1. Objetivo

Usar a RX 6600 e a RX 5500 XT com ganho real de capacidade ou throughput sem
degradar o chat, sem fallback silencioso para CPU e sem transformar o runtime
experimental em dependência da stack principal.

## 2. Restrições comprovadas

- RX 6600: 8 GB, Ollama/ROCm funcional com override `gfx1030`;
- RX 5500 XT: 8 GB, Vulkan/RADV funcional, mas o rocBLAS da imagem Ollama não
  suporta seu alvo nativo `gfx1012`;
- mascarar a RX 5500 como `gfx1030` provoca `MEMORY_APERTURE_VIOLATION`;
- as placas não têm P2P pelo chipset; transferências entre elas passam pelo host;
- benchmark simultâneo é estável, mas reduziu o score da RX 6600 em 16,09% e o
  da RX 5500 em 6,23%; há recurso compartilhado;
- 8 GB + 8 GB não viram uma alocação única de 16 GB. Um runtime pode particionar
  pesos, camadas e KV entre placas, mas cada buffer continua pertencendo a uma GPU.

## 3. Alternativas

### Topologia PCIe física medida

A VM mostra as duas GPUs como `16 GT/s ×16`, mas esses são root ports virtuais do
QEMU e não representam o enlace físico. A medição válida foi feita no Proxmox
`pve-tuf-x470`, placa-mãe ASUS TUF X470-PLUS GAMING e Ryzen 7 5700X:

| GPU | Slot físico | Caminho | Link efetivo | Banda teórica por direção |
|---|---|---|---|---:|
| RX 6600 | `PCIEX16_1` | direto na CPU | PCIe 3.0 ×8 (`8 GT/s ×8`) | ~7,88 GB/s |
| RX 5500 XT | `PCIEX16_2` | chipset X470 | PCIe 2.0 ×4 (`5 GT/s ×4`) | ~2,00 GB/s |

Os dois conectores têm comprimento físico ×16, mas o DMI declara o segundo como
×4 elétrico. O endpoint da GPU pode mostrar um link interno `16 GT/s ×16`; o limite
real é o elo mais estreito do caminho. Na RX 5500, esse elo é o upstream do segundo
slot em `5 GT/s ×4`, além de compartilhar o uplink do chipset com outros dispositivos.

A RX 6600 está correta em Gen3 ×8: a placa usa oito lanes e o X470 negocia Gen3.
A RX 5500 também está de acordo com o projeto da placa-mãe, mas tem aproximadamente
um quarto da banda PCIe da RX 6600. Para obter duas GPUs com links rápidos seria
necessária uma plataforma que ofereça bifurcação CPU ×8/×8 aos dois slots; trocar
as placas de posição apenas penalizaria a GPU principal.

Essa topologia reforça cargas independentes. `split-mode layer` ainda pode ser
medido porque transfere menos que tensor parallelism, mas `split-mode tensor` fica
ainda menos indicado: não há P2P e a RX 5500 está atrás de PCIe 2.0 ×4/chipset.

### A. Duas cargas independentes — recomendada

```text
RX 6600 / Ollama ROCm
  qwen3:4b-64k + bge-m3 (produção atual)

RX 5500 XT / llama.cpp Vulkan
  segundo modelo ou tarefa independente
```

Vantagens:

- não exige comunicação GPU↔GPU por token;
- uma placa indisponível não derruba a outra;
- aumenta throughput: duas solicitações diferentes podem executar em paralelo;
- mantém o runtime comprovado da RX 6600;
- permite usar a RX 5500 via RADV, caminho que passou no benchmark.

Primeira carga candidata para a RX 5500: `qwen3:8b-chat-16k` do chat de estudo.
Ele é independente do gateway Hermes, já usa uma conexão local separada no Open
WebUI e cabe em 8 GB na quantização atual. O piloto deve usar uma cópia GGUF com
SHA-256, não o volume produtivo do Ollama.

Segunda candidata, depois do chat de estudo: embeddings `bge-m3`. Isso pode evitar
que embeddings disputem residência com o chat principal, mas exige configurar um
endpoint de embeddings compatível ou um adaptador mínimo de API. Não começar por
essa migração porque RAG, mem0 e ingestão dependem dela.

### B. Um modelo repartido entre as duas GPUs — experimental

O llama.cpp atual oferece `--split-mode layer` e `--tensor-split`. Isso aumenta a
capacidade para modelos que não cabem em 8 GB, mas não cria VRAM unificada.

Modo inicial permitido para teste:

```text
--split-mode layer
--device Vulkan0,Vulkan1
--tensor-split 60,40       # ponto inicial, não decisão final
--n-gpu-layers all
```

`layer` usa pipeline: cada placa guarda um conjunto de camadas e o KV das próprias
camadas. É o modo mais compatível e tolera melhor interconexão lenta. A proporção
60/40 favorece a RX 6600, que foi aproximadamente 30% mais rápida isolada; devem ser
medidos também 50/50, 65/35 e o ajuste automático.

Não usar inicialmente:

- `--split-mode tensor`: experimental, sem garantia no backend Vulkan, exige
  comunicação frequente e não aceita KV quantizado;
- P2P: o kernel já informou que o chipset não o suporta;
- um modelo crítico de produção: a RX 5500 passa a ser ponto único de falha junto
  com a RX 6600.

Uso esperado: experimentar um modelo 8B/14B ou contexto maior que não caiba numa
placa. Não assumir ganho de tokens/s; o objetivo inicial é capacidade.

### C. Dois Ollamas

Um Ollama Vulkan compilado localmente poderia atender a RX 5500 e preservar APIs
`/api/generate` e `/api/embed`. É viável, mas cria uma segunda imagem customizada e
oferece menos controle explícito de split, dispositivos e parâmetros que o
`llama-server`.

Decisão: não é a primeira opção. Só comparar com llama.cpp depois que o piloto
Vulkan estiver medido. O Ollama ROCm atual continua exclusivo da RX 6600.

### D. Fork ou solução própria de inferência

Não criar um fork de llama.cpp. A solução personalizada deve ser composição, não
um novo motor:

- imagem construída de commit upstream pinado;
- `llama-server` com parâmetros versionados;
- healthcheck e métricas;
- endpoint somente em loopback/rede Docker interna;
- opcionalmente um adaptador pequeno para a API esperada pelo consumidor;
- roteamento explícito por modelo, sem scheduler “inteligente” na primeira fase.

Isso mantém atualização e correções no upstream e reduz código próprio.

## 4. Arquitetura recomendada

```text
Open WebUI / Hermes
        |
        +--> Ollama ROCm :11434 --------> RX 6600
        |      qwen3:4b-64k, bge-m3
        |
        +--> llama-server Vulkan --------> RX 5500 XT
               qwen3:8b-chat-16k
```

Cada modelo tem um destino fixo. Não há balanceamento automático entre placas. Se
o runtime da RX 5500 cair, somente o modelo secundário fica indisponível; o Hermes,
RAG e embeddings continuam na RX 6600.

## 5. Fases e gates

### Fase 0 — preservar baseline

- backup recente e suíte sem falhas operacionais;
- manter `ROCR_VISIBLE_DEVICES=0` no Ollama;
- registrar tokens/s, TTFT, VRAM e qualidade atuais na RX 6600.

### Fase 1 — llama.cpp Vulkan na RX 5500

- build em container a partir de commit pinado, sem instalar compilador no host;
- `--list-devices` deve identificar somente a RX 5500 selecionada;
- volume/modelo de staging separado e porta somente em loopback;
- provar GGUF por SHA-256;
- modelo totalmente na VRAM, sem camada em CPU;
- medir 4k e 16k: carga, prompt processing, geração, VRAM, temperatura e potência;
- testar 30 minutos e conferir kernel sem reset/page fault.

Gate: só integrar se a saída for correta, não houver CPU offload e a latência for
útil para o chat de estudo.

### Fase 2 — integração como serviço secundário

- conexão separada no Open WebUI;
- usuário comum enxerga somente o modelo autorizado;
- healthcheck real e política `restart` documentada;
- sem `docker.sock`, `.ssh`, banco ou segredo desnecessário;
- teste de regressão na suíte e card do serviço;
- falha do serviço secundário não pode afetar o Ollama principal.

### Fase 3 — concorrência real

- pergunta no Hermes/RX 6600 e estudo/RX 5500 ao mesmo tempo;
- comparar p50/p95, tokens/s, CPU, RAM, temperatura e potência com o baseline;
- verificar se a queda simultânea é aceitável e se a fonte suporta a carga.

### Fase 4 — VRAM repartida, laboratório

Somente após as fases anteriores. Matriz mínima:

| Variável | Valores |
|---|---|
| split | automático, 50/50, 60/40, 65/35 |
| contexto | 4k, 16k, 64k quando suportado |
| modelo | 8B Q4, depois candidato 14B Q4 |
| carga | prompt curto, prompt longo, duas sequências |

Critérios: modelo integral nas GPUs, zero CPU offload, sem erro de kernel, resposta
correta, memória com margem e resultado melhor que CPU/offload. Se ficar mais lento
que um modelo menor em uma GPU, classificar como ganho de capacidade, não desempenho.

## 6. Métricas obrigatórias

- tempo de carga;
- TTFT;
- prompt tokens/s e generation tokens/s;
- VRAM de cada GPU e RAM do host;
- camadas/processador reportados pelo runtime;
- temperatura edge/junction e potência;
- erros `amdgpu`, KFD e Vulkan;
- p50/p95 sob concorrência;
- qualidade funcional nos smokes existentes.

Enumeração da GPU isoladamente não é sucesso.

## 7. Decisão proposta

1. manter Ollama ROCm + RX 6600 como produção;
2. criar `llama-server` Vulkan de staging exclusivo para a RX 5500;
3. pilotar `qwen3:8b-chat-16k` na RX 5500;
4. integrar como segundo endpoint somente após benchmark de LLM;
5. testar VRAM repartida apenas como laboratório, com `split-mode layer`;
6. não usar `split-mode tensor`, P2P, fork de llama.cpp ou roteamento automático
   antes de existir medição que justifique a complexidade.

## 8. Rollback

Remover o container de staging e sua conexão, sem tocar no volume do Ollama. A RX
6600 permanece com `ROCR_VISIBLE_DEVICES=0`. Rodar o oráculo e confirmar novamente
`qwen3:4b-64k` e `bge-m3` em 100% GPU.
