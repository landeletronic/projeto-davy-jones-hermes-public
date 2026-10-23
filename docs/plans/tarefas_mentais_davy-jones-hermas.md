# Tarefas mentais — rascunho do eixo de estudos (em andamento)

> Anotações do usuário; não é plano fechado. Discutir antes de implementar.

Terefas para realizar

[ ] criar diretório concurso a ser realizado, sub diretório ano, sub diretório "prova_gabarito" e "edital", onde os usuários podem gravar viam smb, para depois serem processados pela AI via fluxo de trabalho e disponibilizar na base de conhecimento dentro do open webui;

[ ] criar diretório de "documents" dos documentos para docling/RAG;
exemplo abaixo:

#### `documents/` — o inbox controlado

| Pasta | Conteúdo atual | Função |
|---|---:|---|
| `incoming/` | vazio | **Único ponto de entrada** aceito pelo RAG Worker |
| `originals/` | vazio | Cópia do documento canônico de origem |
| `processed/` | vazio | Reservado para pós-processamento |
| `rejected/` | vazio | Rejeições explícitas |
| `temporary/` | vazio | Trabalho transitório |

[ ]

---

> Desenho detalhado destes dois itens (árvores, nomes, manifest, fases):
> `docs/plans/DESENHO-INBOX-DOCUMENTS.md` — rascunho, aguardando "ok". 