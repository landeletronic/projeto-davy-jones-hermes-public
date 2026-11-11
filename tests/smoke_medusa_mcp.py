#!/usr/bin/env python3
"""MCP real a partir do container Hermes; não imprime credenciais nem dados sensíveis."""

import asyncio
import json

import httpx2
from hermes_cli.config import load_config
from mcp import ClientSession
from mcp.client.streamable_http import streamable_http_client


async def main():
    config = load_config()
    assert config["tools"]["tool_search"]["enabled"] in ("off", False)
    remote = config["mcp_servers"]["medusa-status"]
    assert remote["url"] == "http://100.126.89.55:18766/mcp"
    assert remote["headers"]["Authorization"].startswith("Bearer ")
    assert "${" not in remote["headers"]["Authorization"]
    async with httpx2.AsyncClient(headers=remote["headers"], timeout=20, trust_env=False) as client:
        async with streamable_http_client(remote["url"], http_client=client) as streams:
            async with ClientSession(streams[0], streams[1]) as session:
                await session.initialize()
                names = {tool.name for tool in (await session.list_tools()).tools}
                expected = {"worker_status", "gpu_status", "ollama_status", "list_models", "render_capabilities"}
                assert names == expected
                for name in ("worker_status", "gpu_status", "ollama_status"):
                    result = await session.call_tool(name, {})
                    assert not getattr(result, "is_error", getattr(result, "isError", False)), name
                    data = getattr(result, "structured_content", None) or getattr(result, "structuredContent", None)
                    if not data:
                        data = json.loads(result.content[0].text)
                    assert data.get("mcp") == "online" if name == "worker_status" else data.get("ok") is True
                    print("PASS MCP Medusa:", name)


if __name__ == "__main__":
    asyncio.run(main())
