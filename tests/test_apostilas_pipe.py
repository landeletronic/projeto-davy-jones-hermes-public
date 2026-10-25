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
    finally:
        apostilas.chamar_ollama = chamar_anterior

    print("PASS apostilas pipe: modos + RAG + fail-closed + fontes")


if __name__ == "__main__":
    main()
