# AI-MEMORY — instalação no Windows (cliente do servidor central) — RUNBOOK

> **Escrito em 2026-10-19.** Versão de referência: **ai-memory 3.1.1**.
> **Servidor:** `omarchy` (a estação Omarchy Linux) · **Cliente:** `B550M-AORUS-ELI`
> (**Windows 11**, **OpenCode 2.0**).
> **Fontes:** `https://github.com/akitaonrails/ai-memory/blob/main/docs/install.md` §"Server on a different machine", `https://github.com/akitaonrails/ai-memory/blob/main/docs/windows.md`
> §Scenario C/E, `https://github.com/akitaonrails/ai-memory/blob/main/docs/users.md` §"Multi-user attribution" e a ajuda de
> `install-mcp` / `install-hooks`.
>
> **Credencial desta máquina:** chave nativa `aim_` (e **não** o token raiz) — ver §3.1.
> Emiti-la coloca o servidor em **modo multi-usuário**: as **páginas continuam
> compartilhadas**, mas **handoffs e sessões passam a ter dono**.

---

## 0. A ideia em uma linha (leia antes de tudo)

O servidor de memória é **único** e fica na **estação Omarchy**. O Windows é **cliente**:
não sobe servidor, não guarda memória própria — só fala HTTP/HTTPS com o servidor central,
para que as duas máquinas compartilhem a **mesma** memória.

> ⚠️ **NÃO rode `ai-memory setup` no Windows.** Ele registra um servidor **local** para
> iniciar no logon (`HKCU\...\Run`) e liga os agentes no **loopback** — o resultado seria uma
> memória paralela no Windows, e o objetivo (memória única) se perde. Use os passos abaixo.

---

## 1. Pré-requisitos

| Item | Observação |
|---|---|
| **Windows 11 x64** | é esta máquina; ARM64 usaria o build x86_64 por emulação (o instalador avisa) |
| PowerShell 5.1+ | sessão **sem** elevação (nada aqui exige administrador) |
| **Tailscale** conectado à mesma tailnet | é por onde o cliente alcança o servidor |
| **OpenCode 2.0** instalado | é o agente a ligar aqui; o contrato V2 usa `mcp.servers` **aninhado** e o plugin `ai-memory-opencode2.ts` |

> **O servidor é um laptop.** Se ele estiver desligado, a captura não se perde: os eventos
> ficam no *spool* local do cliente e são reenviados quando o servidor voltar
> (`ai-memory recover` força o dreno).

---

## 2. Passo 1 — instalar o binário (sem admin)

```powershell
irm https://github.com/akitaonrails/ai-memory/releases/latest/download/install.ps1 | iex
```

O que ele faz: baixa `ai-memory-windows-x86_64.zip`, **confere o SHA-256** (aborta se faltar
ou divergir), recusa entradas com caminho absoluto ou `..`, extrai em
`%LOCALAPPDATA%\Programs\ai-memory` e adiciona essa pasta ao **PATH do usuário**.
Nada fora disso é tocado. (`$env:AI_MEMORY_NO_MODIFY_PATH=1` pula a parte do PATH.)

Conferir:

```powershell
ai-memory --version
Get-Command ai-memory
```

Abra um terminal **novo** se o PATH não pegar de imediato.

---

## 3. Passo 2 — apontar para o servidor central

São **duas** variáveis de ambiente. Persista-as no usuário (valem em todo terminal novo) e
aplique-as também na **sessão atual** (o overload de 2 argumentos grava no processo):

```powershell
$Url   = "https://omarchy.tail07368.ts.net"
$Token = "<TOKEN>"      # a chave aim_ DESTA máquina (ver §3.1)

foreach ($scope in "User", "Process") {
  [Environment]::SetEnvironmentVariable("AI_MEMORY_SERVER_URL", $Url,   $scope)
  [Environment]::SetEnvironmentVariable("AI_MEMORY_AUTH_TOKEN", $Token, $scope)
}
```

> **Por que não atribuir direto na variável de ambiente:** ferramentas de proteção a segredos
> **redigem** a forma de atribuição a um nome que termina em `TOKEN` (o prefixo de variável do
> PowerShell, seguido do nome e do valor) — e o documento sai quebrado no meio da frase: foi o
> que aconteceu na primeira versão deste runbook, **duas vezes**, uma na gravação do arquivo e
> outra na indexação da wiki. O `[Environment]::SetEnvironmentVariable` faz o mesmo e passa
> ileso. Vale para quem for editar este documento com um agente.

### 3.1 De onde vem o `<TOKEN>` — chave por máquina, **não** o token raiz

Cada máquina tem credencial própria (`aim_…`). O token raiz **fica só na estação Omarchy**:
quem tem o raiz tem `/admin/*`; quem tem a chave tem só memória. Ler a chave desta máquina:

```bash
# na estação Omarchy (arquivo modo 0600):
cat ~/.local/share/ai-memory/api-keys/b550m-aorus-elite.key
```

É um **segredo**: transporte por gerenciador de senhas, nunca por chat, e nunca vai para o git.

> ⚠️ **Consequência de existir uma chave.** Emitir a primeira credencial cria uma linha em
> `users`, e isso liga no servidor o modo que **distingue operadores**:
>
> - **Páginas continuam 100% compartilhadas.** A wiki é *single-tenant*; `last_modified_by`
>   é atribuição, nunca filtro de leitura. (Verificado: página escrita pela chave é lida
>   pelo token raiz.)
>
> - **Handoffs e sessões passam a ter dono** (`user:usuario`). Um handoff começado no
>   Windows é entregue a quem tenha a **mesma identidade** — e hoje o root do servidor é
>   *anônimo* (`root_username` comentado no `config.toml`), então ele **não** chega
>   automaticamente do lado Linux. Recuperação explícita: `any_owner=true` (root). Para
>   casar as identidades, descomentar `root_username = "usuario"` no `config.toml` do
>   servidor e reiniciar o serviço.
>
> - **`/admin/*` fica root-only** — é por isso que o CLI do Windows **não** roda
>   `status`/`doctor` (§8). E **não existe comando para remover o usuário**: a decisão é,
>   na prática, irreversível por CLI.

Emissão, rotação e revogação (na estação Omarchy, com o token raiz):

```bash
ai-memory api-key list                                          # id, label, status, preview
ai-memory api-key rotate 01a155ab-a7ce-7a91-8825-54dabf284cd9   # troca o segredo na hora
ai-memory api-key revoke 01a155ab-a7ce-7a91-8825-54dabf284cd9   # corta só esta máquina
```

> **A chave desta máquina:** id `01a155ab-a7ce-7a91-8825-54dabf284cd9`, label
> `b550m-aorus-elite`, usuário `usuario` (login humano **desabilitado** — é identidade
> somente-API; a chave continua válida, por design).

Dois detalhes que mordem: o `token_pepper` **não pode mudar** depois de emitir chaves
(invalida todos os `aim_` de uma vez), e a chave **não é senha** — não abre console web nem
roda comando administrativo.

---

## 4. Passo 3 — provar a conectividade **antes** de instalar

```powershell
curl.exe https://omarchy.tail07368.ts.net/healthz
# esperado: {"status":"ok"}

curl.exe -s -o NUL -w "%{http_code}`n" https://omarchy.tail07368.ts.net/mcp
# esperado: 401  (sem token) — prova que o endpoint exige autenticação
```

> Use **`curl.exe`** (com extensão): em PowerShell 5.1, `curl` é alias de
> `Invoke-WebRequest` e se comporta diferente.

Se o nome não resolver, é **MagicDNS** desligado na tailnet. Como o certificado TLS é emitido
**para o nome** (`omarchy.tail07368.ts.net`), usar o IP do Tailscale quebra a validação do
certificado — a correção é habilitar o MagicDNS, não trocar por IP.

---

## 5. Passo 4 — ligar o MCP do OpenCode

```powershell
ai-memory install-mcp --client opencode2 --apply `
  --server-url https://omarchy.tail07368.ts.net/mcp `
  --auth-token "<TOKEN>"
```

Escreve (fusão, preservando os outros servidores MCP) em
`%USERPROFILE%\.config\opencode\opencode.json`:

```json
{ "mcp": { "servers": { "ai-memory": {
  "type": "remote",
  "url": "https://omarchy.tail07368.ts.net/mcp",
  "oauth": false,
  "headers": { "Authorization": "Bearer <TOKEN>" } } } } }
```

- Como o alvo é **OpenCode 2.0**, use **`--client opencode2`**: ele fixa o contrato V2
  (`mcp.servers` aninhado, `type: "remote"`, sem `enabled`, `oauth: false`) e o caminho
  `ai-memory-opencode2.ts`, **sem** depender de sondar o binário. O alias genérico
  `--client open-code` faz o mesmo *depois* de rodar `opencode --version` — só é útil se o
  `opencode` não estiver no `PATH`.
- Outros agentes usam o mesmo padrão: `--client codex`, `cursor`, `gemini-cli`,
  `claude-code`, `copilot-cli`, `grok`, … (rode com `--client <x>` sem `--apply` para só
  imprimir o trecho).
- `--apply` faz **backup com timestamp** ao lado do arquivo antes de mexer.

---

## 6. Passo 5 — ligar a captura (hooks)

```powershell
ai-memory install-hooks --agent opencode2 --apply `
  --as-user usuario `
  --server-url https://omarchy.tail07368.ts.net `
  --auth-token "<TOKEN>"
```

- Escreve o plugin `%USERPROFILE%\.config\opencode\plugins\ai-memory-opencode2.ts`.
- `--as-user` é **só rótulo** do instalador (para os seus registros); a atribuição real vem
  do dono do token. Mismatch entre `--as-user` e o token é permitido: o servidor resolve
  pelo token — a flag existe para manter o operador honesto, não para garantir.
- **Reinicie o OpenCode** depois (o plugin carrega na inicialização).
- Note que o `--server-url` aqui é a **origem** (sem `/mcp`); o `install-mcp` acrescenta
  `/mcp` sozinho.
- O OpenCode usa o **plugin TypeScript gerado**, não o pacote de scripts `.ps1`/`.sh` —
  então a pegadinha de `AI_MEMORY_HOOK_PLATFORM` (formas de execução no Windows) **não** se
  aplica aqui. `install-mcp --apply` primeiro e `install-hooks --apply` depois (ou as duas
  variáveis de ambiente definidas) mantêm MCP e captura no **mesmo** servidor.

---

## 7. Passo 6 — o marcador do projeto (é ele que une as duas máquinas)

O arquivo **`.ai-memory.toml`** na raiz do projeto define a coordenada
`workspace` + `project`. É o que garante que uma sessão no Windows grave no **mesmo** projeto
que uma sessão aqui (`default` / `davy-jones-hermes`) — sem ele cada máquina resolve o projeto
por conta própria (basename do remote git; sem remote válido, basename do diretório).

A pasta compartilhada do projeto **já tem** o marcador. Se por algum motivo ele não existir,
crie com o **mesmo** conteúdo dos dois lados:

```toml
workspace = "default"
project   = "davy-jones-hermes"
```

> O `workspace`/`project` tem de **bater** com o que o servidor já conhece. Para conferir do
> lado do servidor: `ai-memory list-projects`.

Conferir o marcador: `ai-memory doctor` mostra `project coordinate: exact`, **mas** ele passa
por rota `/admin/*` e, com a chave por máquina, responde **403** (§8). Confira de duas formas:

- **na estação Omarchy** (como root), que é onde a coordenada importa:
  `ai-memory doctor` e `ai-memory list-projects`;
- **no Windows**, indiretamente: peça ao agente uma leitura da memória do projeto (§8). Se
  ele responde com páginas do lab, o marcador está sendo resolvido.

---

## 8. Verificação (checklist de "pronto")

**No Windows** (o que a chave permite):

- [ ] `ai-memory --version` responde; `Get-Command ai-memory` acha o binário.
- [ ] `curl.exe .../healthz` → `{"status":"ok"}` e `/mcp` sem token → `401`.
- [ ] Recuperação semântica, **pelo agente**: peça *"o que já sabemos sobre o isolamento por
      usuário do mem0?"* — deve trazer `decisions/mem0-multiuser-memory.md` e
      `procedures/owui-auth-and-models.md`. Isto prova MCP + autenticação + escopo de uma vez.
- [ ] Captura: **mande um prompt** e confirme do lado do servidor que os contadores subiram.
      O teste é o do **efeito**, não o da existência do arquivo.
- [ ] Persistência: feche e reabra o terminal/OpenCode e refaça a leitura acima — as variáveis
      têm de continuar de pé (foram gravadas como `User`).

> ⚠️ **`ai-memory status` e `ai-memory doctor` dão 403 no Windows.** São rotas `/admin/*`,
> root-only desde que o servidor passou a distinguir operadores. **Não é defeito de
> instalação:** a chave por máquina não é credencial de administração.

**Na estação Omarchy** (com o token raiz):

- [ ] `ai-memory status` → `sessions`/`observations` **subiram** depois do prompt no Windows.
- [ ] `ai-memory doctor` → cada harness recente **captured** e a coordenada do projeto exata.
- [ ] `ai-memory api-key list` → a chave aparece `active` com `last_used_at` recente.

---

## 9. Problemas comuns

| Sintoma | Causa provável | Ação |
|---|---|---|
| `401` em tudo | token ausente/errado, ou variável só na sessão | reconferir `$env:AI_MEMORY_AUTH_TOKEN` e o valor `User` |
| `403` em `status`/`doctor`/`write-page`/`delete-page` | **esperado**: são rotas `/admin/*`, root-only no modo multi-usuário | conferir da estação Omarchy (root) ou pelo agente (MCP); a chave não é admin |
| `403` no `/mcp` | Host não permitido no servidor (defesa anti-DNS-rebinding) | incluir o nome no `allowed_hosts` do servidor |
| `401` no `/mcp` ou `/hook` | chave revogada/expirada, ou variável só na sessão | `ai-memory api-key list` (no servidor) e reconferir o valor `User` |
| Nome `omarchy.tail07368.ts.net` não resolve | MagicDNS desligado | habilitar MagicDNS (não trocar por IP: quebra o TLS) |
| OpenCode não enxerga as ferramentas | necessário **reiniciar** após `install-hooks` | fechar e reabrir o OpenCode |
| Ferramentas MCP não aparecem e o config tem `mcp` **direto** (formato V1) | entrada no formato errado para o OpenCode 2.0 | refazer com `--client opencode2` (V2 aninhado em `mcp.servers`) |
| Agente sem captura, mas MCP ok | plugin não carregou | ver se existe `...\opencode\plugins\ai-memory-opencode2.ts` |
| Servidor "fora" | a estação é um laptop e pode estar desligada | os eventos ficam em spool; `ai-memory recover` ao voltar |
| Antivírus/EDR reclamando | binário **não assinado** | só costuma doer com `setup` (persistência no logon), que **não** usamos aqui |
| Nada funciona e há suspeita de porta | **49374 é do serviço V2 do OpenCode** nesta estação; o ai-memory aqui usa **49375** | usar sempre `49375` (via `tailscale serve`) |

> **Não rode `ai-memory setup`** no Windows (ver §0). Se já rodou sem querer:
> `ai-memory uninstall --apply` remove o wiring, **inclusive** a entrada de logon.

---

## 10. Desinstalar (no Windows)

```powershell
ai-memory uninstall --apply
[Environment]::SetEnvironmentVariable("AI_MEMORY_SERVER_URL", $null, "User")
[Environment]::SetEnvironmentVariable("AI_MEMORY_AUTH_TOKEN", $null, "User")
```

---

## 11. Registro de execução (2026-10-20, `B550M-AORUS-ELI`)

Implantado com os passos 1–5 e 7, mais o passo de **skills** que este runbook não
documentava. Resultado: MCP conectado (`opencode mcp list` → `ai-memory  connected`),
leitura/escrita/apagamento de página provados pelo **efeito**, e
`tests/verify-ai-memory.ps1` em **PASS=15 / FAIL=0 / WARN=0**. O oráculo do lab
(`tests/run-tests.ps1`) seguiu **PASS=103 / FAIL=0 / WARN=0** — nada aqui o afeta.

### 11.1 Passo que faltava: as skills gerenciadas

MCP + hooks dão as *ferramentas*; sem as skills o agente não tem o *roteiro* de
quando usá-las. O OpenCode V2 lê skills globais de `~/.config/opencode/skills`
(nativo), `~/.claude/skills` e `~/.agents/skills` (compatibilidade):

```powershell
ai-memory install-skills --target-dir "$env:USERPROFILE\.config\opencode\skills"
# --print antes, para só ver os destinos; --force só se houver skill homônima não gerenciada
```

Escreve 6 skills: `ai-memory-retrieval`, `-handoff`, `-messaging`, `-durable-pages`,
`-learning-maintenance`, `-routing-install`. Conferir pelo **efeito**: depois de
instalar, elas passam a aparecer na lista de skills disponíveis da sessão (não basta o
`SKILL.md` existir no disco).

### 11.2 Pegadinhas novas (aprendidas na dor)

| Sintoma | Causa | Ação |
|---|---|---|
| A chave `aim_` **em texto claro** no terminal | `install-mcp`/`install-hooks` **sem** `--apply` (ou com ele) imprimem o snippet `Authorization: Bearer aim_…` no stdout — a proteção de segredos que motivou a §3 **não** cobre a saída do processo | nunca rodar o preview em terminal gravado/logado; se vazar, **rotacionar** (§3.1) |
| `ai-memory search` falha com `could not reach http://127.0.0.1:49374` | o CLI **não** herda o escopo `User` no processo do agente, e usou o default de loopback + rota `/admin/*` (403 para chave de máquina) | no CLI, exportar `AI_MEMORY_SERVER_URL`/`AI_MEMORY_AUTH_TOKEN` na sessão; a **consulta** de verdade é pelo MCP |
| MCP já funciona sem reiniciar — e a captura **também** | o OpenCode recarrega config e plugins a quente | o aviso do instalador ("restart for it to take effect") é conservador: aqui a sessão em curso apareceu no servidor 2 min depois, com o `cwd` do Windows. Confirme pelo **efeito**, não pelo aviso |

### 11.3 Verificação reutilizável (Windows)

```powershell
# cliente ai-memory desta máquina (read-only; não imprime segredos)
powershell -File tests\verify-ai-memory.ps1     # esperado: PASS=15 / FAIL=0 / WARN=0
```

### 11.4 Como provar que é o **servidor da Omarchy** (e não um servidor local)

Cinco provas, todas por evidência (executadas 2026-10-20):

1. **Não há servidor local:** nenhum processo `ai-memory`, nada em `LISTEN` nas portas
   `49374`/`49375`, `127.0.0.1:49374` recusa conexão. O diretório local
   (`%LOCALAPPDATA%\ai-memory`) tem só `auth-token`, `auth-header` e `logs/` — **nenhum**
   `wiki/` ou `db/`: nada de memória fica no Windows.
2. **TLS emitido para o nome:** o certificado é `CN=omarchy.tail07368.ts.net`,
   emitido por **Let's Encrypt** (via Tailscale), e o nome resolve para `100.70.49.0`
   (o nó `omarchy` da tailnet) — não é um endpoint local com certificado próprio.
3. **Config aponta para lá:** `mcp.servers.ai-memory.url = https://omarchy.tail07368.ts.net/mcp`.
4. **O conteúdo é anterior a esta instalação:** ex. `decisions/mem0-multiuser-memory.md`
   (`generated.at = 2026-10-18T18:05:24Z`), `procedures/instalar-ai-memory-no-windows.md`
   e sessões `agent_kind: open-code` de 2026-10-18 — vieram do lado Linux.
5. **Captura ao vivo daqui:** a sessão em curso apareceu no servidor como
   `sessions/8fec9e17-…` com `cwd = C:\Users\usuario\Downloads\davy-jones-hermes`,
   `actor_user = user:usuario`, iniciada em `2026-10-20T00:33:55Z`; o contador de
   observações subiu `822 → 868` enquanto o agente trabalhava.

**Contraprova (decisiva) na estação Omarchy**, com o token raiz — os números têm de bater
com os do Windows *no mesmo instante* (a sessão em curso faz o contador subir):

```bash
ai-memory status        # sessions / observations / pages
ai-memory list-projects # tem de listar default/davy-jones-hermes
```

> ⚠️ O arquivo `%LOCALAPPDATA%\ai-memory\auth-token` guarda a chave em **texto claro** no
> disco (é o desenho da ferramenta). Mais um motivo para rotacionar a chave abaixo.

### 11.5 Pendência deixada aberta

A chave desta máquina apareceu em texto claro na saída do preview (§11.2). Enquanto ela
não for rotacionada, considere-a comprometida:

```bash
# na estação Omarchy (token raiz):
ai-memory api-key rotate 01a155ab-a7ce-7a91-8825-54dabf284cd9
```

Depois da rotação, atualizar `AI_MEMORY_AUTH_TOKEN` (escopo `User`) **e** o header em
`%USERPROFILE%\.config\opencode\opencode.json`, e rodar de novo o `verify-ai-memory.ps1`
(o check `Authorization difere da variável de ambiente` existe justamente para pegar
rotação pela metade).

---

## Anexo A — o que é escrito no Windows

| Caminho | O quê |
|---|---|
| `%LOCALAPPDATA%\Programs\ai-memory\ai-memory.exe` | o binário (PATH do usuário aponta para cá) |
| `%USERPROFILE%\.config\opencode\opencode.json` | entrada MCP `mcp.servers.ai-memory` |
| `%USERPROFILE%\.config\opencode\plugins\ai-memory-opencode2.ts` | plugin de captura (hooks) |
| `%USERPROFILE%\.config\opencode\skills\ai-memory-*\SKILL.md` | as **6 skills gerenciadas** de roteamento (ver §11) |
| `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\ai-memory` | **só** se rodar `setup` — deve **não** existir |

## Anexo B — resumo (copiar e colar)

```powershell
# 1) binário
irm https://github.com/akitaonrails/ai-memory/releases/latest/download/install.ps1 | iex

# 2) servidor central
$Url = "https://omarchy.tail07368.ts.net"; $Token = "<TOKEN>"
[Environment]::SetEnvironmentVariable("AI_MEMORY_SERVER_URL", $Url,   "User")
[Environment]::SetEnvironmentVariable("AI_MEMORY_AUTH_TOKEN", $Token, "User")
# para a JANELA atual (escopo de processo), repita sem o terceiro argumento:
[Environment]::SetEnvironmentVariable("AI_MEMORY_SERVER_URL", $Url)
[Environment]::SetEnvironmentVariable("AI_MEMORY_AUTH_TOKEN", $Token)

# 3) conectividade
curl.exe https://omarchy.tail07368.ts.net/healthz

# 4) MCP + captura
ai-memory install-mcp   --client opencode2 --apply --server-url "$Url/mcp" --auth-token "$Token"
ai-memory install-hooks --agent  opencode2 --apply --as-user usuario --server-url "$Url" --auth-token "$Token"

# 5) conferir PELO AGENTE — o CLI administrativo da 403 por design (ver §8)
#    peca: "o que já sabemos sobre o isolamento por usuário do mem0?"
```

---

## Anexo C — situação do servidor (para quem for reinstalar do zero)

O servidor central é um **systemd --user** nesta estação, escutando em `127.0.0.1:49375`
(a porta default `49374` colide com o serviço V2 do OpenCode). O acesso remoto é publicado
pelo **Tailscale Serve** — HTTPS com certificado real, **só na tailnet**, sem expor nada na
LAN nem na internet:

```bash
tailscale serve --bg 127.0.0.1:49375     # https://omarchy.tail07368.ts.net/ -> 127.0.0.1:49375
```

O `allowed_hosts` do servidor precisa conter `omarchy.tail07368.ts.net`, e o bind **continua**
em loopback (o uso local não depende do Tailscale).

---

## Anexo D — teste de fumaça de uma chave (para a próxima máquina)

Prova que a chave autentica e lê o projeto certo. Rode na **estação Omarchy**; para provar a
escrita, troque `memory_query` por `memory_write_page` (exige `path` **e** `body`) e apague a
página depois, como root.

```python
import json, os, urllib.request as u
K = open(os.path.expanduser('~/.local/share/ai-memory/api-keys/b550m-aorus-elite.key')).read().strip()
U = 'http://127.0.0.1:49375/mcp'
def post(p, sid=None):
    r = u.Request(U, data=json.dumps(p).encode(), method="POST")
    r.add_header("Authorization", "Bearer " + K)
    r.add_header("Content-Type", "application/json")
    r.add_header("Accept", "application/json, text/event-stream")
    if sid: r.add_header("Mcp-Session-Id", sid)
    try:
        x = u.urlopen(r, timeout=180); return x.status, dict(x.headers), x.read().decode()
    except u.HTTPError as e: return e.code, dict(e.headers), e.read().decode()
def payload(b):
    for l in b.splitlines():
        if l.startswith("data:"): return json.loads(l[5:].strip())
    try: return json.loads(b)
    except Exception: return None
st, h, _ = post({"jsonrpc":"2.0","id":1,"method":"initialize","params":{
  "protocolVersion":"2025-06-18","capabilities":{},
  "clientInfo":{"name":"smoke","version":"0"}}})
sid = h.get("mcp-session-id"); print("initialize ->", st)
post({"jsonrpc":"2.0","method":"notifications/initialized"}, sid)
st, _, b = post({"jsonrpc":"2.0","id":2,"method":"tools/call","params":{
  "name":"memory_query","arguments":{"workspace":"default","project":"davy-jones-hermes",
  "query":"isolamento por usuario do mem0","limit":2}}}, sid)
print("query ->", st, "|", json.dumps(payload(b), ensure_ascii=False)[:120])
```

Esperado: `initialize -> 200` e `query -> 200` com páginas do lab. **403** = a credencial não
tem permissão para aquele recurso; **401** = chave revogada ou ausente.

> Uma **chave** nunca roda `status`/`doctor`/`write-page` (rotas `/admin/*`, root-only). Para
> inspecionar a base use o token raiz na estação Omarchy; para operar a memória, o agente via MCP.