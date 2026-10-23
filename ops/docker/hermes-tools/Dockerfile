# Estende a imagem oficial do Hermes com ferramentas operacionais
# (persistente entre recreates de container)
FROM nousresearch/hermes-agent:latest
RUN apt-get update && apt-get install -y --no-install-recommends \
      openssh-client git jq curl wget ripgrep rsync zip unzip \
      procps iputils-ping dnsutils ffmpeg ca-certificates python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Mem0 memory provider — modo OSS (in-process): SDK + deps de vector store/LLM
# (substitui honcho-ai, removido do stack em 2026-10-09)
# A imagem base usa venv em /opt/hermes/.venv sem pip — ensurepip antes de instalar
RUN /opt/hermes/.venv/bin/python3 -m ensurepip --upgrade \
 && /opt/hermes/.venv/bin/python3 -m pip install --no-cache-dir mem0ai qdrant-client ollama
