#!/usr/bin/env python3
"""Smoke do Apostilas Tiradentes pelo /api/chat/completions do navegador."""

import argparse
import sqlite3
import time
from datetime import datetime, timedelta, timezone

import jwt
import requests


DB = "/app/backend/data/webui.db"
BASE = "http://127.0.0.1:8080"
MODEL = "apostilas_tiradentes"


def pid1_env(name):
    with open("/proc/1/environ", "rb") as fh:
        for part in fh.read().split(b"\0"):
            if part.startswith(name.encode() + b"="):
                return part.split(b"=", 1)[1].decode()
    return ""


def token_usuario_comum():
    conn = sqlite3.connect(DB)
    row = conn.execute(
        "SELECT u.id,a.session_stamp FROM user u JOIN auth a ON a.id=u.id "
        "WHERE u.role!='admin' ORDER BY u.created_at LIMIT 1"
    ).fetchone()
    conn.close()
    if not row:
        raise RuntimeError("não há usuário comum para o smoke")
    return jwt.encode({
        "id": row[0], "typ": "session", "auth_method": "password",
        "auth_time": int(time.time()), "session_stamp": row[1], "mfa_verified": False,
        "exp": datetime.now(timezone.utc) + timedelta(minutes=10),
    }, pid1_env("WEBUI_SECRET_KEY"), algorithm="HS256")


def chat(headers, texto, timeout=60, files=None):
    payload = {"model": MODEL, "messages": [{"role": "user", "content": texto}], "stream": False}
    if files:
        payload["files"] = files
    response = requests.post(BASE + "/api/chat/completions", headers=headers, json=payload,
                             timeout=timeout)
    response.raise_for_status()
    return response.json()["choices"][0]["message"]["content"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--resolver", action="store_true")
    args = parser.parse_args()
    headers = {"Authorization": "Bearer " + token_usuario_comum(), "Content-Type": "application/json"}
    models = requests.get(BASE + "/api/models", headers=headers, timeout=60).json()["data"]
    model = next((item for item in models if item.get("id") == MODEL), None)
    assert model and model.get("name") == "Apostilas Tiradentes", \
        "modelo não visível ao usuário comum"
    imagem = chat(
        headers, "Explique esta imagem",
        files=[{"type": "image", "name": "pagina.png", "content_type": "image/png"}],
    )
    assert "não consigo ler imagens" in imagem.lower() and "matemática" in imagem.lower(), imagem
    print("PASS apostilas: acesso comum + imagem sem erro técnico")

    if args.resolver:
        resposta = chat(
            headers,
            "Usando a apostila de Matemática, explique porcentagem para o 9º ano e informe a fonte.",
            timeout=360,
        )
        normalizada = resposta.lower()
        assert "porcent" in normalizada, resposta
        assert "fontes recuperadas" in normalizada and "apostila" in normalizada, resposta
        assert "<think>" not in normalizada and "reasoning_content" not in normalizada, resposta
        print("PASS apostilas E2E: explicação didática + fonte")


if __name__ == "__main__":
    main()
