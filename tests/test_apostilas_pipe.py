#!/usr/bin/env python3
"""Regressão local do Pipe Apostilas Tiradentes (só stdlib)."""

import asyncio
import importlib.util
import os


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "ops", "open-webui", "apostilas_tiradentes.py")
spec = importlib.util.spec_from_file_location("apostilas_tiradentes", SOURCE)
apostilas = importlib.util.module_from_spec(spec)
spec.loader.exec_module(apostilas)


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)


def main():
    check(apostilas.modo_pedido("Explique porcentagem") == "explicar", "modo explicar")
    check(apostilas.modo_pedido("Resuma o conteúdo sobre frações") == "resumir", "modo resumo")
    check(apostilas.modo_pedido("Encontre um exercício da apostila") == "localizar", "modo localizar")
    check(apostilas.modo_pedido("Crie três exercícios inéditos") == "criar", "modo criar")
    check(apostilas.modo_pedido("Dê apenas uma dica") == "dica", "modo dica")
    check(apostilas.modo_pedido("Corrija minha resposta") == "corrigir", "modo corrigir")

    pedido_regressao = (
        "continuando os estudos sobre expressões algébricas. pode aprofundar mais este conteúdo. "
        "se tiver acesso a internet pode verificar material didático externo."
    )
    check(apostilas.disciplina_pedido(pedido_regressao, []) == "matematica",
          "expressões algébricas determinam Matemática")
    check(apostilas.pede_internet(pedido_regressao), "pedido de internet detectado")
    check(not apostilas.pede_internet("Explique expressões algébricas usando a apostila."),
          "busca externa não é implícita")
    check(apostilas.tem_aderencia("expressões algébricas", ["Classificação da expressão algébrica"]),
          "aderência lexical aceita variação singular/plural")
    check(not apostilas.tem_aderencia("números complexos", ["Operações com radicais e números reais"]),
          "vizinho vetorial sem o assunto não conta como fonte suficiente")
    check(apostilas.consulta_busca(
        "Usando a apostila de Matemática, explique porcentagem para o 9º ano e informe a fonte."
    ) == "porcentagem", "embedding usa o assunto, não as instruções do pedido")

    metadata = {
        "base_user_prompt": "Explique porcentagem usando a apostila de Matemática.",
        "sources": [{
            "source": {"name": "tiradentes-bm-apostila médio - matemática.pdf"},
            "document": ["Porcentagem representa uma razão de base 100."],
        }],
    }
    check(apostilas.pergunta_original(
        [{"role": "user", "content": "template RAG diferente"}], metadata
    ).startswith("Explique porcentagem"), "pergunta original preservada")
    apoio, fontes = apostilas.contexto_rag(metadata)
    check("base 100" in apoio, "texto RAG preservado")
    check(fontes == ["tiradentes-bm-apostila médio - matemática.pdf"], "fonte preservada")

    metadata_errado = {
        "base_user_prompt": pedido_regressao,
        "sources": [{
            # O OWUI 0.12.4 pode esconder o arquivo e entregar só o nome da coleção.
            "source": {"name": "Apostilas Tiradentes"},
            "document": ["Pontuação e classes gramaticais."],
        }],
    }
    apoio_errado, fontes_erradas = apostilas.contexto_rag(metadata_errado, "matematica")
    check(not apoio_errado and not fontes_erradas,
          "fonte de Português é rejeitada para pedido explícito de Matemática")
    prompt = apostilas.montar_prompt("Explique porcentagem", "explicar", ["pedido"], apoio)
    check("<trechos_das_apostilas>" in prompt and "invente conteúdo" in prompt.lower(),
          "fonte delimitada e contrato contra invenção")

    async def nao_chamar(_prompt):
        raise AssertionError("LLM foi chamado sem fonte")

    chamar_anterior = apostilas.chamar_ollama
    apostilas.chamar_ollama = nao_chamar
    try:
        sem_fonte = asyncio.run(apostilas.Pipe().pipe({"messages": [
            {"role": "user", "content": "Explique um conteúdo da apostila."},
        ]}))
        check(sem_fonte == apostilas.FALHA_SEM_FONTE, "sem fonte falha fechado")
        imagem = asyncio.run(apostilas.Pipe().pipe(
            {"messages": [{"role": "user", "content": "Explique esta imagem"}]},
            __files__=[{"name": "foto.png", "type": "image"}],
        ))
        check(imagem == apostilas.SEM_VISAO, "imagem recebe orientação amigável")
    finally:
        apostilas.chamar_ollama = chamar_anterior

    prompts = []

    async def resposta_falsa(prompt):
        prompts.append(prompt)
        return "Porcentagem é uma razão em cada cem."

    apostilas.chamar_ollama = resposta_falsa
    recuperar_anterior = apostilas.recuperar_contexto
    pesquisar_anterior = apostilas.pesquisar_web
    try:
        resposta = asyncio.run(apostilas.Pipe().pipe(
            {"messages": [{"role": "user", "content": "Explique porcentagem."}]},
            __metadata__=metadata,
        ))
        check("Porcentagem é" in resposta and "Fontes recuperadas" in resposta,
              "explicação inclui fontes")
        check("apostila médio - matemática.pdf" in resposta, "nome da fonte na resposta")

        metadata_criar = dict(metadata)
        metadata_criar["base_user_prompt"] = "Crie um exercício inédito."
        criada = asyncio.run(apostilas.Pipe().pipe(
            {"messages": [{"role": "user", "content": "Crie um exercício inédito."}]},
            __metadata__=metadata_criar,
        ))
        check("Atividade criada pelo tutor" in criada and "não é uma questão oficial" in criada,
              "atividade inédita rotulada")
        check(any("não revele" in p.lower() for p in prompts), "atividade protege a resposta")

        recuperacoes = []

        async def recuperar_falso(pergunta, disciplina):
            recuperacoes.append((pergunta, disciplina))
            return (
                "Fonte: tiradentes-bm-apostila médio - matemática.pdf\n"
                "Expressões algébricas contêm números, letras e operações.",
                ["tiradentes-bm-apostila médio - matemática.pdf"],
            )

        apostilas.recuperar_contexto = recuperar_falso
        resposta_regressao = asyncio.run(apostilas.Pipe().pipe(
            {"messages": [
                {"role": "user", "content": "Quero estudar Matemática."},
                {"role": "assistant", "content": "Vamos estudar expressões algébricas."},
                {"role": "user", "content": pedido_regressao},
            ]},
            __metadata__=metadata_errado,
        ))
        check(recuperacoes and recuperacoes[0][1] == "matematica",
              "Pipe refaz recuperação na disciplina correta")
        check("apostila médio - matemática.pdf" in resposta_regressao,
              "resposta usa fonte matemática recuperada internamente")
        check("pesquisa externa não acionada" in resposta_regressao.lower(),
              "fonte local tem prioridade mesmo com opt-in externo")

        async def sem_apoio(_pergunta, _disciplina):
            return "", []

        buscas = []

        async def pesquisar_falso(pergunta):
            buscas.append(pergunta)
            return (
                "Título: Expressões algébricas — exemplo externo\n"
                "URL: https://example.edu/algebra\n"
                "Trecho: Material didático sobre variáveis e operações.",
                [("Expressões algébricas — exemplo externo", "https://example.edu/algebra")],
            )

        apostilas.recuperar_contexto = sem_apoio
        apostilas.pesquisar_web = pesquisar_falso
        resposta_web = asyncio.run(apostilas.Pipe().pipe(
            {"messages": [{"role": "user", "content": pedido_regressao}]},
            __metadata__={"base_user_prompt": pedido_regressao, "sources": []},
        ))
        check(len(buscas) == 1, "SearXNG é chamado quando falta fonte e há pedido explícito")
        check("Fontes externas consultadas" in resposta_web and "https://example.edu/algebra" in resposta_web,
              "fonte web é rotulada e citada com URL")

        buscas.clear()
        sem_pedido_web = asyncio.run(apostilas.Pipe().pipe(
            {"messages": [{"role": "user", "content": "Explique números complexos."}]},
            __metadata__={"base_user_prompt": "Explique números complexos.", "sources": []},
        ))
        check(not buscas and sem_pedido_web == apostilas.FALHA_SEM_FONTE,
              "ausência de fonte sem opt-in não aciona a internet")
    finally:
        apostilas.chamar_ollama = chamar_anterior
        apostilas.recuperar_contexto = recuperar_anterior
        apostilas.pesquisar_web = pesquisar_anterior

    print("PASS apostilas pipe: modos + RAG + fail-closed + fontes")


if __name__ == "__main__":
    main()
