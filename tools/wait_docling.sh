#!/usr/bin/env bash
set -u
for i in $(seq 1 72); do
  h=$(docker inspect -f '{{.State.Health.Status}}' docling 2>/dev/null || echo missing)
  if [ "$h" = "healthy" ]; then
    echo "HEALTHY after $((i * 5))s"
    break
  fi
  if [ $((i % 6)) -eq 0 ]; then
    echo "waiting $((i * 5))s: $h"
  fi
  sleep 5
done
echo "--- last logs ---"
docker logs docling --tail 20 2>&1 | tail -20
