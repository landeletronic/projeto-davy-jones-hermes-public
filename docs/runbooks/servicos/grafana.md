# grafana — dashboards (atrás do nginx em 3001)

| | |
|---|---|
| Imagem | `grafana/grafana@sha256:dbbc38ea…` (13.2.4) |
| Porta | **nenhuma publicada**; quem atende a LAN é o **nginx em `:3001`** (TLS) → `grafana:3000` |
| Dados | volume `grafana_data` (`grafana.db`) + provisionamento de `monitoring/` |
| Usuário | corre **uid 472**, não root — e isso importa para permissões |
| Login | admin + senha do `.env` (**só no 1º boot** do volume) |

## Verificar

```bash
docker inspect -f '{{.State.Health.Status}}' grafana            # healthy
curl -sk -o /dev/null -w '%{http_code}\n' https://192.168.15.231:3001/
# login real (a suíte faz uma tentativa por execução — brute-force trava o usuário!)
curl -sk -u admin:"$GF_PASS" https://192.168.15.231:3001/api/user -o /dev/null -w '%{http_code}\n'
# dashboards provisionados
docker exec grafana ls /etc/grafana/provisioning/dashboards/
```

## Sintomas típicos

- **"failed to walk provisioned dashboards: permission denied"** → `monitoring/` não é legível
  pelo uid 472. O umask do host cria 700; corrija com `chmod -R a+rX monitoring` (o sync já faz).
- **Senha do `.env` não entra** → `GF_SECURITY_ADMIN_PASSWORD` vale **só no 1º boot**. Redefina:
  ```bash
  docker exec grafana grafana cli admin reset-admin-password '<nova>'
  docker compose restart grafana        # sem o restart não vale
  ```
- **5 erros = usuário bloqueado** (tabela `login_attempt` sobrevive a restart):
  ```bash
  docker compose stop grafana
  docker run --rm -v hermes-architect_grafana_data:/var/lib/grafana alpine \
    sh -c "apk add -q sqlite && sqlite3 /var/lib/grafana/grafana.db 'delete from login_attempt;'"
  docker compose up -d grafana
  ```
- **Dashboard `hermes-lab` não aparece** → é provisionamento, não importação: o arquivo tem de
  estar em `monitoring/` e legível.

## Backup

`grafana.db` é copiado pela API `.backup` do SQLite num container com o volume montado (não
`docker cp` do banco vivo). Restaurando: **`chown 472:472` + `chmod 640`** depois de copiar de
volta, senão o SQLite não abre e o container entra em crash-loop.
