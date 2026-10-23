# Davy Jones GPT — Contexto para continuidade

**Data da consolidação:** 20/10/2026  
**Fonte:** conversas deste tópico, inclusive relatório consolidado anterior.  
**Escopo:** síntese de decisões, arquitetura, estado conhecido e próximos passos. **Não constitui inventário atual de hardware nem verificação ao vivo.**

## 1. Objetivo

Construir o **Davy Jones GPT**, laboratório/plataforma de IA local e autônoma, com soluções **gratuitas e open source**, voltado a TI, Jurídico, Contábil e preparação para concursos da Magistratura. Prevê interface web, LLMs locais, agentes com ferramentas, memória, RAG, processamento documental, busca web e automações com permissões.

## 2. Arquitetura prevista (não confundir com serviços já implantados)

- **Proxmox VE → VM Ubuntu Server → Docker/Compose**; preferir um contêiner por serviço.
- **Open WebUI:** interface.
- **Hermes Agent:** orquestração, agentes, ferramentas e autorizações; não usar Open WebUI Pipelines como middleware central.
- **Ollama** e, para testes, **llama.cpp:** inferência local.
- **Memória:** Honcho constava da arquitetura inicial deste tópico; decisão/implantação final ainda precisa ser reconfirmada.
- **RAG independente:** Docling → metadados e chunking estruturado → embeddings → Qdrant + BM25 → RRF → reranking → construção de contexto → Hermes/LLM.
- **SearXNG:** busca na internet; ferramentas via APIs/OpenAPI/MCP.
- Para Jurídico/Contábil: evidências, fontes, metadados temporais e versões. Para Magistratura: estudos e questões estruturadas.
- Ações operacionais separadas em **READ / WRITE / DESTRUCTIVE**; operações destrutivas exigem confirmação.

## 3. Regras de implementação

1. Priorizar software gratuito/open source.
2. Automatizar instalações/configurações com scripts **quando expressamente autorizados**; não gerar scripts sem pedido/autorização.
3. Cada script deve validar o que realizou, ser idempotente quando viável e ter documentação de reinstalação/diagnóstico.
4. Modo `verify` **estritamente somente leitura**: sem APT, criação de arquivos, correção de permissões ou outras alterações.
5. `.sh` e `.md` devem ter **exatamente o mesmo nome-base**.
6. Preservar serviços/configurações já funcionais; evitar `chmod -R 777` e `chown -R` indiscriminados.
7. Não alterar Proxmox, GRUB, VFIO ou passthrough sem autorização explícita.
8. Registrar **estado comprovado**, separado de intenção, hipótese ou teste futuro.
9. **Requisito de inferência:** LLM integralmente na VRAM da(s) GPU(s), sem offload de camadas para CPU/RAM; comprovar isso por medição, não apenas pela enumeração da GPU.

## 4. Hardware e virtualização conhecidos no tópico

| Item | Informação registrada | Observação |
|---|---|---|
| CPU física | AMD Ryzen 7 5700X | Relatada |
| Placa-mãe | Gigabyte B550M Aorus Elite | Relatada |
| Host | Proxmox VE 9.2 | Relatado |
| VM | `davy-jones`, VMID `10003` | Relatada |
| SO convidado | Ubuntu Server 26.04.1 LTS | Confirmado em execução de script |
| vCPU | 8 | Configuração relatada |
| Disco VM | Aproximadamente 1 TB | Relatado |
| RAM física | Temporariamente 16 GB por problema nos módulos; previsão de 32 GB | **Retorno a 32 GB não confirmado** |
| RAM VM | Temporariamente 8 GB; previsão de 16 GB | **Retorno a 16 GB não confirmado** |
| GPU funcional | ASRock Radeon RX 6600, 8 GB, Navi 23, PCI `1002:73ff` | `amdgpu` e RADV validados |
| GPU adicional | Radeon RX 5700, 8 GB | **Ideia/proposta, não instalação confirmada** |

A RX 5500 XT anterior apresentou problemas de inicialização/reset e foi substituída pela RX 6600. Não retomar diagnóstico da placa antiga sem solicitação.

### Duas GPUs — hipótese de expansão

- **Modo 1 (preferencial para começar):** RX 6600 executa um LLM e RX 5700 executa outro LLM ou tarefas paralelas.
- **Modo 2 (experimental):** dividir um único modelo entre RX 6600 e RX 5700 usando runtime com suporte multi-GPU, sujeito a compatibilidade, overhead PCIe e benchmarks.
- **8 GB + 8 GB não equivalem automaticamente a uma GPU de 16 GB** nem a VRAM unificada.
- A RX 5700 (Navi 10/RDNA 1) e a RX 6600 (Navi 23/RDNA 2) são heterogêneas.
- ROCm não foi escolhido como caminho principal nesta etapa, devido às limitações de suporte oficial dessas GPUs; **Vulkan/Mesa RADV** é o caminho experimental priorizado.

## 5. Infraestrutura Docker validada

- Docker Engine 29.8.0, Compose v5.5.1 e Buildx v0.37.0 foram reportados e testados; `hello-world` funcionou.
- Rede bridge interna **`davy-jones-internal`**, `172.30.0.0/24`, `internal: true`.
- Diretório-base **`/opt/davy-jones/`** com `compose/`, `config/`, `secrets/`, `data/`, `logs/`, `models/`, `backups/`, `scripts/`, `tmp/`, `run/`.
- `compose/compose.yaml` foi preparado com rede externa, **sem serviços de aplicação** naquele momento.
- Dados persistentes preferencialmente em bind mounts sob `/opt/davy-jones`; determinar UID/GID de cada imagem antes de alterar ownership.
- `secrets/` com permissões restritas; demais diretórios com política conservadora.

## 6. Etapas executadas e situação conhecida

| Etapa | Resultado conhecido |
|---|---|
| 2 — Docker/Compose | Instalado e validado |
| 3.1 — Diretórios | PASS |
| 3.3 — Rede Docker | PASS |
| 3.4 — Política de armazenamento | PASS |
| 3.5 — Compose base | PASS |
| 3.6 — Preparação Ollama | PASS estrutural; observação antiga sobre GPU já superada pela troca |
| 3.7 — Diagnóstico GPU/DRM | RX 6600 reconhecida, `amdgpu`, KFD e render node presentes |
| 3.8 — ROCm/KFD | KFD validado; ferramentas ROCm user-space ausentes |
| 3.9 — Runtime GPU | Estrutura da GPU validada; Vulkan ainda não instalado na ocasião |
| 3.10 — Vulkan/RADV | Pacotes instalados, `vulkaninfo` confirmou RX 6600/RADV; **script encerrou com bug após imprimir PASS** |

### Evidência essencial da etapa 3.10

Pacotes instalados no Ubuntu: `libvulkan1` 1.4.341.0-1; `mesa-vulkan-drivers` 26.0.8-1ubuntu0.3; `vulkan-tools` 1.4.341.0+dfsg1-1.

`vulkaninfo --summary` identificou:

```text
GPU0:
  vendorID   = 0x1002
  deviceID   = 0x73ff
  deviceName = AMD Radeon RX 6600 (RADV NAVI23)
  driverID   = DRIVER_ID_MESA_RADV
  driverName = radv
  driverInfo = Mesa 26.0.8-1ubuntu0.3
GPU1:
  deviceName = llvmpipe (LLVM 21.1.8, 256 bits)
  driverID   = DRIVER_ID_MESA_LLVMPIPE
```

**Interpretação:** RADV da RX 6600 está funcional no guest. `llvmpipe` adicional não invalida o RADV. A mensagem `DISPLAY environment variable not set` é compatível com servidor headless.

**Bug do script 3.10:** após `[OK] RESULTADO: PASS`, ocorreu `/home/tlandskron/10-preparacao-vulkan-radv.sh: line 151: out: unbound variable`. Causa identificada: `trap ... RETURN` referenciando variável local `out` fora de escopo sob `set -u`. A tentativa posterior de gerar arquivos corrigidos não foi concluída devido à indisponibilidade da ferramenta. **Não presumir que a correção foi entregue ou aplicada.** Corrigir limpeza do arquivo temporário e validar novamente em modo somente leitura, se solicitado.

## 7. Modelos e benchmarks discutidos

- Candidatos: Qwen3.5 4B quantizado (inicial), Qwen3 8B Q4, Qwen3.5 9B Q4 (experimental), DeepSeek pequeno.
- Embeddings preferencialmente na CPU, preservando VRAM para LLM, salvo testes deliberados.
- Medir 4K/8K/16K/24K/32K de contexto, tokens/s, latência, VRAM, RAM, temperatura/energia, estabilidade e offload.
- `vulkaninfo` comprova enumeração/driver, **não** comprova que Ollama ou llama.cpp usam a GPU nem que o LLM cabe integralmente na VRAM.

## 8. Próxima continuidade recomendada

1. **Concluir formalmente a etapa 3.10:** corrigir o bug do script e executar `verify` sem alterações no servidor.
2. Validar o backend **Vulkan do Ollama ou llama.cpp**, inicialmente com a **RX 6600 isolada**, observando VRAM e ausência de CPU offload.
3. Executar benchmarks controlados de modelos pequenos e limites de contexto.
4. Somente depois discutir instalação/passthrough da **RX 5700**, verificando slots PCIe, alimentação, IOMMU/VFIO, dispositivos render e compatibilidade RADV, sem presumir suporte multi-GPU.
5. Comparar inferência independente em duas GPUs com divisão de um único modelo, se tecnicamente viável.
6. Implantar progressivamente Open WebUI, Hermes, RAG, Qdrant, Docling, busca e memória após as validações de inferência.

## 9. Pontos a confirmar na nova conversa

- RAM física e RAM efetivamente alocada à VM **hoje**.
- Se a RX 5700 já foi adquirida/instalada ou continua sendo apenas proposta.
- Se o script `10-preparacao-vulkan-radv.sh` foi corrigido posteriormente.
- Versões atuais do Docker, Mesa e Ubuntu caso tenham sido atualizadas.
- Escolha final do componente de memória, pois Honcho era a opção inicial discutida neste tópico.

---

**Orientação para a próxima conversa:** continuar a partir deste documento, preservar as decisões e distinguir resultados medidos de planos. Não instalar, modificar configurações nem gerar scripts sem pedido específico do usuário.
