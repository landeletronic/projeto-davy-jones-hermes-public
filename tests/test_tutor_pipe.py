#!/usr/bin/env python3
"""Regressão local do parser/consulta do Pipe Tutor Tiradentes (só stdlib)."""

import importlib.util
import asyncio
import os
import sqlite3
import tempfile


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "ops", "open-webui", "tutor_tiradentes.py")
spec = importlib.util.spec_from_file_location("tutor_tiradentes", SOURCE)
tutor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tutor)


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)


def criar_banco(path):
    c = sqlite3.connect(path)
    c.executescript("""
    CREATE TABLE prova (ano TEXT PRIMARY KEY, arquivo TEXT);
    CREATE TABLE questao (ano TEXT, numero INTEGER, disciplina TEXT, enunciado TEXT, pagina INTEGER);
    CREATE TABLE alternativa (ano TEXT, numero INTEGER, letra TEXT, texto TEXT);
    CREATE TABLE gabarito (ano TEXT, numero INTEGER, letra TEXT, fonte TEXT);
    CREATE TABLE ano_status (ano TEXT PRIMARY KEY, status TEXT);
    INSERT INTO prova VALUES ('2025','concurso/tiradentes-bm/2025/prova_gabarito/prova-2025.pdf');
    INSERT INTO ano_status VALUES ('2025','ok');
    INSERT INTO questao VALUES ('2025',26,'matematica','Uma equação com percentual.',9);
    INSERT INTO questao VALUES ('2025',27,'matematica','Outra questão com desconto percentual de 20%.',10);
    INSERT INTO gabarito VALUES ('2025',26,'C','ocr-tabela');
    INSERT INTO gabarito VALUES ('2025',27,'A','ocr-tabela');
    """)
    for numero, correta in ((26, "C"), (27, "A")):
        for letra, texto in zip("ABCDE", ("zero", "dois", "menos oito", "oito", "raiz")):
            c.execute("INSERT INTO alternativa VALUES (?,?,?,?)", ("2025", numero, letra, texto))
    c.commit()
    c.close()


def main():
    check(tutor.extrair_referencia("Resolva a questão 26 de Matemática de 2025") ==
          {"ano": "2025", "numero": 26, "disciplina": "matematica"}, "extração exata")
    check(tutor.extrair_referencia("Q26/2025, português")["disciplina"] == "portugues", "português")
    msgs = [
        {"role": "user", "content": "Questão 26 de Matemática de 2025"},
        {"role": "assistant", "content": "..."},
        {"role": "user", "content": "Agora mostre a resolução"},
    ]
    check(tutor.referencia_da_conversa(msgs)["numero"] == 26, "referência do histórico")
    check(tutor.modo_pedido("Dê apenas uma dica") == "dica", "modo dica")
    check(tutor.modo_pedido("Quero tentar antes") == "tentar", "modo tentar")
    check(tutor.modo_pedido("Corrija minha resposta: C") == "corrigir", "modo corrigir")
    check(tutor.tem_imagem([{"name": "foto.jpg"}], []), "imagem detectada")
    metadata = {
        "base_user_prompt": "Resolva a questão 26 de Matemática de 2025",
        "sources": [{
            "source": {"name": "Tiradentes BM"},
            "document": ["Porcentagem representa uma razão de base 100."],
        }],
    }
    check(tutor.pergunta_original(
        [{"role": "user", "content": "template RAG com questão 99 de 2020"}], metadata
    ).endswith("2025"), "pergunta original preservada fora do template RAG")
    apoio = tutor.contexto_rag(metadata)
    check("Fonte: Tiradentes BM" in apoio and "base 100" in apoio, "contexto RAG delimitável")
    prompt = tutor.prompt_do_modo({
        "ano": "2025", "numero": 26, "disciplina": "matematica",
        "arquivo": "prova-2025.pdf", "pagina": 9, "enunciado": "Calcule.",
        "gabarito": "C", "fonte_gabarito": "ocr", "alternativas": [
            {"letra": "A", "texto": "1"}, {"letra": "C", "texto": "3"},
        ],
    }, "resolver", ["pedido"], apoio)
    check("<questao_confirmada>" in prompt and "<apoio_conceitual_nao_autoritativo>" in prompt,
          "questão estruturada e RAG têm fronteiras distintas")

    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "questoes.db")
        criar_banco(path)
        conn = tutor.conectar_ro(path)
        q = tutor.buscar_questao(conn, "2025", 26, "matematica")
        check(q and q["gabarito"] == "C" and q["pagina"] == 9, "consulta completa")
        check(q["arquivo"].endswith("prova-2025.pdf") and len(q["alternativas"]) == 5,
              "origem e alternativas")
        resposta_estruturada = tutor.resposta_resolvida(q, "Interpretação e resolução.")
        check("Enunciado:" in resposta_estruturada and "prova-2025.pdf" in resposta_estruturada
              and "Alternativa correta: (C)" in resposta_estruturada,
              "resposta garante dados estruturados e conferência")
        check(tutor.buscar_questao(conn, "2025", 26, "portugues") is None,
              "disciplina divergente falha fechado")
        check(tutor.buscar_questao(conn, "2025", 99) is None, "inexistente falha fechado")
        treino = tutor.escolher_por_texto(conn, "porcentagem", "matematica")
        check(treino and treino["numero"] == 26, "seleção por assunto")
        parecida = tutor.escolher_parecida(conn, q)
        check(parecida and parecida["numero"] == 27, "outra parecida")
        try:
            conn.execute("DELETE FROM questao")
            raise AssertionError("conexão permitiu escrita")
        except sqlite3.OperationalError as exc:
            check("readonly" in str(exc).lower() or "read-only" in str(exc).lower(), "erro read-only")
        conn.close()

        conectar_anterior = tutor.conectar_ro
        tutor.conectar_ro = lambda: conectar_anterior(path)
        try:
            resposta = asyncio.run(tutor.Pipe().pipe({"messages": [
                {"role": "user", "content": "Quero tentar a questão 26 de Matemática de 2025"},
                {"role": "assistant", "content": "Vamos tentar."},
                {"role": "user", "content": "Mostre outra questão parecida"},
            ]}))
            check("questão 27" in resposta and "questão 26" not in resposta,
                  "outra parecida não reutiliza a referência histórica")
        finally:
            tutor.conectar_ro = conectar_anterior
    print("PASS tutor pipe: parser + consulta exata + fail-closed + somente leitura")


if __name__ == "__main__":
    main()
