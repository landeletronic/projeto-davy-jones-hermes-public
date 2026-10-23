#!/usr/bin/env bash
set -u
for i in ghcr.io/open-webui/open-webui:main ollama/ollama:rocm qdrant/qdrant:v1.15.2 ghcr.io/docling-project/docling-serve-cpu:v1.37.0; do
  printf '%s -> ' "$i"
  docker image inspect "$i" --format '{{index .RepoDigests 0}}'
done
