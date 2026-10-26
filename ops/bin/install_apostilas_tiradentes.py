#!/usr/bin/env python3
"""Instala/atualiza a base, o Pipe e o modelo Apostilas Tiradentes no OWUI.

Roda dentro do container open-webui. A base exclusiva referencia os mesmos
arquivos já processados da base Tiradentes BM; não duplica PDFs no volume.
"""

import argparse
import hashlib
import json
import os
import re
import sqlite3
import sys
import time
from datetime import datetime, timedelta, timezone

import jwt
import requests


BASE = "http://127.0.0.1:8080"
WEBUI_DB = "/app/backend/data/webui.db"
FUNCTION_ID = "apostilas_tiradentes"
MODEL_NAME = "Apostilas Tiradentes"
SOURCE_KB = "Tiradentes BM"
KB_NAME = "Apostilas Tiradentes"
APOSTILAS_DIR = "/documents/concurso/tiradentes-bm/apostilas"
SUFIXOS = {".pdf", ".txt", ".md", ".docx"}
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
        "SELECT u.id,a.session_stamp FROM user u JOIN auth a ON a.id=u.id "
        "WHERE u.role='admin' ORDER BY u.created_at LIMIT 1"
    ).fetchone()
    conn.close()
    if not row:
        fail("nenhum administrador no Open WebUI")
    return jwt.encode({
        "id": row[0], "typ": "session", "auth_method": "password",
        "auth_time": int(time.time()), "session_stamp": row[1], "mfa_verified": False,
        "exp": datetime.now(timezone.utc) + timedelta(minutes=30),
    }, secret, algorithm="HS256")


def request(method, path, headers, timeout=120, **kwargs):
    response = requests.request(method, BASE + path, headers=headers, timeout=timeout, **kwargs)
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


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for bloco in iter(lambda: fh.read(1 << 20), b""):
            h.update(bloco)
    return h.hexdigest()


def nome_owui(rel):
    """Reproduz o nome achatado que rag_ingest envia ao Open WebUI."""
    partes = rel.replace("\\", "/").split("/")
    nome = partes[-1]
    stem = os.path.splitext(nome)[0].lower()
    ext = os.path.splitext(nome)[1].lower()
    ano = ""
    for parte in partes[:-1]:
        if re.fullmatch(r"\d{4}", parte):
            ano = parte
            break
    if not ano:
        match = re.search(r"(?<!\d)(\d{4})(?!\d)", stem)
        ano = match.group(1) if match else ""
    tokens = [token for token in stem.split("-") if token and token != ano]
    resto = "-".join(tokens)[:60]
    pedacos = ["tiradentes-bm"]
    if ano:
        pedacos.append(ano)
    if resto:
        pedacos.append(resto)
    return "-".join(pedacos) + ext


def arquivos_da_pasta():
    if not os.path.isdir(APOSTILAS_DIR):
        fail(f"pasta de apostilas ausente: {APOSTILAS_DIR}")
    arquivos = {}
    for raiz, dirs, nomes in os.walk(APOSTILAS_DIR):
        dirs[:] = sorted(d for d in dirs if not d.startswith(("_", ".")))
        for nome in sorted(nomes):
            if nome.startswith(("_", ".")) or os.path.splitext(nome)[1].lower() not in SUFIXOS:
                continue
            path = os.path.join(raiz, nome)
            rel = os.path.relpath(path, APOSTILAS_DIR).replace(os.sep, "/")
            arquivos[rel] = {"sha256": sha256(path), "filename": nome_owui(rel)}
    if not arquivos:
        fail("nenhum arquivo encontrado na pasta de apostilas")
    return arquivos


def get_or_create_kb(headers):
    knowledges = request("GET", "/api/v1/knowledge/", headers)
    items = knowledges.get("items", []) if isinstance(knowledges, dict) else knowledges
    kb = next((item for item in items if item.get("name") == KB_NAME), None)
    if kb:
        return kb, False
    kb = request("POST", "/api/v1/knowledge/create", headers, json={
        "name": KB_NAME,
        "description": "Conteúdo didático e exercícios das apostilas do Colégio Tiradentes.",
    })
    return kb, True


def arquivos_processados_da_base():
    hashes = arquivos_da_pasta()
    conn = sqlite3.connect(WEBUI_DB)
    conn.row_factory = sqlite3.Row
    source = conn.execute("SELECT id FROM knowledge WHERE name=?", (SOURCE_KB,)).fetchone()
    if not source:
        conn.close()
        fail(f'base de origem "{SOURCE_KB}" não encontrada')
    rows = conn.execute(
        "SELECT f.id,f.filename,f.hash FROM file f "
        "JOIN knowledge_file kf ON kf.file_id=f.id WHERE kf.knowledge_id=?",
        (source["id"],),
    ).fetchall()
    conn.close()
    por_hash = {row["hash"]: dict(row) for row in rows if row["hash"]}
    por_nome = {row["filename"]: dict(row) for row in rows if row["filename"]}
    encontrados = []
    faltantes = []
    for rel, identidade in sorted(hashes.items()):
        # Em PDFs, file.hash do OWUI 0.12.3 pode não ser o SHA-256 físico que o
        # manifest usa. O nome achatado é a outra identidade determinística do worker.
        row = por_hash.get(identidade["sha256"]) or por_nome.get(identidade["filename"])
        if row:
            row["origem"] = rel
            encontrados.append(row)
        else:
            faltantes.append(rel)
    return encontrados, faltantes


def vincular_arquivos(kb_id, headers):
    arquivos, faltantes = arquivos_processados_da_base()
    if not arquivos:
        fail("nenhuma apostila já processada foi encontrada na base Tiradentes BM")
    conn = sqlite3.connect(WEBUI_DB)
    existentes = {
        row[0] for row in conn.execute(
            "SELECT file_id FROM knowledge_file WHERE knowledge_id=?", (kb_id,)
        )
    }
    conn.close()
    adicionados = 0
    for arquivo in arquivos:
        if arquivo["id"] in existentes:
            continue
        request("POST", f"/api/v1/knowledge/{kb_id}/file/add", headers, timeout=3600,
                json={"file_id": arquivo["id"]})
        adicionados += 1
        print(f'== vinculado: {arquivo["origem"]}', file=sys.stderr)
    for rel in faltantes:
        print(f"== aviso: ainda não ingerido na base principal: {rel}", file=sys.stderr)
    if faltantes:
        fail(f"{len(faltantes)} arquivo(s) da pasta ainda não estão na base Tiradentes BM")
    return len(arquivos), adicionados, faltantes


def install(source_path):
    if not os.path.isfile(source_path):
        fail("fonte do Pipe ausente: " + source_path)
    with open(source_path, encoding="utf-8") as fh:
        content = fh.read()
    headers = {"Authorization": "Bearer " + admin_session(), "Content-Type": "application/json"}

    kb, created = get_or_create_kb(headers)
    total, adicionados, faltantes = vincular_arquivos(kb["id"], headers)
    request("POST", f"/api/v1/knowledge/{kb['id']}/access/update", headers,
            json={"access_grants": PUBLIC_READ})

    function_form = {
        "id": FUNCTION_ID,
        "name": MODEL_NAME,
        "content": content,
        "meta": {"description": (
            "Assistente pedagógico das apostilas Tiradentes com pesquisa externa via SearXNG "
            "somente sob pedido explícito e na ausência de fonte local."
        )},
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
        fail("Apostilas Tiradentes não pode ser Function global")

    model_form = {
        "id": FUNCTION_ID,
        "base_model_id": None,
        "name": MODEL_NAME,
        "is_active": True,
        "params": {"temperature": 0.2, "function_calling": "legacy"},
        "meta": {
            "description": (
                "Explicações, exercícios, dicas e correções pelas apostilas; fallback web explícito "
                "via SearXNG somente quando faltar fonte local."
            ),
            "knowledge": [{"id": kb["id"], "name": KB_NAME, "type": "collection"}],
            "capabilities": {
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
        "knowledge": KB_NAME, "knowledge_created": created,
        "files": total, "files_added": adicionados, "files_pending": faltantes,
    }, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default="/tmp/apostilas_tiradentes.py")
    args = parser.parse_args()
    install(args.source)


if __name__ == "__main__":
    main()
