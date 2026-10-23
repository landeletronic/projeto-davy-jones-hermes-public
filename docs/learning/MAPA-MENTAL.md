# Mapa Mental — Do Básico ao Avançado

> **Fonte:** Flow #663 — Fábio Akita (`https://www.youtube.com/watch?v=N3eU-2VIByQ`) · ~4h17m
> **Objetivo:** trilha de evolução de programador, do básico ao avançado, ancorada nas ideias
> da transcrição e cruzada com o seu lab de IA local (jurídico) e com o uso do OpenCode.

## Legenda

| Marca | Significado |
|---|---|
| **[A]** | Ideia do Akita na transcrição |
| **[P]** | Aplicação ao seu projeto (lab IA local / escritório jurídico) |
| **[O]** | Como isso vira prática no OpenCode |
| ✅ | Você já domina isto |
| 🔄 | Você está aqui agora |
| ⏭️ | Próximo passo natural |

---

## N0 — Postura (o "porquê" antes da técnica)

- **[A] "Vai e faz."** O Akita recebe todo dia *"como escrevo meus prompts? você acha que eu deveria…?"* — resposta: **para de perguntar se deveria, faz**. As pessoas não fazem porque não querem ver que não sabem.
- **[A] Ninguém acerta de primeira.** O jogo dele saiu **depois de ~70 versões em 2 meses**. Errar 500 vezes *é* o processo, não a falha.
- **[A] Ser promíscuo com ferramenta.** *"Todo programador tem que ser promíscuo com ferramenta"* — dormir na cama de todas, e trocar quando quiser. *"Foda-se o nome"* (Claude, Codex, Manus, DeepSeek…). O que importa é o resultado e quem paga é você.
- **[A] "AI slop":** quem reclama de slop sem ter escrito **uma linha de código** está repetindo termo de papagaio. *"Primeiro você escreve 1000 posts de blog… e aí você vem conversar sobre AI Slop."*
- **[A] Experimentar > assistir.** *"É o que todo desenvolvedor deveria estar fazendo agora: experimentando."*

**[P]** Seu lab inteiro é isso na prática: você não leu sobre stacks locais — **construiu** (Qdrant + Ollama + Open WebUI + Hermes/mem0), fase a fase, com validação. 🔄
**[O]** No OpenCode, "vai e faz" = pedir a ação, não a opinião. Deixe a IA executar e depois revisar.

---

## N1 — Básico (a base que não muda)

- **Fundamentos de computação e de engenharia de software** — *"isso que a gente aprende na faculdade ou aprende em projetos"*: existe engenharia para lidar com os problemas que aparecem na prática.
- **Terminal / Linux / redes** — SSH, portas, permissões, processos, firewall.
- **Versionamento (Git)** — histórico, branches, rollback.
- **O conceito de teste** — o que é um teste, para que serve.
- **Ambientes** — entender que existe dev e produção, e por que separar.

**[P]** ✅ Você já tem N1 sólido: Docker/Compose, SSH, portas, `ufw` + cadeia `DOCKER-USER`, bind-mounts, GPU (ROCm/`HSA_OVERRIDE_GFX_VERSION`).
**[O]** `git`/diff são o "undo" do trabalho com IA: sempre revisar o diff antes de aceitar.

---

## N2 — Intermediário (onde a maioria empaca)

### 2.1 Teste automatizado e regressão — **[A] o coração do episódio**

- **Sintoma de quem não tem teste:** *"um passo pra frente, dois pra trás"* — o bug volta **nos mesmos lugares**, o projeto não anda.
- **A correção:** ao corrigir um bug, **escrever um teste que falha primeiro**, corrigir, e o teste passa → **aquele bug nunca mais aparece**.
- **"É um conceito de engenharia de software"** — regressão. Cada **regra do seu sistema vira um teste** (no jogo de cartas: cada regra = um teste; é o *manual de instruções em código*).
- **Teste de integração:** jogar "para valer" cobre o que o teste pequeno não cobre — mas *"você fode menos seu computador"* rodando os testes simulados primeiro.
- **Deixe o agente fazer isso por você:** peça personas de agentes que *"sabem as regras"* e geram os casos de teste; depois uma rotina que roda tudo **antes de soltar em produção**. Uma vez que o agente *sabe que existem testes*, ele detecta e corrige o próprio bug antes de você pedir.

### 2.2 Ambientes e deploy

- **dev → staging / beta testers → produção.** *"Sua produção é o seu stage"* só enquanto os usuários são amigos.
- Beta tester = *"como se fosse o staging"*: acesso antecipado, sabendo que pode quebrar. O público geral **não perdoa**.
- **Deploy sem derrubar quem está usando** — aí entra arquitetura.

### 2.3 Regras do projeto (AGENTS.md)

- **[A]** As instruções ficam num `AGENTS.md` que **toda sessão lê**: "toda vez que corrigir um bug, crie um teste de regressão" é uma regra viva.

**[P]** 🔄 **Este é o seu ponto exato de avanço.** O lab tem validações manuais (checklists no `docs/plans/PLANO-IMPLEMENTACAO-MEM0.md`), mas **não tem suíte de teste nem CI**. O passo N2 aplicado ao lab: transformar os checklists em testes executáveis.
**[O]** Placar: `AGENTS.md` com regras ("todo bug → teste de regressão"), `opencode` rodando a suíte, revisão de diff obrigatória.

---

## N3 — Avançado (IA e Agentes) — **onde você está**

### 3.1 O que mudou em 2026

- **[A] "2026 é o ano dos agentes."** O que destravou não foi o modelo "ficar gênio" — foi o **agente poder testar**:
  > *"ele continua dando uma resposta burra, mas ele agora testa. É o que a gente faz com o júnior: vem com a resposta, falha, testa de novo, conserta… até resolver. Esse é o grande diferencial deste ano."*
- **Agente enxerga a execução.** Antes (chat) era só texto; agora o modelo *executa, vê o erro e itera*.
- **Protocolos de agentes** amadureceram (a junção **modelo + agente** é o que virou produtivo).
- **Harness vs modelo:** *"é muito de ajuste da combinação de harness com o diferencial do modelo"*. Ferramentas viraram commodity: *"não tem nada que um tem que o outro já não tem."*
- **[A] Contexto é inimigo:** *"contexto longo demais prejudica mais do que ajuda."*

### 3.2 Memória gerenciada — **[A] o núcleo do "AI Memory"**

- **Memória curta / memória longa**, com **consolidação** (decisões, conceitos, "gotchas") e **limpeza** (o que não se acessa vira ruído e é esquecido — *"como a gente quando sonha"*).
- **Fora da sessão**, porque a sessão do agente **compacta e perde** memória.
- **Inbox entre agentes:** um agente pede ao outro *via memória* — e serve de onboarding para *"qualquer um que entra: um júnior, um terceiro…"* → *"ele tem que descobrir em algum lugar o que essa galera já fez, quais as regras do projeto."*
- **RAG × wiki em Markdown:** *"RAG era interessante quando a janela era pequena. Agora que todas têm janela de 1 milhão, é mais fácil o agente ir no arquivo de texto e pegar o trecho."* Formato aberto (OKF/Markdown) > banco opaco.
- **Plug-and-play** via MCP.

### 3.3 Avaliar sem se enganar

- **Nenhum benchmark diz o melhor em tudo** — cada um diz o melhor *para aquele teste*.
- **[A] Faça o seu:** *"é que nem uma prova de inglês"* — testar vocabulário do dia a dia não diz nada sobre o científico. O benchmark do Akita simula um **agente sabotador** injetando código ruim: *"mesmo assim, modelos mais fracos não conseguem achar todas as sabotagens."*
- **Modelo certo por tarefa:** local pequeno serve para *classificar e-mail, traduzir* — *"LLM é large language model, a melhor coisa que ele faz é linguagem"*. Para programar sério: frontier (Opus/Sonnet/DeepSeek/Kimi/GLM).

### 3.4 IA local — expectativa realista

- **[A] Hard consumer não programa sério:** *"não existe modelo de 32 GB que consiga programar"* — no máximo ~70B/70 GB. A 5090 (32 GB) já é apertada; há rumor de sair de linha.
- Local brilha em **tarefas simples** (classificar, resumir, rotear), não em substituir o Claude para codar.

### 3.5 Segurança com agentes

- **[A] Nunca dê suas contas ao agente.** *"É uma coisa que eu não faço jamais, jamais."* Agentes remotos autenticando em tudo e rodando sozinhos = perigo.
- Ferramenta própria: **AI Jail** (contêiner de segurança para agentes).

**[P]** 🔄 **Esta é literalmente a sua fase atual:** o plugin **mem0** *é* um sistema de memória curta/longa com consolidação; o `X-Hermes-Session-Key` resolve o **isolamento por usuário**; o Qdrant é o store compartilhado (RAG futuro + memória). Você já entendeu — como o Akita diz — que *"memória é uma coisa que você tem que gerenciar"*.
**[O]** Fazer o OpenCode consumir/gerenciar essa memória (regras de projeto + o que persistir entre sessões) é o elo natural entre N3 e N2.

---

## N4 — Sênior (julgamento, não digitação)

- **[A] Os 4 itens:** saber **o que fazer**, saber **o que não fazer**, saber **como testar**, e **ter um oráculo** para confirmar o resultado. *"Saber testar e ter suíte de teste e confirmação é a parte mais importante."*
- **[A] Sangue frio na catástrofe.** No caso dos 90 TB (RAID degradado + disco falhando): *"a primeira reação de um júnior numa catástrofe é fazer merda, é aumentar a catástrofe."* O sênior **para e pensa de novo**.
- **[A] Saber dizer não ao agente.** O agente insistia em usar Samba "porque é emergência"; o Akita forçou SSH **porque sabia que tinha que funcionar**. *"A diferença é: eu sei o que tem que ser feito."*
- **[A] Recuperação de catástrofe é meticulosa:** inventário, comparação, paralelismo calibrado (saturar banda sem derrubar o resto).
- **[A] Carreira:** *"toda carreira que é só fazer copy-paste da mesma coisa, acabou"* — nunca foi carreira, era temporário (operador de cartão perfurado, ábaco → calculadora, thumbnail no Photoshop → Canva).
- **[A] It's just Iron Man builds:** Mark 85 = 85 builds iterativos, *"um bug de cada vez"* — exatamente o método pedido.
- **[A] Open source** como exercício para quem não sabe que carreira quer.
- **[A] Ensinar é a prova:** ele fez um **micro-GPT** (200 linhas → modelo de 300M) para mostrar que *"não é bicho de sete cabeças, não vai ter Skynet, não vai ter consciência."* Saber **de onde vêm os dados, tokenização, treino, fine-tuning** = fundamento.

**[P]** Sênior no seu lab = não só subir o stack, mas saber **quando não mexer** (ex.: não criar `mem0_memories` na mão com dims erradas), manter **oráculo** (validações) e operar **recuperação** sem pânico.
**[O]** O papel do OpenCode aqui é ser o "júnior rápido": você define o oráculo, ele itera. O julgamento fica com você.

---

## N5 — Seu projeto atual (lab de IA local — jurídico)

### 5.1 Decisões consolidadas

| Tema | Escolha |
|---|---|
| Escala de uso | **Escritório pequeno (2–10)** → isolamento por usuário, backup, auditoria leve |
| Memória | **mem0 OSS in-process** no Hermes (0 containers novos) |
| Vector store | **Qdrant compartilhado** (`mem0_memories` + RAG futuro, 1024 dims) |
| Identidade | Login e-mail+senha no Open WebUI; `user_id` = e-mail (`X-Hermes-Session-Key`) |
| 100% local | Nada depende de internet |
| Honcho | Removido permanentemente |
| Renovação TLS | Autoassinado até 2029; alerta aos 30 dias + `tools/make_tls_cert.sh --force --reload` (manual de propósito) |
| Higiene da memória | Job diário (dedup + teto); TTL desligado até o escritório definir o prazo (LGPD) |

### 5.2 Estado (atualizado em 2026-10-20)

- **Fases 0–7** ✅ — 12 containers `healthy`, TLS na LAN, RAG com citação, monitoramento,
  backup com restore provado e CI diário.
- **Pós-relatório** ✅ — itens **#1 a #10** fechados (o #4 em 2026-10-20), cada um com check no
  oráculo; quase todo o P3 também (KV `q4_0`, base de teste, Qdrant 1.19.2, `grafana.db` no
  backup). Detalhe e evidências em **`docs/reports/RELATORIO-LACUNAS.md`**.
- **Aberto** — citação verificável, retenção LGPD (política), auditoria leve e off-site de verdade
  (o pull já confere SHA-256 e aceita `-ExtraDest`, mas o destino ainda é a mesma máquina).
- **Oráculo** — `tests/verify_stack.sh`, **139 checks**; CI diário 04:10.
- **Entrada da documentação** — `README.md` (visão geral) e `AGENTS.md` (regras).

### 5.3 O que "escritório 2–10" muda no roadmap

- **Isolamento por usuário** já resolvido (memória por e-mail) — mas decidir se haverá **memória por caso/cliente**.
- **Backup** deixa de ser opcional (Qdrant + volume do Open WebUI).
- **Auditoria leve** (quem perguntou o quê) e **retenção** (LGPD/sigilo profissional) entram no escopo.
- **Grafana** para saber se está tudo de pé sem SSH.

---

## N6 — Uso do OpenCode (o "par de mãos" da trilha)

| Nível | Como o OpenCode entra |
|---|---|
| N1 | Explicar/inspecionar (`read`, `grep`, `glob`), rodar comandos no host |
| N2 | Criar `AGENTS.md` com regras; gerar e rodar **suítes de teste**; revisar diff |
| N3 | Gerenciar **memória/contexto** (o que persiste entre sessões); subagentes para tarefas paralelas |
| N4 | Executar planos com **oráculo**; você mantém o julgamento e diz "não" (como no caso SSH×Samba) |
| N5 | Executar as fases do lab com validação a cada passo |

**Boa prática que o próprio episódio valida:** regra no `AGENTS.md` + teste que falha primeiro + revisão obrigatória. O agente fica rápido; **você** fica no comando.

---

## Onde você está (leitura honesta)

```
N0 Postura .......... ✅ (você constrói, não só consome)
N1 Básico ........... ✅ (Docker, rede, Linux, GPU)
N2 Intermediário .... 🔄▶ (falta TESTE AUTOMATIZADO + CI no lab)
N3 Avançado/Agentes . 🔄 (mem0/isolamento/memória — está no meio)
N4 Sênior ........... ◻ (julgamento/oráculo — em construção)
```

- **Você está no meio do N3.** Entende agentes, memória e isolamento — mas o **N2 ainda não fechou** no lab.
- **Próximo passo natural:** aplicar N2 ao N5 → pegar os checklists das fases e transformar em **teste + CI**. Foi exatamente o que o Akita descreve como o salto: *"agora eu sei que estou andando pra frente."*

---

## Checklist de evolução (a cada ciclo)

- [ ] Escrevi um teste que **falha primeiro** antes de corrigir?
- [ ] O bug corrigido virou **teste de regressão** (regra no `AGENTS.md`)?
- [ ] Tenho um **oráculo** que confirma que funciona (não é "achei que funcionou")?
- [ ] Sei **o que não fazer** (limites: não mexer no que não entendo)?
- [ ] Estou **experimentando** ou só assistindo?
- [ ] Consigo **trocar de ferramenta** sem perder a memória/decisões do projeto?
- [ ] Mantive o **contexto enxuto** (memória consolidada ≠ despejar tudo)?
- [ ] Fiz o deploy **sem derrubar** quem estava usando?

---

### Frases-âncora do episódio (para reler)

> *"Ele continua dando a resposta burra, mas ele agora testa. É o que a gente faz com o júnior."*

> *"Se ele tivesse feito um teste automatizado em cima desses lugares que dão bug, aquele bug não aparece nunca mais."*

> *"Um passo pra frente, dois pra trás" só acontece em quem não tem teste.*

> *"Todo programador tem que ser promíscuo com ferramenta."*

> *"2026 é o ano dos agentes."*

> *"A diferença é: eu sei o que tem que ser feito."*

> *"Vai e faz."*
