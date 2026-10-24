# install_tutor_tiradentes.py — instala o Tutor Tiradentes no Open WebUI

| | |
|---|---|
| Instalador | `ops/bin/install_tutor_tiradentes.py` |
| Pipe | `ops/open-webui/tutor_tiradentes.py` |
| Quando roda | em todo `ops/deploy/sync-to-host.ps1` (idempotente) |
| Banco | `/data/questoes.db`, bind de `~/rag-state/questoes.db` com `:ro` |
| Modelo interno | `qwen3:8b-chat-16k`, pela rede Docker local |
| Nome na interface | **Tutor Tiradentes — 9º ano** |

## O que instala

Pela API nativa do Open WebUI 0.12.3, o instalador cria ou atualiza:

1. a Function/Pipe `tutor_tiradentes`, ativa e não global;
2. o modelo de mesmo ID, com o nome amigável exibido à aluna;
3. a permissão `user/* read` do modelo e da base `Tiradentes BM`;
4. o vínculo da base `Tiradentes BM` como apoio conceitual.

O token administrativo dura dez minutos e é assinado **dentro do container** com o
`WEBUI_SECRET_KEY` do PID 1. Nenhum segredo entra no repositório ou sai do container.

## Contrato de segurança

- Ano, número e disciplina são extraídos pelo Pipe e consultados diretamente no SQLite.
- O banco abre com `mode=ro` + `PRAGMA query_only`; o bind-mount também é somente leitura.
- A questão só segue ao modelo se ano, número, disciplina, documento, página, enunciado,
  alternativas e gabarito forem válidos.
- A base vetorial ajuda apenas com conceitos e fórmulas; não identifica questão por ano/número.
- Falha de validação devolve a mensagem amigável fixa, sem procurar substituta nem inventar.
- Imagem sem ano/número recebe orientação amigável antes de o Ollama ser chamado; erro
  técnico de visão ou `mmproj` não chega à usuária.

## Aplicar ou reinstalar

Se o bind-mount ainda não existe, recrie **somente** o Open WebUI primeiro:

```bash
ssh davy-jones-hermes 'cd /home/usuario/hermes-architect && docker compose up -d open-webui'
```

Depois execute o deploy normal, que instala o Tutor e roda o oráculo:

```powershell
powershell -File ops\deploy\sync-to-host.ps1
```

Para executar apenas o instalador após os arquivos já estarem sincronizados:

```bash
ssh davy-jones-hermes "docker cp /home/usuario/hermes-architect/ops/open-webui/tutor_tiradentes.py open-webui:/tmp/tutor_tiradentes.py && docker cp /home/usuario/hermes-architect/ops/bin/install_tutor_tiradentes.py open-webui:/tmp/install_tutor_tiradentes.py && docker exec open-webui python /tmp/install_tutor_tiradentes.py"
```

## Verificar e diagnosticar

```bash
ssh davy-jones-hermes 'bash /home/usuario/hermes-architect/tests/verify_stack.sh'
ssh davy-jones-hermes 'docker exec -i open-webui python - --resolver' < tests/smoke_tutor.py
```

O segundo comando faz o E2E completo como usuário comum e pode levar alguns minutos. Sem
`--resolver`, o smoke é rápido: comprova visibilidade do modelo e falha fechada para questão
inexistente sem chamar o LLM.

| Sintoma | Diagnóstico / ação |
|---|---|
| `/data/questoes.db ausente` | aplique `docker compose up -d open-webui`; `restart` não adiciona mount |
| modelo não aparece para usuário comum | rode o instalador e confira os grants no oráculo |
| questão existente falha fechado | rode `questoes conferir` e consulte ano/número diretamente |
| Function diverge do repositório | rode `sync-to-host.ps1`; ele reaplica o código pela API |
| imagem produz erro técnico | confira se a Function instalada tem o mesmo SHA-256 da fonte do repo |
