"""Remove uma knowledge base de TESTE do Open WebUI (e tudo que ela deixou).

Por que existe: a base "Teste raciocinio" foi criada para provar o RAG e ficou no
banco. Apagar pela UI é frágil (e a UI não cascateia `knowledge_file` — bug real
do 0.12.3); este script faz o mesmo caminho da API do smoke e ainda limpa o
resíduo no SQLite e os vetores no Qdrant.

Roda DENTRO do container open-webui (tem acesso ao banco e à rede do Qdrant):

  docker cp tools/cleanup_owui_test_kb.py open-webui:/tmp/cleanup.py
  docker exec open-webui python /tmp/cleanup.py --dry-run        # só mostra
  docker exec open-webui python /tmp/cleanup.py                  # apaga

Autenticação: JWT HS256 com WEBUI_SECRET_KEY (typ=session), igual ao smoke_rag.py
— API key não vale como sessão desde o 0.12.3.
"""

import argparse
import os
import sqlite3
import sys
import time
from datetime import datetime, timedelta, timezone

import jwt
import requests

DB = '/app/backend/data/webui.db'
BASE = 'http://127.0.0.1:8080'
QDRANT = 'http://qdrant:6333'
ADMIN_EMAIL = 'admin@example.com'
DEFAULT_NAME = 'Teste raciocinio'


def db():
    return sqlite3.connect(DB)


def _pid1_env(name):
    try:
        with open('/proc/1/environ', 'rb') as fh:
            for part in fh.read().split(b'\0'):
                if part.startswith(name.encode() + b'='):
                    return part.split(b'=', 1)[1].decode()
    except OSError:
        pass
    return ''


def session_token(c):
    secret = os.environ.get('WEBUI_SECRET_KEY') or _pid1_env('WEBUI_SECRET_KEY')
    if not secret:
        sys.exit('WEBUI_SECRET_KEY não encontrado (env ou /proc/1/environ)')
    row = c.execute('select id from user where email=?', (ADMIN_EMAIL,)).fetchone()
    if not row:
        sys.exit(f'usuário admin {ADMIN_EMAIL} não existe')
    uid = row[0]
    stamp = c.execute('select session_stamp from auth where id=?', (uid,)).fetchone()[0]
    return jwt.encode(
        {
            'id': uid,
            'typ': 'session',
            'auth_method': 'password',
            'auth_time': int(time.time()),
            'session_stamp': stamp,
            'mfa_verified': False,
            'exp': datetime.now(timezone.utc) + timedelta(minutes=30),
        },
        secret,
        algorithm='HS256',
    )


def targets(c, name):
    """knowledge (id, name) e os files ligados a ele."""
    rows = c.execute('select id, name from knowledge where name=?', (name,)).fetchall()
    out = []
    for kid, kname in rows:
        files = [r[0] for r in c.execute(
            'select file_id from knowledge_file where knowledge_id=?', (kid,))]
        out.append((kid, kname, files))
    return out


def orphans(c):
    """Linhas de ligação apontando para knowledge/file que não existem mais."""
    return c.execute('''
        select count(*) from knowledge_file kf
        where not exists (select 1 from knowledge k where k.id = kf.knowledge_id)
           or not exists (select 1 from file f where f.id = kf.file_id)
    ''').fetchone()[0]


def qdrant_points(kid, file_ids):
    """Conta pontos ligados ao knowledge (tenant_id = kid) e aos files."""
    n = 0
    for body in ({'filter': {'must': [{'key': 'tenant_id', 'match': {'value': kid}}]}},):
        try:
            r = requests.post(f'{QDRANT}/collections/owui_knowledge/points/count',
                              json={**body, 'exact': True}, timeout=30)
            n += int(r.json().get('result', {}).get('count', 0))
        except Exception:  # noqa: BLE001
            pass
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--name', default=DEFAULT_NAME)
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    c = db()
    found = targets(c, args.name)
    if not found:
        print(f'[cleanup] nenhuma knowledge "{args.name}" — nada a fazer')
        return 0

    for kid, kname, files in found:
        pts = qdrant_points(kid, files)
        print(f'[cleanup] knowledge {kid} "{kname}" | {len(files)} arquivo(s) | {pts} ponto(s) no Qdrant')
        for f in files:
            print(f'[cleanup]   file {f}')
        if args.dry_run:
            continue

        H = {'Authorization': f'Bearer {session_token(c)}'}
        r = requests.delete(f'{BASE}/api/v1/knowledge/{kid}/delete', headers=H, timeout=60)
        print(f'[cleanup] delete knowledge: {r.status_code} {r.text[:100]}')
        for f in files:
            try:
                r = requests.delete(f'{BASE}/api/v1/files/{f}', headers=H, timeout=120)
                print(f'[cleanup] delete file {f}: {r.status_code}')
            except Exception as exc:  # noqa: BLE001
                print(f'[cleanup] delete file {f}: {exc}')

        # A UI/API não cascateia knowledge_file (bug do 0.12.3): limpa à mão.
        c.execute('delete from knowledge_file where knowledge_id=?', (kid,))
        for f in files:
            c.execute('delete from knowledge_file where file_id=?', (f,))
        c.commit()

        # Vetores: o OWUI normalmente remove ao apagar o file; se sobrar, apaga aqui.
        try:
            requests.post(
                f'{QDRANT}/collections/owui_knowledge/points/delete?wait=true',
                json={'filter': {'must': [{'key': 'tenant_id', 'match': {'value': kid}}]}},
                timeout=60)
        except Exception as exc:  # noqa: BLE001
            print(f'[cleanup] qdrant: {exc}')

    left = len(targets(c, args.name))
    orphan = orphans(c)
    c.close()
    print(f'[cleanup] restante: {left} knowledge(s) com esse nome | knowledge_file órfão: {orphan}')
    return 0 if left == 0 and orphan == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
