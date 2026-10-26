# install_apostilas_tiradentes.py — instala o Apostilas Tiradentes no Open WebUI

| | |
|---|---|
| Instalador | `ops/bin/install_apostilas_tiradentes.py` |
| Pipe | `ops/open-webui/apostilas_tiradentes.py` |
| Quando roda | em todo `ops/deploy/sync-to-host.ps1` (idempotente) |
| Base exclusiva | **Apostilas Tiradentes** |
| Modelo interno | `qwen3:8b-chat-16k`, pela rede Docker local |
| Nome na interface | **Apostilas Tiradentes** |

## O que instala

O instalador usa a API nativa do Open WebUI 0.12.3 para:

1. criar ou localizar a base **Apostilas Tiradentes**;
2. identificar os arquivos em `/documents/concurso/tiradentes-bm/apostilas/` pelo SHA-256 físico e
   pelo nome achatado determinístico do worker (o `file.hash` de PDFs no OWUI pode ser diferente);
3. vincular à base exclusiva os mesmos arquivos já processados em **Tiradentes BM**;
4. criar ou atualizar a Function/Pipe `apostilas_tiradentes`;
5. criar o modelo amigável e liberar leitura para usuários comuns.

Os PDFs não são copiados. O mesmo `file_id` é ligado às duas bases, mas cada base possui seus próprios
vetores no Qdrant. O `rag-ingest` passa `--kb-extra "Apostilas Tiradentes"` para todo arquivo novo cujo
caminho esteja dentro de `concurso/tiradentes-bm/apostilas/`.

## Contrato pedagógico e de segurança

- A busca recebe somente conteúdo da base exclusiva de apostilas.
- O Pipe detecta a disciplina pelo pedido atual e, em pedidos elípticos de continuação, pelo
  histórico recente. A mensagem atual sempre vence o histórico.
- Fonte identificada como outra disciplina é rejeitada. Se a busca inicial do Open WebUI trouxer
  somente a disciplina errada, o Pipe refaz a recuperação local no Qdrant, restrita à disciplina
  correta e à base **Apostilas Tiradentes**.
- A resposta informa os nomes das fontes recuperadas.
- Sem trecho recuperado, o Pipe não chama o modelo e responde que não encontrou conteúdo suficiente.
- Exercício incompleto não pode ser reconstruído por suposição.
- Atividade criada pelo modelo é rotulada como **inédita e não oficial**.
- Dica não deve revelar a resposta antes da tentativa da aluna.
- Imagem recebe orientação amigável; o erro técnico de `mmproj` não aparece.
- A busca global do Open WebUI continua desabilitada. O Pipe consulta diretamente o SearXNG somente
  quando **as apostilas não sustentam o assunto** e a aluna pede explicitamente pesquisa na internet.
- Resultados externos são tratados como conteúdo não confiável, limitados a três, rotulados em
  seção própria e publicados com título e URL. Instruções encontradas nos resultados são ignoradas.
- Sem pedido explícito, ausência de fonte continua falhando fechado. O Tutor Tiradentes não participa
  desse fluxo e permanece restrito ao SQLite e às fontes locais.
- Provas oficiais por ano/número continuam sendo responsabilidade do **Tutor Tiradentes — 9º ano**.

## Aplicar ou reinstalar

O deploy normal sincroniza os arquivos, instala o modelo e roda o oráculo:

```powershell
powershell -File ops\deploy\sync-to-host.ps1
```

Para reinstalar apenas esta Function depois de os arquivos estarem sincronizados:

```bash
ssh davy-jones-hermes "docker cp /home/usuario/hermes-architect/ops/open-webui/apostilas_tiradentes.py open-webui:/tmp/apostilas_tiradentes.py && docker cp /home/usuario/hermes-architect/ops/bin/install_apostilas_tiradentes.py open-webui:/tmp/install_apostilas_tiradentes.py && docker exec open-webui python /tmp/install_apostilas_tiradentes.py"
```

## Verificar e diagnosticar

```bash
ssh davy-jones-hermes 'bash /home/usuario/hermes-architect/tests/verify_stack.sh'
ssh davy-jones-hermes 'docker exec -i open-webui python - --resolver' < tests/smoke_apostilas.py
```

| Sintoma | Diagnóstico / ação |
|---|---|
| modelo não aparece | rode o instalador e confira os grants no oráculo |
| conteúdo de prova aparece | confira se o modelo está ligado à base `Apostilas Tiradentes`, não à `Tiradentes BM` |
| arquivo novo não aparece | rode `rag-ingest`; arquivos em `apostilas/` recebem a base adicional automaticamente |
| assunto de Matemática recebe fonte de Português | rode o smoke com `--resolver`; o Pipe deve rejeitar a fonte incompatível e refazer a busca por disciplina |
| resposta diz que não encontrou | confira se o assunto existe nas apostilas e veja as fontes recuperadas; a aluna não precisa reformular um pedido que já identifica claramente o assunto |
| pesquisa externa não acontece | confirme duas condições: ausência de suporte local e verbo explícito de pesquisa junto de “internet”, “web”, “site” ou “material externo” |
| pesquisa externa falha | teste o JSON do SearXNG e a conectividade de saída; o Pipe deve responder sem inventar consulta ou links |
| exercício veio incompleto | procure pelo começo do enunciado ou peça outro; não mande o modelo completar |
