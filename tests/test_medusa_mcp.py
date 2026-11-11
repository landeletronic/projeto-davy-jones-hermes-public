#!/usr/bin/env python3
"""Regressão do MCP da Medusa usando FastMCP/Starlette em ambiente isolado."""

import importlib.util
import json
import tempfile
from pathlib import Path

from starlette.testclient import TestClient


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("medusa_mcp", ROOT / "tools" / "medusa_mcp.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def main():
    with tempfile.TemporaryDirectory() as directory:
        module.TOKEN_FILE = Path(directory) / "token"
        module.HERMES_TOKEN_FILE = Path(directory) / "hermes-token"
        token = "x" * 48
        hermes_token = "h" * 48
        module.TOKEN_FILE.write_text(token)
        module.HERMES_TOKEN_FILE.write_text(hermes_token)
        headers = {"Accept": "application/json, text/event-stream", "Authorization": "Bearer " + token}
        initialize = {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2025-11-25", "capabilities": {},
            "clientInfo": {"name": "regression", "version": "1"}}}
        outsider = TestClient(module.app, base_url="http://127.0.0.1:18766", client=("100.94.111.91", 12345))
        assert outsider.post("/mcp", json=initialize, headers=headers).status_code == 403
        assert outsider.post("/mcp", json=initialize, headers={**headers, "X-Forwarded-For": "100.112.146.19"}).status_code == 403
        outsider.close()
        with TestClient(module.app, base_url="http://127.0.0.1:18766", client=("100.112.146.19", 12345)) as client:
            assert client.post("/mcp", json=initialize).status_code == 401
            assert client.post("/mcp", json=initialize, headers={"Authorization": "Bearer wrong"}).status_code == 401
            module.TOKEN_FILE.unlink()
            assert client.post("/mcp", json=initialize, headers=headers).status_code == 401
            hermes_headers = {**headers, "Authorization": "Bearer " + hermes_token}
            assert client.post("/mcp", json=initialize, headers=hermes_headers).status_code == 200
            module.HERMES_TOKEN_FILE.unlink()
            assert client.post("/mcp", json=initialize, headers=hermes_headers).status_code == 401
            module.TOKEN_FILE.write_text(token)
            assert client.post("/mcp", json=initialize, headers=headers).status_code == 200
            response = client.post("/mcp", headers=headers, json={"jsonrpc": "2.0", "id": 2,
                                   "method": "tools/list", "params": {}})
            names = {item["name"] for item in response.json()["result"]["tools"]}
            assert names == {"worker_status", "gpu_status", "ollama_status", "list_models", "render_capabilities"}
            response = client.post("/mcp", headers=headers, json={"jsonrpc": "2.0", "id": 3,
                                   "method": "tools/call", "params": {"name": "worker_status", "arguments": {}}})
            assert "not_installed" in json.dumps(response.json())
    print("PASS medusa MCP: IP exclusivo, token obrigatório, initialize, tools/list e tools/call")


if __name__ == "__main__":
    main()
