"""Sobe UM documento para uma base do OWUI — roda DENTRO do container open-webui.

Quem chama: `tools/rag_ingest.py` (no host), que copia este arquivo para /tmp e roda
  docker exec open-webui python /tmp/owui_upload.py \\
      --path /documents/concurso/tiradentes-bm/2026/prova_gabarito/prova-2026.pdf \\
      --name tiradentes-bm-2026-prova.pdf --kb "Tiradentes BM"

Por que dentro do container: a autenticação é uma **sessão JWT** (typ=session) assinada
com a `WEBUI_SECRET_KEY` do processo 1 — o mesmo mecanismo do tests/smoke_rag.py. OWUI
0.12+ não aceita API key como sessão humana, e o segredo não sai do container.

Contrato de saída: o resto vai para o stderr; no stdout sai **uma** linha
`RESULT {json}` — é dela que o worker no host lê file_id/knowledge_id/pontos.
Exit != 0 = falhou (o worker copia o arquivo para _rejeitados/ com o motivo).

Faxina: `--remove-file <file_id>` apaga o arquivo (e os vetores) e a linha órfã de
`knowledge_file` — é o que `rag-ingest --remover <sha256>` usa. OWUI 0.12.3 não apaga
essa linha sozinho (bug conhecido do projeto).
"""

import argparse
import json
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
COL = 'owui_knowledge'

MIME = {
    '.pdf': 'application/pdf',
    '.txt': 'text/plain',
    '.md': 'text/markdown',
    '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    '.pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
}

H = {}


def db():
    return sqlite3.connect(DB)


def fail(msg):
    print(f'ERRO: {msg}', file=sys.stderr)
    raise SystemExit(1)


def _pid1_env(name):
    """Lê uma variável do processo principal (uvicorn = PID 1)."""
    try:
        with open('/proc/1/environ', 'rb') as fh:
            for part in fh.read().split(b'\0'):
                if part.startswith(name.encode() + b'='):
                    return part.split(b'=', 1)[1].decode()
    except OSError:
        pass
    return ''


def session_token(admin_email):
    secret = os.environ.get('WEBUI_SECRET_KEY') or _pid1_env('WEBUI_SECRET_KEY')
    if not secret:
        fail('WEBUI_SECRET_KEY não encontrado (env nem /proc/1/environ)')
    c = db()
    row = c.execute('select id from user where email=?', (admin_email,)).fetchone()
    if not row:
        c.close()
        fail(f'usuário {admin_email} não existe no webui.db')
    uid = row[0]
    stamp = c.execute('select session_stamp from auth where id=?', (uid,)).fetchone()[0]
    c.close()
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


def get_or_create_kb(name):
    r = requests.get(f'{BASE}/api/v1/knowledge/', headers=H, timeout=60)
    r.raise_for_status()
    items = r.json()
    if isinstance(items, dict):
        items = items.get('items', [])
    for k in items:
        if k.get('name') == name:
            return k['id'], False
    r = requests.post(
        f'{BASE}/api/v1/knowledge/create',
        headers=H,
        json={
            'name': name,
            'description': f'Base de estudo do concurso {name} - editais, provas e gabaritos',
        },
        timeout=60,
    )
    r.raise_for_status()
    return r.json()['id'], True


def points_for(kid):
    r = requests.post(
        f'{QDRANT}/collections/{COL}/points/count',
        json={'exact': True, 'filter': {'must': [{'key': 'tenant_id', 'match': {'value': kid}}]}},
        timeout=30,
    )
    r.raise_for_status()
    return r.json()['result']['count']


def chars_extracted(fid):
    """Tamanho do texto extraído (Docling) — o worker avisa quando é baixo demais."""
    try:
        c = db()
        row = c.execute('select data from file where id=?', (fid,)).fetchone()
        c.close()
    except sqlite3.Error:
        return 0
    if not row or not row[0]:
        return 0
    try:
        data = json.loads(row[0])
    except (TypeError, ValueError):
        return 0
    return len(data.get('content') or '')


def wait_processed(fid, timeout):
    t0 = time.time()
    status = None
    data = {}
    while time.time() - t0 < timeout:
        meta = requests.get(f'{BASE}/api/v1/files/{fid}', headers=H, timeout=120).json()
        data = meta.get('data') or {}
        status = data.get('status')
        if status in ('completed', 'failed'):
            return status, data, round(time.time() - t0, 1)
        time.sleep(3)
    return status, data, round(time.time() - t0, 1)


def add_file_to_kb(kb_name, fid):
    """Garante o vínculo/vetores do mesmo arquivo em uma knowledge base."""
    kid, created = get_or_create_kb(kb_name)
    c = db()
    present = c.execute(
        'select count(*) from knowledge_file where knowledge_id=? and file_id=?', (kid, fid)
    ).fetchone()[0]
    c.close()
    elapsed = 0.0
    if not present:
        t0 = time.time()
        r = requests.post(
            f'{BASE}/api/v1/knowledge/{kid}/file/add',
            headers=H,
            json={'file_id': fid},
            timeout=3600,
        )
        elapsed = round(time.time() - t0, 1)
        if not r.ok:
            fail(f'file/add na base "{kb_name}" HTTP {r.status_code}: {r.text[:600]}')
        print(f'== file/add em "{kb_name}": ok em {elapsed}s', file=sys.stderr)
    c = db()
    linked = c.execute(
        'select count(*) from knowledge_file where knowledge_id=? and file_id=?', (kid, fid)
    ).fetchone()[0]
    c.close()
    if not linked:
        fail(f'arquivo processado mas não vinculado à base "{kb_name}"')
    return {'id': kid, 'name': kb_name, 'created': created, 'add_s': elapsed}


def descartar(fid):
    """Remove um arquivo que NÃO entrou na base (upload sem uso = resto no banco).

    Um PDF corrompido sobe (o POST aceita) e só falha no Docling: sem isso a linha
    fica órfã em `file` para sempre e o `_rejeitados/` não é a única marca da falha.
    """
    try:
        r = requests.delete(f'{BASE}/api/v1/files/{fid}', headers=H, timeout=300)
        print(f'== descarte do arquivo {fid}: {r.status_code}', file=sys.stderr)
    except requests.RequestException as exc:  # noqa: BLE001
        print(f'== aviso: não consegui descartar {fid}: {exc}', file=sys.stderr)
    try:
        c = db()
        c.execute('delete from knowledge_file where file_id=?', (fid,))
        c.commit()
        c.close()
    except sqlite3.Error as exc:
        print(f'== aviso: vínculo de {fid} não limpo: {exc}', file=sys.stderr)


def ingest(args):
    path = args.path
    if not os.path.isfile(path):
        fail(f'arquivo não existe dentro do container: {path}')
    size = os.path.getsize(path)
    if size == 0:
        fail('arquivo vazio (0 bytes)')

    mime = MIME.get(os.path.splitext(path)[1].lower(), 'application/octet-stream')
    t0 = time.time()
    with open(path, 'rb') as fh:
        r = requests.post(
            f'{BASE}/api/v1/files/?process=true&process_in_background=false',
            headers=H,
            files={'file': (args.name, fh, mime)},
            timeout=3600,
        )
    upload_s = round(time.time() - t0, 1)
    if not r.ok:
        fail(f'upload HTTP {r.status_code}: {r.text[:600]}')
    body = r.json()
    fid = body['id']
    print(f'== upload de "{args.name}" ({size} bytes): ok em {upload_s}s', file=sys.stderr)

    status, data, wait_s = wait_processed(fid, args.timeout)
    print(f'== processamento (Docling): {status} em {wait_s}s', file=sys.stderr)
    if status != 'completed':
        detail = data.get('error') or data.get('status') or 'sem detalhe'
        descartar(fid)
        fail(f'processamento não concluiu ({status}): {detail}')

    try:
        primary = add_file_to_kb(args.kb, fid)
        extras = [add_file_to_kb(name, fid) for name in dict.fromkeys(args.kb_extra)
                  if name and name != args.kb]
    except SystemExit:
        descartar(fid)
        raise

    points = points_for(primary['id'])
    chars = chars_extracted(fid)
    out = {
        'ok': True,
        'name': args.name,
        'file_id': fid,
        'knowledge_id': primary['id'],
        'kb_created': primary['created'],
        'kb': args.kb,
        'extra_knowledge': extras,
        'status': status,
        'bytes': size,
        'chars': chars,
        'points': points,
        'upload_s': upload_s,
        'process_s': wait_s,
        'file_add_s': primary['add_s'],
    }
    print('RESULT ' + json.dumps(out, ensure_ascii=False))


def remove_file(args):
    """Apaga um arquivo do OWUI (e os vetores) + a linha órfã de knowledge_file."""
    fid = args.remove_file
    c = db()
    row = c.execute('select filename from file where id=?', (fid,)).fetchone()
    kfs = c.execute('select knowledge_id from knowledge_file where file_id=?', (fid,)).fetchall()
    c.close()
    if not row:
        print(f'== aviso: file_id {fid} não existe mais no banco', file=sys.stderr)
    name = row[0] if row else None

    # remove da base pela API (chunk/vector delete) quando o vínculo é conhecido
    for (kid,) in kfs:
        try:
            r = requests.post(
                f'{BASE}/api/v1/knowledge/{kid}/file/remove',
                headers=H,
                json={'file_id': fid},
                timeout=600,
            )
            print(f'== knowledge/{kid}/file/remove: {r.status_code}', file=sys.stderr)
        except requests.RequestException as exc:  # noqa: BLE001
            print(f'== aviso: file/remove falhou ({exc}) — sigo para o DELETE', file=sys.stderr)

    r = requests.delete(f'{BASE}/api/v1/files/{fid}', headers=H, timeout=600)
    print(f'== DELETE /files/{fid}: {r.status_code} {r.text[:200]}', file=sys.stderr)

    # a linha de ligação fica órfã na 0.12.3 (bug do projeto): limpa à mão
    c = db()
    c.execute('delete from knowledge_file where file_id=?', (fid,))
    c.commit()
    left = c.execute('select count(*) from knowledge_file where file_id=?', (fid,)).fetchone()[0]
    still = c.execute('select count(*) from file where id=?', (fid,)).fetchone()[0]
    c.close()
    if left or still:
        fail(f'remoção incompleta: {left} vínculo(s) e {still} arquivo(s) restantes')

    print('RESULT ' + json.dumps({'ok': True, 'removed': True, 'file_id': fid, 'name': name}))


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--path', help='caminho do arquivo DENTRO do container (/documents/...)')
    p.add_argument('--name', help='nome que aparece na citação (nome achatado)')
    p.add_argument('--kb', default='Tiradentes BM', help='nome da base no OWUI')
    p.add_argument('--kb-extra', action='append', default=[],
                   help='base adicional que recebe o mesmo arquivo (repetível)')
    p.add_argument('--admin-email', default='admin@example.com')
    p.add_argument('--timeout', type=int, default=1800, help='espera do Docling (s)')
    p.add_argument('--remove-file', metavar='FILE_ID', help='apaga o arquivo e o vínculo')
    args = p.parse_args()

    H.update({'Authorization': f'Bearer {session_token(args.admin_email)}'})
    me = requests.get(f'{BASE}/api/v1/auths/', headers=H, timeout=60)
    if not me.ok:
        fail(f'auth HTTP {me.status_code}: sessão JWT recusada')
    print(f'== auth: {me.json().get("email")}', file=sys.stderr)

    if args.remove_file:
        remove_file(args)
    elif args.path and args.name:
        ingest(args)
    else:
        fail('informe --path e --name (ou --remove-file FILE_ID)')


if __name__ == '__main__':
    main()
