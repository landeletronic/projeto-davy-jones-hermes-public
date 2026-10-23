# make-public-repo.ps1 — espelho público sanitizado do lab

| | |
|---|---|
| Arquivo | `ops/deploy/make-public-repo.ps1` — **só no repositório privado** (o publicador não é copiado para o espelho) |
| Roda em | **Windows**, à mão |
| Destino | `landeletronic/projeto-davy-jones-hermes-public` (público) |
| Fonte | `git archive HEAD` do repo privado (só arquivos rastreados) |

> O publicador fica de fora do espelho de propósito: ele **contém** a tabela de redação, com o
> e-mail pessoal do dono como texto de origem. Copiá-lo faria a própria redação reescrevê-lo
> (o script publicado sairia sem sentido). Ele é ferramenta do repo privado, como o PAT.

## Por que snapshot e não clone

O **primeiro commit do repo privado** (`15feb19`) trazia a senha e o secret do dashboard `9119`
escritos no `docker-compose.yml`, e são exatamente as credenciais **em uso hoje**. Um clone do
privado — mesmo com um commit "removendo o arquivo" — deixaria essa senha alcançável no histórico.
Foi o mesmo cuidado que o `projeto-medusa-public` exigiu com o arquivo de acesso ao host.

Por isso o espelho **nasce de um snapshot**: uma árvore, um commit inicial. Cada publicação vira um
commit novo, sempre a partir do `HEAD` já sanitizado. Nenhum byte do passado entra.

## O que ele faz, em ordem

1. confere que está no repo privado e anota o `HEAD` (avisa se a árvore está suja — o snapshot usa
   o `HEAD`, não o working tree);
2. prepara a pasta local (`~\Downloads\davy-jones-hermes-public`), preservando o `.git`;
3. `git archive HEAD` → extrai na pasta (arquivos rastreados; o `.env` fica de fora pelo
   `.gitignore` e o script **falha** se ele aparecer) e remove o próprio publicador;
4. aplica a **tabela de redação**, preservando BOM e LF de cada arquivo;
5. **varre o resultado** e aborta antes de qualquer commit se sobrar segredo ou dado pessoal;
6. `git add -A` + commit (autor neutro `landeletronic@users.noreply.github.com` — o e-mail pessoal
   não vai nem no `git log`) e, com `-Push`, cria o repo no GitHub se preciso e faz o push via
   `GIT_ASKPASS`.

## Tabela de redação

| No privado | No público | Por quê |
|---|---|---|
| e-mail pessoal do dono | `admin@example.com` | aparece nas docs e como admin padrão das ferramentas |
| e-mail do 2º usuário de teste | `teste@example.com` | usado nos testes de isolamento A/B |
| caminho da pasta do usuário no Windows | `C:\Users\usuario` | os scripts de deploy citam o caminho absoluto |

IP da LAN (`192.168.15.231`) e o hostname `davy-jones-hermes` **ficam**: são rede interna e o nome
do projeto (mesmo critério do `projeto-medusa-public`).

## O que a varredura recusa

- qualquer **valor do `.env`** (chave do gateway, senha do Grafana, usuário/senha/secret do
  dashboard) — a mesma fonte da verdade que a suíte usa;
- arquivos com cara de segredo: `.env`, `*.db`, `*.bak`, `*.key`, `*.pem`, `*.crt`, `*.p12`,
  `*.pfx`, `*.kdbx`, `keystore`;
- `BEGIN … PRIVATE KEY`, o caminho pessoal do Windows, o e-mail pessoal, qualquer endereço do
  domínio de e-mail público, e `API_SERVER_KEY` com **valor literal** (interpolação `${VAR:?msg}`
  é o padrão certo);
- arquivo com mais de **1 MB**.

## Como rodar (no repositório privado)

```powershell
# conferir sem commitar nada
powershell -File ops\deploy\make-public-repo.ps1 -DryRun

# gerar o snapshot e revisar antes de publicar
powershell -File ops\deploy\make-public-repo.ps1

# gerar e publicar (cria o repo se não existir)
powershell -File ops\deploy\make-public-repo.ps1 -Push
```

O PAT fica em `%USERPROFILE%\.secrets\github-pat.txt` (escopos `repo`/`workflow`) e vai por
`GIT_ASKPASS` — **não** entra no `.git/config` nem no commit.

## Se falhar

| Sintoma | Causa | Ação |
|---|---|---|
| `varredura achou N problema(s)` | sobrou segredo/dado pessoal no snapshot | **não** publique: acrescente a regra na tabela de redação (ou remova o arquivo) e rode de novo |
| `pasta existe e não parece ser o repositório público` | `OutDir` aponta para outra pasta | conferir o caminho, ou `-Force` para recriar |
| `.env entrou no snapshot` | o `.env` foi versionado por engano | tirar do git **no privado** (o `.gitignore` já o exclui) |
| `push não confirmado` | o `git` escreve progresso em stderr | o script confere com `git ls-remote`; se divergir, ver o PAT e a rede |
| acentos quebrados nos `.ps1` publicados | arquivo sem BOM no privado | corrigir o BOM no arquivo de origem |

## Limite conhecido

A varredura é **por conteúdo conhecido** (valor do `.env` + padrões). Um segredo que exista só
dentro de um PDF ou de uma imagem **não** é detectado — nesse caso, o arquivo tem de sair da árvore
(é o mesmo limite da varredura da suíte).
