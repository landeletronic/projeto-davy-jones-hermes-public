#!/usr/bin/env bash
set -u
for c in owui_knowledge owui_files; do
  curl -s "http://localhost:6333/collections/$c" -o "/tmp/$c.json"
  curl -s -X POST "http://localhost:6333/collections/$c/points/scroll" \
    -H 'Content-Type: application/json' \
    -d '{"limit": 5, "with_payload": true, "with_vector": false}' \
    -o "/tmp/${c}_points.json"
done
python3 - <<'PY'
import json

for name in ('owui_knowledge', 'owui_files'):
    d = json.load(open(f'/tmp/{name}.json'))['result']
    print(f"{name}: status={d['status']} points={d['points_count']} vectors={json.dumps(d['config']['params']['vectors'])}")
    pts = json.load(open(f'/tmp/{name}_points.json'))['result']['points']
    for p in pts[:3]:
        pl = p['payload']
        print('  id:', p['id'])
        print('  payload keys:', list(pl.keys()))
        print('  metadata:', json.dumps(pl.get('metadata'), ensure_ascii=False)[:300])
        print('  text:', (pl.get('page_content') or pl.get('text') or '')[:160].replace('\n', ' '))
PY
