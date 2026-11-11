# medusa_mcp.py — MCP de diagnóstico somente leitura da Medusa

`tools/medusa_mcp.py` oferece diagnóstico de GPU, Ollama, modelos e recursos de mídia; não
executa shell arbitrário, gera vídeos, modifica dados ou publica episódios.

O pipeline de Podcast continua não implementado.

## Implantação atual na Medusa

- Código: `/home/usuario/medusa-mcp/server.py` (cópia de `tools/medusa_mcp.py`).
- Ambiente isolado: `/home/usuario/medusa-mcp/.venv`, MCP Python SDK 1.26.0.
- Serviço de usuário: `medusa-mcp.service` (fonte `ops/systemd/medusa-mcp.service`), com Uvicorn
  somente no IP Tailscale da Medusa `100.126.89.55:18766`; não publica porta na LAN.
- A aplicação aceita somente o IP Tailscale do Davy `100.112.146.19` **e** o token próprio.
  O ASGI usa o endereço real do socket e o Uvicorn desativa proxy headers: `X-Forwarded-For`
  não concede acesso. Conexões usam HTTP dentro do túnel WireGuard do Tailscale, não HTTPS.
- Token de diagnóstico do host: `~/.config/medusa-mcp/token` na Medusa e no Davy, modo 600.
- Token independente do Hermes: `~/.config/medusa-mcp/token-hermes` na Medusa, modo 600, e
  `MEDUSA_MCP_TOKEN` no `.env` do projeto. O Compose injeta a variável no container; o
  `hermes-data/config.yaml` contém somente a referência `${MEDUSA_MCP_TOKEN}`. Não versionar valores.
- Regressão: `/home/usuario/medusa-mcp/.venv/bin/python /home/usuario/medusa-mcp/tests/test_medusa_mcp.py`.

Em 2026-10-31, `initialize`, `tools/list` e as cinco ferramentas passaram **do host Davy**;
sem token ou com token errado retornaram 401. A estação Windows recebeu 403 mesmo com token correto
e com `X-Forwarded-For` falsificado. As entradas anteriores no OpenCode e Qoder foram removidas e
o transporte stdio remoto foi desativado. O filtro é **da aplicação**, não uma ACL da tailnet;
outros hosts ainda podem estabelecer TCP, mas não receber resposta MCP autorizada.

O container Hermes conecta diretamente pelo Tailscale usando o token exclusivo. A regressão
`tests/smoke_medusa_mcp.py` verifica handshake, ferramentas e chamadas reais, sem revelar a
credencial; `tests/verify_stack.sh` a executa. Não monte `~/.ssh` ou `docker.sock` no gateway.
Os IPs são fixados na configuração e precisam ser verificados se um nó for recriado. Instale uma
ACL da tailnet específica para bloquear o TCP de outras máquinas como defesa adicional quando a
política for administrada; não confunda isso com o filtro já testado. `tool_search` permanece off.
