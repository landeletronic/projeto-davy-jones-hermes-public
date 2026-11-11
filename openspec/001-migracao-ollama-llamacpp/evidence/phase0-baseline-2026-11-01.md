# Evidência — Fase 0 — baseline e backup

**Data:** 2026-11-01  
**Host:** `davy-jones-hermes` (`192.168.15.231`)  
**Runtime atual:** Ollama em container Docker  
**Status:** Gate A aprovado; nenhum cutover realizado.

## Estado observado

- Ollama: `0.40.2`;
- container: saudável;
- modelos instalados: `qwen3:4b-64k`, `qwen3:8b-chat-16k`,
  `qwen3:8b-extract`, `bge-m3` e variantes adicionais;
- `qwen3:4b-64k`: contexto `65536`, 100% GPU, 5,6 GB residentes;
- `bge-m3`: 100% GPU, 664 MB residentes;
- nenhum binário `ollama`, `llama-server`, `llama-cli` ou `llama-bench` no host;
- nenhum serviço systemd Ollama; o runtime é o container `ollama`;
- GPU exposta ao container por `/dev/kfd` e `/dev/dri`.

## Medição de geração

Modelo: `qwen3:4b-64k`  
Prompt fixo: `Responda apenas: baseline concluido.`  
`num_predict=128`, `temperature=0`, resposta não-stream.

| Execução | Carga do modelo | Tokens | Tempo de avaliação | Tokens/s |
|---|---:|---:|---:|---:|
| Cold | 1,208 s | 128 | 2,087 s | 61,34 |
| Warm 1 | 0,001 s | 128 | 2,071 s | 61,80 |
| Warm 2 | 0,002 s | 128 | 2,077 s | 61,62 |

## Medição de embedding

- modelo: `bge-m3`;
- dimensão observada: `1024`;
- endpoint: `/api/embed`;
- resultado compatível com as coleções atuais do Qdrant.

## Backup

- artefato: `/home/usuario/backups/hermes-20261101T215804Z.tar.gz`;
- tamanho: 87 MB;
- SHA-256: `b52667f2ea500c56a3af50c76b76421ef6a85b2f492a2a0a453a25b28242cebb`;
- `gzip -t`: aprovado;
- `tar -tzf`: aprovado;

## Oráculo

```text
CI OK: PASS=271 FAIL=0 WARN=0
```

## Artefatos brutos no host

```text
/var/tmp/ollama-baseline-20261101/
```

Contém metadados, respostas brutas de geração, resposta de embedding e estado do
`ollama ps` antes/depois.
