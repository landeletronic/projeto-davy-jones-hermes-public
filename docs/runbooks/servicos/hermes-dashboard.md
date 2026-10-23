# hermes-dashboard — painel interno do gateway

| | |
|---|---|
| Imagem | `hermes-tools:local` (a mesma do gateway) |
| Porta | `9119` (liberada na LAN pelo ufw — é INPUT de verdade, o processo escuta no host) |
| Dados | nenhum volume próprio; lê o estado do gateway |
| Healthcheck | `curl -fsS http://127.0.0.1:9119/api/health` |
| Login | formulário em `/login` — usuário/senha/secret no `.env` |

## Login (porta 9119)

O painel exige login; as três variáveis vivem no `.env` (o compose só interpola — desde
2026-10-23; antes ficavam escritas no `docker-compose.yml`):

```bash
grep HERMES_DASHBOARD_BASIC_AUTH /home/usuario/hermes-architect/.env
```

| variável | o que é |
|---|---|
| `HERMES_DASHBOARD_BASIC_AUTH_USERNAME` / `..._PASSWORD` | o que se digita no formulário |
| `HERMES_DASHBOARD_BASIC_AUTH_SECRET` | chave que **assina o cookie de sessão** (não é senha); trocá-la derruba todas as sessões abertas |

**Não é HTTP Basic:** `curl -u admin:senha` devolve `401`. O login é
`POST /auth/password-login` com `{"provider":"basic","username":...,"password":...}` e o cookie
volta na resposta. Sem sessão, só `/api/health` e `/api/status` respondem.

### Trocar a senha

1. edite `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD` (e, de preferência, o `..._SECRET`) no `.env`;
2. `cd /home/usuario/hermes-architect && docker compose up -d hermes-dashboard`
   — **o `sync-to-host.ps1` copia o `.env` mas não aplica o compose**;
3. prove o login (abaixo). A senha antiga para de valer na hora; trocou o secret, os navegadores
   já logados caem.

```bash
# 200 = senha certa; 401 = errada (limite de tentativas por IP — não fique testando à toa)
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:9119/auth/password-login \
  -H 'Content-Type: application/json' \
  -d '{"provider":"basic","username":"admin","password":"<senha do .env>"}'
```

## Verificar

```bash
docker inspect -f '{{.State.Health.Status}}' hermes-dashboard    # healthy
curl -s localhost:9119/api/health
curl -s -o /dev/null -w '%{http_code}\n' http://192.168.15.231:9119/   # pela LAN (302 -> /login)
```

## Reiniciar

```bash
cd /home/usuario/hermes-architect && docker compose restart hermes-dashboard
```

## Sintomas típicos

- **Não abre pela LAN mas abre no host** → porta 9119 não está liberada no ufw. Confira
  `sudo ufw status numbered | grep 9119`; a política está em `ops/bin/ufw-lab.sh`.
- **Healthcheck falha mas o processo responde** → o healthcheck usa `curl` **dentro** do
  container; se a imagem foi trocada, confira se `curl` existe nela.
- **Mostra dados velhos** → ele consulta o gateway; se o `hermes-agent` estiver reiniciando, a
  tela fica vazia até ele voltar.
- **Compose recusa subir com "defina no .env (ver .env.example)"** → falta uma das três
  `HERMES_DASHBOARD_BASIC_AUTH_*` no `.env`; o `:?` do compose falha de propósito, com mensagem.
- **Login volta para a tela** → senha errada, ou o container ainda tem o env antigo (mudou o
  `.env` sem `docker compose up -d`).

> É um painel de operação, não de usuário final. Tem login próprio, mas continua sendo de rede
> local: não exponha na internet.
