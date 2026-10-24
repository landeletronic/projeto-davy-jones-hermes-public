#!/usr/bin/env python3
"""Smoke do Tutor pelo mesmo /api/chat/completions usado pelo navegador.

Roda DENTRO do open-webui. Sem argumento testa acesso comum + fail-closed (rápido,
sem LLM). Com --resolver chama o modelo local para a questão real 2025/Q26.
"""

import argparse
import json
import os
import sqlite3
import time
from datetime import datetime, timedelta, timezone

import jwt
import requests


DB = "/app/backend/data/webui.db"
BASE = "http://127.0.0.1:8080"
MODEL = "tutor_tiradentes"
FALHA = "Não consegui localizar com segurança essa questão. Peça ao responsável para verificar a base."


def pid1_env(name):
    with open("/proc/1/environ", "rb") as fh:
        for part in fh.read().split(b"\0"):
            if part.startswith(name.encode() + b"="):
                return part.split(b"=", 1)[1].decode()
    return ""


def token_usuario_comum():
    c = sqlite3.connect(DB)
    row = c.execute(
        "SELECT u.id,a.session_stamp FROM user u JOIN auth a ON a.id=u.id "
        "WHERE u.role!='admin' ORDER BY u.created_at LIMIT 1"
    ).fetchone()
    c.close()
    if not row:
        raise RuntimeError("não há usuário comum para o smoke")
    return jwt.encode({
        "id": row[0], "typ": "session", "auth_method": "password",
        "auth_time": int(time.time()), "session_stamp": row[1], "mfa_verified": False,
        "exp": datetime.now(timezone.utc) + timedelta(minutes=10),
    }, pid1_env("WEBUI_SECRET_KEY"), algorithm="HS256")


def chat(headers, texto=None, timeout=60, messages=None, files=None):
    if messages is None:
        messages = [{"role": "user", "content": texto}]
    payload = {
        "model": MODEL,
        "messages": messages,
        "stream": False,
    }
    if files:
        payload["files"] = files
    r = requests.post(BASE + "/api/chat/completions", headers=headers, json=payload, timeout=timeout)
    r.raise_for_status()
    data = r.json()
    return data["choices"][0]["message"]["content"]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--resolver", action="store_true")
    args = p.parse_args()
    headers = {"Authorization": "Bearer " + token_usuario_comum(), "Content-Type": "application/json"}
    models = requests.get(BASE + "/api/models", headers=headers, timeout=60).json()["data"]
    model = next((m for m in models if m.get("id") == MODEL), None)
    assert model and model.get("name") == "Tutor Tiradentes — 9º ano", "modelo não visível ao usuário comum"
    resposta = chat(headers, "Resolva a questão 99 de Matemática de 2019.")
    assert resposta.strip() == FALHA, "questão inexistente não falhou fechado"
    imagem = chat(
        headers,
        "Pode resolver esta imagem?",
        files=[{"type": "image", "name": "questao.png", "content_type": "image/png"}],
    )
    assert "não consigo ler imagens" in imagem.lower() and "ano e o número" in imagem.lower(), imagem
    treino = chat(headers, "Escolha uma questão de porcentagem para eu treinar.")
    assert "Questão para treinar" in treino and ("porcent" in treino.lower() or "%" in treino), treino
    parecida = chat(headers, messages=[
        {"role": "user", "content": "Quero tentar a questão 26 de Matemática de 2025."},
        {"role": "assistant", "content": "Tudo bem."},
        {"role": "user", "content": "Mostre outra questão parecida."},
    ])
    assert "Outra questão parecida" in parecida and "2025 — questão 26" not in parecida, parecida
    print("PASS tutor: acesso comum + fail-closed + imagem + assunto + questão parecida")
    if args.resolver:
        resposta = chat(headers, "Resolva passo a passo a questão 26 de Matemática de 2025.", 360)
        for esperado in ("2025", "26", "prova-2025.pdf", "página 9", "(C)", "-8"):
            assert esperado.lower() in resposta.lower(), f"resposta sem {esperado!r}"
        for secao in ("interpretação", "estratégia", "conferência", "gabarito"):
            assert secao in resposta.lower(), f"resposta sem seção {secao!r}"
        assert "<think>" not in resposta.lower() and "reasoning_content" not in resposta.lower(), \
            "raciocínio interno vazou no conteúdo"

        dica = chat(headers, "Dê apenas uma dica para a questão 26 de Matemática de 2025.", 360)
        dica_normalizada = dica.lower().replace("**", "")
        assert "-8" not in dica_normalizada and "alternativa c" not in dica_normalizada \
            and "resposta c" not in dica_normalizada and "gabarito" not in dica_normalizada, dica

        continuacao = chat(headers, timeout=360, messages=[
            {"role": "user", "content": "Quero tentar a questão 26 de Matemática de 2025."},
            {"role": "assistant", "content": "Tente com calma e me chame quando quiser."},
            {"role": "user", "content": "Agora mostre a resolução."},
        ])
        assert "prova-2025.pdf" in continuacao and "(C)" in continuacao and "-8" in continuacao, continuacao

        correcao = chat(headers, timeout=360, messages=[
            {"role": "user", "content": "Questão 26 de Matemática de 2025."},
            {"role": "assistant", "content": "Qual foi sua resposta?"},
            {"role": "user", "content": "Respondi D. Corrija a minha resposta."},
        ])
        assert "(C)" in correcao and "-8" in correcao and "gabarito" in correcao.lower(), correcao
        print("PASS tutor E2E: resolução + dica sem resposta + continuação + correção")


if __name__ == "__main__":
    main()
