#!/usr/bin/env python3
"""mem0-maintenance — higiene da memória de longo prazo (mem0 / Qdrant).

Por que existe: o mem0 é ADD-only. O LLM de extração decide ADD/UPDATE/NOOP, mas
na prática a coleção só cresce (10 → 24 pontos em um dia de testes) e fatos
repetidos/velhos ficam para sempre. Este job roda diariamente, antes do backup:

  1. DEDUP exato   — mesmo (user_id, hash), mantém o mais recente.
  2. DEDUP near    — cosseno >= MEM0_DEDUP_SIM (0.97) no mesmo usuário, mantém o
                     mais recente (texto maior em empate).
  3. TETO          — acima de MEM0_MAX_PER_USER, remove os mais antigos
                     (updated_at) do usuário.
  4. TTL (opcional) — MEM0_RETENTION_DAYS > 0 remove o que não é tocado há N dias.
                     Default 0 = desligado: apagar memória é decisão do escritório
                     (LGPD/sigilo), não default de fábrica.

Fala direto com o Qdrant (REST, stdlib) — não depende do venv do Hermes nem do
plugin, então continua funcionando se o plugin for atualizado.

Métricas para o node-exporter (textfile): hermes_mem0_*.
Uso: mem0-maintenance [--dry-run]
"""

import calendar
import json
import os
import sys
import time
import urllib.error
import urllib.request

QDRANT = os.environ.get('QDRANT_URL', 'http://127.0.0.1:6333').rstrip('/')
COLL = os.environ.get('MEM0_COLLECTION', 'mem0_memories')
DEDUP_SIM = float(os.environ.get('MEM0_DEDUP_SIM', '0.97'))
MAX_PER_USER = int(os.environ.get('MEM0_MAX_PER_USER', '2000'))
RETENTION_DAYS = int(os.environ.get('MEM0_RETENTION_DAYS', '0'))
TEXTFILE = os.environ.get('MEM0_TEXTFILE', '/home/usuario/hermes-architect/ci/textfile')
DRY = '--dry-run' in sys.argv


def _req(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        f'{QDRANT}{path}', data=data, method=method,
        headers={'Content-Type': 'application/json'},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        raw = resp.read()
    return json.loads(raw) if raw else {}


def scroll_all():
    """Todos os pontos com payload e vetor (paginado)."""
    points, offset = [], None
    while True:
        body = {'limit': 256, 'with_payload': True, 'with_vector': True}
        if offset is not None:
            body['offset'] = offset
        result = _req('POST', f'/collections/{COLL}/points/scroll', body)['result']
        points.extend(result.get('points') or [])
        offset = result.get('next_page_offset')
        if not offset:
            return points


def cosine(a, b):
    if not a or not b or len(a) != len(b):
        return 0.0
    dot = sum(x * y for x, y in zip(a, b))
    na = sum(x * x for x in a) ** 0.5
    nb = sum(y * y for y in b) ** 0.5
    return dot / (na * nb) if na and nb else 0.0


def when(point):
    payload = point.get('payload') or {}
    return str(payload.get('updated_at') or payload.get('created_at') or '')


def group_by_user(points):
    users = {}
    for p in points:
        user = str((p.get('payload') or {}).get('user_id') or '')
        users.setdefault(user, []).append(p)
    return users


def main():
    points = scroll_all()
    users = group_by_user(points)
    delete = {}  # id -> reason

    # 1) dedup exato por (user_id, hash)
    for user, pts in users.items():
        seen = {}
        for p in sorted(pts, key=when):
            h = (p.get('payload') or {}).get('hash')
            if not h:
                continue
            if h in seen:
                delete[p['id']] = 'duplicate'
            else:
                seen[h] = p['id']

    # 2) dedup near-duplicate por cosseno, dentro do mesmo usuário
    for user, pts in users.items():
        alive = [p for p in pts if p['id'] not in delete]
        alive.sort(key=when)  # do mais antigo ao mais novo
        for i, older in enumerate(alive):
            if older['id'] in delete:
                continue
            for newer in alive[i + 1:]:
                if newer['id'] in delete:
                    continue
                if cosine(older.get('vector'), newer.get('vector')) >= DEDUP_SIM:
                    delete[older['id']] = 'duplicate'
                    break

    # 3) teto por usuário (remove os mais antigos)
    for user, pts in users.items():
        alive = [p for p in pts if p['id'] not in delete]
        excess = len(alive) - MAX_PER_USER
        if excess > 0:
            for p in sorted(alive, key=when)[:excess]:
                delete[p['id']] = 'cap'

    # 4) TTL opcional
    if RETENTION_DAYS > 0:
        cutoff = time.time() - RETENTION_DAYS * 86400
        for p in points:
            if p['id'] in delete:
                continue
            ts = (p.get('payload') or {}).get('updated_at') or (p.get('payload') or {}).get('created_at')
            if not ts:
                continue
            try:
                # updated_at é UTC; timegm evita o deslocamento do fuso local.
                epoch = calendar.timegm(time.strptime(str(ts)[:19], '%Y-%m-%dT%H:%M:%S'))
            except ValueError:
                continue
            if epoch < cutoff:
                delete[p['id']] = 'ttl'

    reasons = {'duplicate': 0, 'cap': 0, 'ttl': 0}
    for reason in delete.values():
        reasons[reason] = reasons.get(reason, 0) + 1

    ids = list(delete)
    if ids and not DRY:
        for i in range(0, len(ids), 256):
            _req('POST', f'/collections/{COLL}/points/delete?wait=true',
                 {'points': ids[i:i + 256]})

    # duplicatas remanescentes (após a limpeza) — invariante conferido pela suíte
    remaining, seen = 0, set()
    for p in points:
        if p['id'] in delete:
            continue
        payload = p.get('payload') or {}
        key = (payload.get('user_id'), payload.get('hash'))
        if payload.get('hash'):
            if key in seen:
                remaining += 1
            else:
                seen.add(key)

    total_after = len(points) - len(delete)
    print(
        f'mem0: {len(points)} pontos | removidos {len(ids)} '
        f'(dup={reasons.get("duplicate", 0)} cap={reasons.get("cap", 0)} ttl={reasons.get("ttl", 0)}) '
        f'| restam {total_after} | dup remanescentes={remaining}'
        + (' [DRY-RUN]' if DRY else '')
    )

    if not DRY and os.path.isdir(TEXTFILE):
        lines = [
            '# HELP hermes_mem0_points_total Pontos na coleção mem0_memories',
            '# TYPE hermes_mem0_points_total gauge',
            f'hermes_mem0_points_total {total_after}',
            '# HELP hermes_mem0_deleted_total Pontos removidos pela manutenção',
            '# TYPE hermes_mem0_deleted_total counter',
            f'hermes_mem0_deleted_total{{reason="duplicate"}} {reasons.get("duplicate", 0)}',
            f'hermes_mem0_deleted_total{{reason="cap"}} {reasons.get("cap", 0)}',
            f'hermes_mem0_deleted_total{{reason="ttl"}} {reasons.get("ttl", 0)}',
            '# HELP hermes_mem0_duplicates_remaining Duplicatas (user_id,hash) remanescentes',
            '# TYPE hermes_mem0_duplicates_remaining gauge',
            f'hermes_mem0_duplicates_remaining {remaining}',
            '# HELP hermes_mem0_last_run_timestamp_seconds Epoch da última manutenção',
            '# TYPE hermes_mem0_last_run_timestamp_seconds gauge',
            f'hermes_mem0_last_run_timestamp_seconds {int(time.time())}',
        ]
        tmp = os.path.join(TEXTFILE, 'hermes_mem0.prom.tmp')
        with open(tmp, 'w', encoding='utf-8') as fh:
            fh.write('\n'.join(lines) + '\n')
        os.replace(tmp, os.path.join(TEXTFILE, 'hermes_mem0.prom'))

    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except urllib.error.URLError as exc:
        print(f'mem0-maintenance: Qdrant inacessível ({exc})', file=sys.stderr)
        sys.exit(2)
