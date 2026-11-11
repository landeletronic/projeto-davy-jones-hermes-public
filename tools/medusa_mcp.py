#!/usr/bin/env python3
"""MCP somente leitura: acesso HTTP exclusivo do Davy por Tailscale e token."""

import hmac
import json
import os
import shutil
import subprocess
import urllib.error
import urllib.request
from pathlib import Path

from mcp.server.fastmcp import FastMCP
from mcp.server.transport_security import TransportSecuritySettings


TOKEN_FILE = Path(os.environ.get("MEDUSA_MCP_TOKEN_FILE", str(Path.home() / ".config/medusa-mcp/token")))
HERMES_TOKEN_FILE = Path.home() / ".config/medusa-mcp/token-hermes"
DAVY_IP = "100.112.146.19"
server = FastMCP("medusa-status", stateless_http=True, json_response=True,
                 transport_security=TransportSecuritySettings(
                     allowed_hosts=["100.126.89.55:18766", "127.0.0.1:18766"],
                     allowed_origins=[]))


def query_ollama(path):
    try:
        with urllib.request.urlopen("http://127.0.0.1:11434" + path, timeout=5) as response:
            return json.load(response)
    except (OSError, ValueError, urllib.error.URLError):
        return None


@server.tool()
def worker_status() -> dict:
    """Estado do MCP: serviço de renderização ainda não implementado."""
    return {"mcp": "online", "render_worker": "not_installed"}


@server.tool()
def gpu_status() -> dict:
    """Consulta nome, memória e driver NVIDIA sem executar inferência."""
    try:
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=name,memory.total,memory.used,driver_version",
             "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=5, check=True,
        )
        return {"ok": True, "gpus": [line.strip() for line in result.stdout.splitlines()]}
    except (OSError, subprocess.SubprocessError):
        return {"ok": False, "gpus": []}


@server.tool()
def ollama_status() -> dict:
    """Consulta a versão do Ollama local, sem gerar respostas."""
    result = query_ollama("/api/version")
    return {"ok": result is not None, "version": result.get("version") if result else None}


@server.tool()
def list_models() -> dict:
    """Lista apenas os nomes de modelos instalados no Ollama local."""
    result = query_ollama("/api/tags")
    return {"ok": result is not None, "models": [x.get("name") for x in result.get("models", [])] if result else []}


@server.tool()
def render_capabilities() -> dict:
    """Mostra programas disponíveis; não presume que o pipeline esteja instalado."""
    return {"ffmpeg": bool(shutil.which("ffmpeg")), "nvidia_smi": bool(shutil.which("nvidia-smi")),
            "podcast_pipeline": "not_installed"}


class BearerAuth:
    """Protege todas as rotas HTTP; falha fechado se o token estiver indisponível."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        client = scope.get("client")
        if not client or client[0] != DAVY_IP:
            await send({"type": "http.response.start", "status": 403, "headers": [(b"content-type", b"application/json")]})
            await send({"type": "http.response.body", "body": b'{"error":"forbidden"}'})
            return
        headers = scope.get("headers", [])
        values = [value for name, value in headers if name.lower() == b"authorization"]
        valid = False
        for token_file in (TOKEN_FILE, HERMES_TOKEN_FILE):
            try:
                token = token_file.read_bytes().strip()
                valid |= len(token) >= 32 and len(values) == 1 and hmac.compare_digest(values[0], b"Bearer " + token)
            except OSError:
                pass
        if not valid:
            await send({"type": "http.response.start", "status": 401, "headers": [(b"content-type", b"application/json")]})
            await send({"type": "http.response.body", "body": b'{"error":"unauthorized"}'})
            return
        await self.app(scope, receive, send)


app = BearerAuth(server.streamable_http_app())
