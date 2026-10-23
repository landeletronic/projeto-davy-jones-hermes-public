# RELATÓRIO TÉCNICO — PROJETO DAVY JONES GPT

Caribbean Pirates GPT | Consolidação das conversas deste tópico | 20/10/2026

Natureza do documento: relatório de objetivos, arquitetura, recursos tecnológicos e configuração de hardware conhecida.

Base documental: decisões, resultados de execução e informações apresentadas nas conversas deste tópico. Não foi realizado novo inventário, diagnóstico ou acesso aos servidores.

## 1. Objetivo do projeto

O Davy Jones GPT tem como objetivo desenvolver um ambiente próprio de inteligência artificial, executado localmente, utilizando preferencialmente soluções gratuitas e de código aberto.

O projeto deverá funcionar como laboratório de desenvolvimento, experimentação, integração e validação de tecnologias de IA, com capacidade de evoluir para uma plataforma de utilização prática.

Seus principais objetivos são:

1. Executar modelos de linguagem (LLMs) localmente, utilizando aceleração por GPU.
2. Permitir interação com a IA por meio de interface web.
3. Integrar agentes capazes de interpretar solicitações, consultar informações e executar ferramentas autorizadas.
4. Implementar memória persistente para agentes e conversações.
5. Desenvolver mecanismos de recuperação de informações por RAG.
6. Processar documentos PDF, DOC, DOCX e outros formatos relevantes.
7. Integrar mecanismos de pesquisa na internet.
8. Disponibilizar recursos especializados para TI, atividades jurídicas, contábeis e preparação para concursos da magistratura.
9. Comparar modelos, mecanismos de inferência e configurações de hardware.
10. Manter autonomia operacional e reduzir a dependência de serviços externos pagos.

O projeto deverá permitir experimentação controlada, observabilidade, documentação e reprodução das configurações utilizadas.

## 2. Arquitetura tecnológica prevista

Open WebUI

Interface web de interação com o usuário

Hermes Agent — Orquestração

Agentes, ferramentas, decisões e permissões

Ollama / llama.cpp

Inferência local de LLMs

Memória de agentes

Honcho previsto na arquitetura inicial

RAG / Qdrant

Recuperação de conhecimento

SearXNG

Pesquisa na internet

Docling

Extração de documentos

Ferramentas externas

APIs, OpenAPI e MCP

Docker / Ubuntu Server / Proxmox VE

Infraestrutura de execução, isolamento e armazenamento

A arquitetura estabelece que cada serviço deverá operar, preferencialmente, em contêiner Docker independente, permitindo manutenção, atualização e diagnóstico isolados.

O Hermes foi escolhido para a função de agente e orquestrador. O Open WebUI permanece como interface, sem depender do Open WebUI Pipelines como middleware central.

## 3. Recursos de software previstos

| Componente         | Finalidade                                | Situação no tópico                     |
| ------------------ | ----------------------------------------- | -------------------------------------- |
| Ubuntu Server      | Sistema operacional da VM                 | Confirmado                             |
| Proxmox VE         | Virtualização e passthrough de GPU        | Confirmado                             |
| Docker Engine      | Execução de contêineres                   | Instalado e validado                   |
| Docker Compose     | Orquestração de serviços                  | Instalado e validado                   |
| Open WebUI         | Interface de interação                    | Planejado                              |
| Hermes Agent       | Agente e orquestração                     | Planejado                              |
| Ollama             | Servidor de inferência                    | Preparação realizada                   |
| llama.cpp          | Inferência e testes experimentais         | Candidato                              |
| Honcho             | Memória de agentes na arquitetura inicial | Planejado, sujeito a reavaliação       |
| Qdrant             | Banco de dados vetorial                   | Planejado                              |
| Docling            | Extração e estruturação documental        | Planejado                              |
| SearXNG            | Pesquisa web                              | Planejado                              |
| RAG API / Worker   | Processamento e recuperação documental    | Planejado                              |
| BM25 / RRF         | Recuperação lexical e fusão de resultados | Planejado                              |
| Reranker           | Reordenação de resultados recuperados     | Planejado                              |
| Vulkan / Mesa RADV | Aceleração gráfica e computacional        | Instalado e validado no host convidado |
| ROCm               | Alternativa de aceleração AMD             | Não instalado nesta sequência          |

A definição inicial de Honcho como memória de agentes pertence à arquitetura discutida neste tópico e não constitui confirmação de implantação.

## 4. Recursos de inteligência artificial

### 4.1. Modelos de linguagem

Foram considerados modelos da família Qwen, incluindo Qwen3 e Qwen3.5, além de alternativas para comparação.

Os candidatos discutidos incluem:

- Qwen3.5 4B quantizado, como opção inicial.
- Qwen3 8B quantizado, para avaliações de maior capacidade.
- Qwen3.5 9B quantizado, como candidato experimental sujeito à capacidade de VRAM.
- Modelos DeepSeek menores, para comparações.

A seleção definitiva dependerá de testes reais de consumo de memória, velocidade, qualidade das respostas e compatibilidade com as GPUs.

Requisito estabelecido: os LLMs deverão executar integralmente na VRAM, sem descarregamento de camadas para RAM ou CPU.

### 4.2. Recuperação de conhecimento — RAG

O mecanismo RAG foi planejado para operar independentemente da interface web, permitindo utilização por diferentes agentes e serviços.

Fluxo previsto:

Documentos e fontes de conhecimento

Docling — extração e estruturação

Metadados e divisão estruturada em trechos

Embeddings / Qdrant / BM25

RRF e reranking

Contexto fundamentado → Hermes → LLM

Para aplicações jurídicas e contábeis, a arquitetura prevê identificação de fontes, metadados temporais, versões documentais e evidências utilizadas nas respostas.

## 5. Áreas de aplicação

| Área                     | Funcionalidades pretendidas                                                                     |
| ------------------------ | ----------------------------------------------------------------------------------------------- |
| Tecnologia da Informação | Administração de servidores, diagnósticos, automações, Docker, Linux e ferramentas operacionais |
| Jurídica                 | Consulta de legislação, jurisprudência, documentos processuais, pesquisa e elaboração assistida |
| Contábil                 | Análise de documentos, cálculos, consultas técnicas e organização de informações                |
| Magistratura             | Estudos, pesquisa jurídica, questões, revisão de conteúdo e acompanhamento de conhecimento      |

As ferramentas operacionais deverão distinguir ações de leitura, escrita e operações destrutivas. Ações destrutivas exigirão confirmação específica.

## 6. Hardware configurado e recursos conhecidos

Esta seção apresenta exclusivamente o hardware e as configurações relatadas no tópico, sem novo inventário.

| Elemento                      | Configuração conhecida                                        |
| ----------------------------- | ------------------------------------------------------------- |
| Processador físico            | AMD Ryzen 7 5700X                                             |
| Placa-mãe                     | Gigabyte B550M Aorus Elite                                    |
| Virtualizador                 | Proxmox VE 9.2                                                |
| VM                            | Davy Jones, VMID 10003                                        |
| Sistema operacional convidado | Ubuntu Server 26.04.1 LTS                                     |
| Processadores virtuais        | 8 vCPUs                                                       |
| Memória RAM da VM             | 8 GB em configuração temporária relatada; anteriormente 16 GB |
| Memória RAM física            | 16 GB temporários, com previsão de retorno a 32 GB            |
| Armazenamento da VM           | Aproximadamente 1 TB                                          |
| GPU validada                  | AMD Radeon RX 6600 ASRock, 8 GB                               |
| GPU adicional proposta        | AMD Radeon RX 5700, 8 GB                                      |
| Rede Docker interna           | `davy-jones-internal`, `172.30.0.0/24`                        |

Observação sobre a RAM: o tópico contém informações de momentos distintos. Foi comunicada uma redução temporária de memória devido a problema nos módulos, com intenção de restaurar 32 GB no host e 16 GB na VM. Não há confirmação posterior, neste trecho, de que a restauração ocorreu.

Observação sobre as GPUs: a RX 6600 foi efetivamente reconhecida e validada no Ubuntu. A RX 5700 foi apresentada como proposta de ampliação; não há confirmação de sua instalação ou configuração.

### 6.1. GPU RX 6600 — validação realizada

Os resultados fornecidos demonstraram:

- GPU AMD Navi 23, PCI ID `1002:73ff`.
- Driver de kernel `amdgpu`.
- Dispositivos `/dev/kfd` e `/dev/dri/renderD128` disponíveis.
- VRAM identificada pelo kernel em aproximadamente 8 GB.
- Mesa Vulkan 26.0.8.
- Driver `RADV NAVI23` identificado pelo `vulkaninfo`.
- Dispositivo Vulkan classificado como GPU dedicada.

O resultado principal foi:

```
deviceName = AMD Radeon RX 6600 (RADV NAVI23)
driverID   = DRIVER_ID_MESA_RADV
driverName = radv
driverInfo = Mesa 26.0.8-1ubuntu0.3
```

O `llvmpipe` também apareceu como dispositivo Vulkan de CPU. Sua presença não invalida a identificação do RADV.

A validação demonstrou que o runtime Vulkan reconhece a RX 6600. Ainda não demonstra execução de LLM integralmente na GPU, que dependerá de testes posteriores.

### 6.2. Proposta de utilização de duas GPUs

A arquitetura está sendo estudada para utilizar simultaneamente:

RX 6600

# 8 GB

Vulkan/RADV validado

LLM principal e testes de inferência

RX 5700

# 8 GB

Proposta

Segundo LLM, tarefas paralelas e testes multi-GPU

A capacidade agregada nominal seria de 16 GB de VRAM distribuída entre duas placas, não uma memória unificada de 16 GB.

Foram discutidos dois modos de operação: execução independente de modelos em cada GPU e distribuição experimental de um modelo entre ambas, caso o runtime permita.

A segunda modalidade exigirá testes de compatibilidade, divisão de camadas, transferência de dados e desempenho.

## 7. Infraestrutura Docker e armazenamento

Foi estabelecida a seguinte estrutura operacional:

```
/opt/davy-jones/
├── compose/
│   └── overlays/
├── config/
│   ├── common/
│   └── services/
├── secrets/
├── data/
│   ├── app/
│   ├── cache/
│   ├── database/
│   ├── documents/
│   ├── exports/
│   └── uploads/
├── logs/
│   └── services/
├── models/
│   └── ollama/
├── backups/
│   ├── config/
│   └── database/
├── scripts/
│   ├── install/
│   ├── verify/
│   ├── backup/
│   └── maintenance/
├── tmp/
└── run/
```

A estrutura foi preparada para separar configurações, modelos, dados persistentes, documentos, logs, backups e scripts operacionais.

Também foram estabelecidas diretrizes para permissões de arquivos, isolamento de serviços, identificação de UID/GID dos contêineres e preservação de dados.

## 8. Etapas de implantação registradas

| Etapa | Atividade                          | Resultado conhecido                                    |
| ----- | ---------------------------------- | ------------------------------------------------------ |
| 2     | Instalação Docker Engine e Compose | Validada                                               |
| 3.1   | Estrutura de diretórios            | PASS                                                   |
| 3.3   | Rede Docker interna                | PASS                                                   |
| 3.4   | Política de armazenamento          | PASS                                                   |
| 3.5   | Preparação Docker Compose          | PASS                                                   |
| 3.6   | Preparação do ambiente Ollama      | PASS, com observações da GPU anterior                  |
| 3.7   | Diagnóstico GPU/DRM                | RX 6600 validada                                       |
| 3.8   | Validação ROCm/KFD                 | Estrutura KFD validada; ROCm user-space ausente        |
| 3.9   | Validação do runtime GPU           | Estrutura validada; Vulkan ainda ausente naquela etapa |
| 3.10  | Instalação e validação Vulkan/RADV | RADV validado; erro final de limpeza no script         |

Na etapa 3.10, o script apresentou `out: unbound variable` depois da mensagem `RESULTADO: PASS`. O problema estava no tratamento de arquivo temporário pelo script, não na identificação da GPU pelo Vulkan.

Assim, a evidência técnica de funcionamento do RADV é positiva, mas a execução do script não terminou normalmente.

## 9. Requisitos operacionais do projeto

As conversas estabeleceram diretrizes de implementação:

- Utilização de soluções open source e gratuitas.
- Preferência por serviços independentes em Docker.
- Automação de instalação e configuração por scripts.
- Validação posterior de cada instalação.
- Modo `verify` estritamente somente leitura.
- Documentação correspondente a cada script, com o mesmo nome-base e extensão `.md`.
- Preservação de configurações existentes e funcionais.
- Operações idempotentes sempre que possível.
- Diagnóstico e testes antes de alterações de infraestrutura.
- Não modificar Proxmox, GRUB ou passthrough sem necessidade e autorização.
- Registrar o estado efetivamente validado, diferenciando-o de funcionalidades apenas planejadas.

## 10. Situação geral e próximos objetivos

O projeto possui uma base operacional parcialmente preparada: sistema Ubuntu, Docker, rede interna, diretórios, política de armazenamento e runtime Vulkan/RADV para a RX 6600.

Os principais objetivos ainda pendentes nesta sequência são:

1. Validar a execução de modelos locais pelo Ollama ou llama.cpp com aceleração efetiva por Vulkan.
2. Medir utilização de VRAM, RAM, desempenho e limites de contexto.
3. Confirmar que os modelos selecionados não utilizam offload para CPU/RAM.
4. Avaliar a inclusão da RX 5700 e sua compatibilidade com a infraestrutura virtualizada.
5. Comparar execução independente e multi-GPU.
6. Implantar progressivamente a interface, agentes, memória, RAG e demais serviços planejados.
7. Integrar as áreas de TI, Jurídica, Contábil e Magistratura.

## 11. Conclusão

O Davy Jones GPT foi concebido como uma plataforma própria de inteligência artificial, com execução local de modelos, agentes, memória, recuperação de conhecimento, processamento documental e ferramentas de automação.

Sua infraestrutura utiliza virtualização Proxmox, Ubuntu Server e Docker, com aceleração por GPU AMD. A RX 6600 já demonstrou compatibilidade funcional com o driver Mesa/RADV no ambiente convidado.

A possível inclusão de uma RX 5700 representa uma ampliação experimental, principalmente para processamento paralelo e investigação de inferência multi-GPU.

O estágio documentado é de preparação da infraestrutura e validação dos recursos de aceleração, não de implantação completa da plataforma de inteligência artificial.

Este relatório consolida as informações das conversas, sem realizar inventário de hardware e sem presumir que componentes planejados já estejam instalados ou operacionais.