#!/usr/bin/env python3
"""Instala/atualiza o Pipe e o modelo Tutor Tiradentes pela API nativa do OWUI.

Roda DENTRO do container open-webui. Não recebe nem grava credencial: assina uma
sessão administrativa curta com o segredo já existente no PID 1, como o uploader.
"""

import argparse
import json
import os
import sqlite3
import sys
import time
from datetime import datetime, timedelta, timezone

import jwt
import requests


BASE = "http://127.0.0.1:8080"
WEBUI_DB = "/app/backend/data/webui.db"
FUNCTION_ID = "tutor_tiradentes"
MODEL_NAME = "Tutor Tiradentes — 9º ano"
KB_NAME = "Tiradentes BM"
PUBLIC_READ = [{"principal_type": "user", "principal_id": "*", "permission": "read"}]


def fail(msg):
    print("ERRO: " + msg, file=sys.stderr)
    raise SystemExit(1)


def pid1_env(name):
    with open("/proc/1/environ", "rb") as fh:
        for part in fh.read().split(b"\0"):
            if part.startswith(name.encode() + b"="):
                return part.split(b"=", 1)[1].decode()
    return ""


def admin_session():
    secret = os.environ.get("WEBUI_SECRET_KEY") or pid1_env("WEBUI_SECRET_KEY")
    if not secret:
        fail("WEBUI_SECRET_KEY não encontrado")
    conn = sqlite3.connect(WEBUI_DB)
    row = conn.execute(
        "SELECT u.id, a.session_stamp FROM user u JOIN auth a ON a.id=u.id "
        "WHERE u.role='admin' ORDER BY u.created_at LIMIT 1"
    ).fetchone()
    conn.close()
    if not row:
        fail("nenhum administrador no Open WebUI")
    return jwt.encode(
        {
            "id": row[0], "typ": "session", "auth_method": "password",
            "auth_time": int(time.time()), "session_stamp": row[1],
            "mfa_verified": False,
            "exp": datetime.now(timezone.utc) + timedelta(minutes=10),
        },
        secret,
        algorithm="HS256",
    )


def request(method, path, headers, **kwargs):
    response = requests.request(method, BASE + path, headers=headers, timeout=120, **kwargs)
    if not response.ok:
        fail(f"{method} {path}: HTTP {response.status_code}: {response.text[:500]}")
    return response.json() if response.content else None


def optional_get(path, headers):
    response = requests.get(BASE + path, headers=headers, timeout=60)
    if response.status_code in (401, 404):
        return None
    if not response.ok:
        fail(f"GET {path}: HTTP {response.status_code}: {response.text[:500]}")
    return response.json()


def install(source_path):
    if not os.path.isfile(source_path):
        fail("fonte do Pipe ausente: " + source_path)
    if not os.path.isfile("/data/questoes.db"):
        fail("/data/questoes.db ausente: aplique o bind-mount :ro do compose")
    with open(source_path, encoding="utf-8") as fh:
        content = fh.read()

    headers = {"Authorization": "Bearer " + admin_session(), "Content-Type": "application/json"}
    function_form = {
        "id": FUNCTION_ID,
        "name": MODEL_NAME,
        "content": content,
        "meta": {"description": "Tutor pedagógico local com consulta exata ao banco de questões."},
        "commit_message": "sincronização pelo repositório",
    }
    current = optional_get(f"/api/v1/functions/id/{FUNCTION_ID}", headers)
    if current:
        request("POST", f"/api/v1/functions/id/{FUNCTION_ID}/update", headers, json=function_form)
    else:
        request("POST", "/api/v1/functions/create", headers, json=function_form)
    current = optional_get(f"/api/v1/functions/id/{FUNCTION_ID}", headers)
    if not current.get("is_active"):
        current = request("POST", f"/api/v1/functions/id/{FUNCTION_ID}/toggle", headers)
    if current.get("is_global"):
        fail("o Tutor não pode ser Function global")

    knowledges = request("GET", "/api/v1/knowledge/", headers)
    items = knowledges.get("items", []) if isinstance(knowledges, dict) else knowledges
    kb = next((k for k in items if k.get("name") == KB_NAME), None)
    if not kb:
        fail(f'base "{KB_NAME}" não encontrada')
    request("POST", f"/api/v1/knowledge/{kb['id']}/access/update", headers,
            json={"access_grants": PUBLIC_READ})

    model_form = {
        "id": FUNCTION_ID,
        "base_model_id": None,
        "name": MODEL_NAME,
        "is_active": True,
        "params": {
            "temperature": 0.2,
            "function_calling": "legacy",
        },
        "meta": {
            "description": "Questões do Colégio Tiradentes com localização exata e explicação para o 9º ano.",
            "knowledge": [{"id": kb["id"], "name": KB_NAME, "type": "collection"}],
            "capabilities": {
                # Permite que a UI entregue a imagem ao Pipe, que responde com
                # SEM_VISAO antes de chamar o modelo textual (nunca chega a mmproj).
                "vision": True, "file_upload": False, "web_search": False,
                "image_generation": False, "code_interpreter": False,
            },
        },
        "access_grants": PUBLIC_READ,
        "commit_message": "sincronização pelo repositório",
    }
    model = optional_get(f"/api/v1/models/model?id={FUNCTION_ID}", headers)
    if model:
        request("POST", "/api/v1/models/model/update", headers, json=model_form)
    else:
        request("POST", "/api/v1/models/create", headers, json=model_form)
    model = optional_get(f"/api/v1/models/model?id={FUNCTION_ID}", headers)
    if not model or model.get("name") != MODEL_NAME:
        fail("modelo não ficou registrado com o nome esperado")
    print(json.dumps({
        "ok": True, "function": FUNCTION_ID, "name": model["name"],
        "knowledge": KB_NAME, "db_read_only": True,
    }, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default="/tmp/tutor_tiradentes.py")
    args = parser.parse_args()
    install(args.source)


if __name__ == "__main__":
    main()
