# Evidência — início da execução autônoma

**Data:** 2026-11-01  
**Autorização:** registrada no `manifest.yaml`  
**Estado:** execução segura realizada; integração produtiva bloqueada por ausência
de ambiente de staging isolado.

## Testes locais

```text
PASS tutor pipe: parser + consulta exata + fail-closed + somente leitura
PASS apostilas pipe: modos + RAG + fail-closed + fontes
```

O teste `tests/test_medusa_mcp.py` não executou no Windows porque o ambiente local
não possui o pacote Python `starlette`. Nenhum pacote global foi instalado.

## Estado operacional

```text
CI OK: PASS=271 FAIL=0 WARN=0
Ollama: running / healthy
```

## Decisão de segurança

Não foi adicionada uma conexão llama.cpp no banco produtivo do Open WebUI. A
integração real exige host/volumes/credenciais de staging separados; alterar
`webui.db` de produção para cadastrar uma conexão temporária violaria o isolamento
previsto no plano.

O runtime temporário já foi validado anteriormente para API, streaming, reasoning,
concorrência e healthcheck. O próximo avanço seguro é provisionar um staging isolado
ou obter autorização específica para uma janela de teste de consumidor que não
persista configuração produtiva.
