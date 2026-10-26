# searxng — meta-busca interna

| | |
|---|---|
| Imagem | `searxng/searxng@sha256:8bdd9aa1…` (2026.10.17) |
| Porta | **nenhuma publicada** (só rede interna, `:8080`) |
| Config | `searxng/settings.yml` (o container roda como uid **977** e toma posse do diretório) |
| Uso no lab | OWUI global desligado; fallback explícito somente do **Apostilas Tiradentes** |

## Verificar

```bash
docker inspect -f '{{.State.Health.Status}}' searxng        # healthy
docker exec searxng wget -qO- 'http://127.0.0.1:8080/search?q=teste&format=json' | head -c 200
```

## Reiniciar

```bash
cd /home/usuario/hermes-architect && docker compose restart searxng
```

## Sintomas típicos

- **JSON não vem** → `settings.yml` precisa de `formats: [html, json]`; sem isso o endpoint
  responde 403.
- **Editar o `settings.yml` e não mudar nada** → o diretório é do uid 977. O sync copia via
  `/tmp` + `sudo install` justamente por isso; editando à mão, use `sudo`.
- **Container reinicia em loop** → YAML inválido. `docker logs searxng` mostra a linha.

> O lab continua independente da internet e `ENABLE_WEB_SEARCH=false` impede busca global no OWUI.
> O Pipe Apostilas Tiradentes acessa `http://searxng:8080/search` diretamente somente no fallback
> duplamente condicionado (sem fonte local + pedido explícito). O Tutor Tiradentes não usa web.
