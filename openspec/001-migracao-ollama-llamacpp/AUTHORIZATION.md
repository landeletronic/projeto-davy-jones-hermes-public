# Autorização para execução autônoma

Este arquivo é um gate humano explícito. O plano não deve avançar para execução
autônoma somente por existir no Git.

## Escopo que será autorizado

- execução das fases seguras do `AUTONOMOUS-EXECUTION-PLAN.md`;
- uso de subagentes para análise, testes e revisão;
- criação de manifests, testes, runbooks e evidências;
- staging paralelo e reversível;
- manutenção do Ollama como produção/fallback.

## Fora da autorização padrão

- remoção do Ollama ou volumes;
- cutover global;
- reindexação definitiva do Qdrant;
- destruição/restauração destrutiva de volumes;
- alterações externas não descritas no plano.

## Resposta registrada

Autorização recebida em 2026-11-01:

```text
autorizo a execução autônoma do plano OpenSpec 001
```

O `manifest.yaml` foi atualizado para registrar a autorização. Ela permite iniciar
os gates seguros do plano, mas não autoriza remover o Ollama, reindexar produção ou
fazer cutover global.
