#!/usr/bin/env bash
set -u
for i in prom/prometheus:v3.15.0 prom/node-exporter:v1.12.1 grafana/grafana:13.2.4 gcr.io/cadvisor/cadvisor:v0.55.1; do
  if docker pull "$i" >/dev/null 2>&1; then
    printf '%s -> ' "$i"
    docker image inspect "$i" --format '{{index .RepoDigests 0}}'
  else
    echo "$i -> PULL-FAIL"
  fi
done
