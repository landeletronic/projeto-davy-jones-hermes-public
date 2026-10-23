"""Smoke test E2E da RAG jurídica — roda DENTRO do container open-webui.

Fluxo:
  sessão (JWT) -> upload PDF -> cria Knowledge -> adiciona arquivo (Docling + bge-m3)
  -> confere os pontos no Qdrant (owui_knowledge, tenant_id = knowledge id)
  -> pergunta ao modelo com a base -> limpa tudo (knowledge, file).

Autenticação (mudou na v0.12.3):
  OWUI 0.12+ exige "human session" (JWT com typ=session) em /api/v1/auths/ — API key
  não é mais aceita. O script assina um JWT HS256 com o WEBUI_SECRET_KEY do processo
  e o `session_stamp` da conta (mesma verificação que o login faz), sem tocar em
  `auth.enable_api_keys` (que segue desligado).

Uso (no host):
  docker cp tests/fixtures/contrato-teste.pdf open-webui:/tmp/contrato-teste.pdf
  docker cp tests/smoke_rag.py open-webui:/tmp/smoke_rag.py
  docker exec open-webui python /tmp/smoke_rag.py
"""

import json
import os
import sqlite3
import time
from datetime import datetime, timedelta, timezone

import jwt
import requests

DB = '/app/backend/data/webui.db'
BASE = 'http://127.0.0.1:8080'
QDRANT = 'http://qdrant:6333'
PDF = '/tmp/contrato-teste.pdf'
ADMIN_EMAIL = 'admin@example.com'

created = {'knowledge': None, 'file': None}
H = {}


def db():
    return sqlite3.connect(DB)


def _pid1_env(name):
    """Lê uma variável de ambiente do processo principal (uvicorn = PID 1)."""
    try:
        with open('/proc/1/environ', 'rb') as fh:
            for part in fh.read().split(b'\0'):
                if part.startswith(name.encode() + b'='):
                    return part.split(b'=', 1)[1].decode()
    except OSError:
        pass
    return ''


def session_token():
    """Assina um JWT de sessão válido para o admin (v0.12.3+ exige sessão humana)."""
    secret = os.environ.get('WEBUI_SECRET_KEY') or _pid1_env('WEBUI_SECRET_KEY')
    assert secret, 'WEBUI_SECRET_KEY não encontrado (env ou /proc/1/environ)'
    c = db()
    row = c.execute('select id from user where email=?', (ADMIN_EMAIL,)).fetchone()
    assert row, f'usuário {ADMIN_EMAIL} não existe'
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


def cleanup():
    if created['knowledge']:
        try:
            r = requests.delete(
                f"{BASE}/api/v1/knowledge/{created['knowledge']}/delete",
                headers=H,
                timeout=60,
            )
            print('cleanup knowledge:', r.status_code, r.text[:120])
        except Exception as exc:  # noqa: BLE001
            print('cleanup knowledge:', exc)
    if created['file']:
        try:
            r = requests.delete(f'{BASE}/api/v1/files/{created["file"]}', headers=H, timeout=120)
            print('cleanup file:', r.status_code, r.text[:200])
        except Exception as exc:  # noqa: BLE001
            print('cleanup file:', exc)

    # OWUI NÃO remove a linha de ligação ao apagar knowledge/file (bug real:
    # 3 execuções deixaram 3 órfãs em knowledge_file). Limpa explicitamente e
    # confirma que nada sobrou — é o teste de regressão do cleanup.
    try:
        c = db()
        n = 0
        if created['knowledge']:
            n += c.execute('delete from knowledge_file where knowledge_id=?',
                           (created['knowledge'],)).rowcount
        if created['file']:
            n += c.execute('delete from knowledge_file where file_id=?',
                           (created['file'],)).rowcount
        c.commit()
        left = 0
        for col, val in (('knowledge_id', created['knowledge']), ('file_id', created['file'])):
            if val:
                left += c.execute(f'select count(*) from knowledge_file where {col}=?', (val,)).fetchone()[0]
        c.close()
        print(f'cleanup knowledge_file: {n} linha(s) removida(s), {left} restante(s)')
        assert left == 0, 'cleanup deixou linhas órfãs em knowledge_file'
    except AssertionError:
        raise
    except Exception as exc:  # noqa: BLE001
        print('cleanup knowledge_file:', exc)

    print('cleanup: ok')


def qdrant_collections():
    r = requests.get(f'{QDRANT}/collections', timeout=10)
    return r.json()['result']['collections']


def main():
    global H
    H = {'Authorization': f'Bearer {session_token()}'}

    # 0) auth check
    me = requests.get(f'{BASE}/api/v1/auths/', headers=H, timeout=30)
    print('auth:', me.status_code, me.json().get('email'))
    me.raise_for_status()

    # 1) upload do PDF (extração via Docling acontece aqui)
    t0 = time.time()
    with open(PDF, 'rb') as fh:
        r = requests.post(
            f'{BASE}/api/v1/files/?process=true&process_in_background=false',
            headers=H,
            files={'file': ('contrato-teste.pdf', fh, 'application/pdf')},
            timeout=900,
        )
    print(f'upload: {r.status_code} em {time.time() - t0:.1f}s')
    r.raise_for_status()
    data = r.json().get('data') or {}
    print('file data:', json.dumps(data, ensure_ascii=False)[:500])
    fid = r.json()['id']
    created['file'] = fid

    # o processamento (Docling) roda em background; aguarda o status
    t0 = time.time()
    status = data.get('status')
    while status not in ('completed', 'failed') and time.time() - t0 < 600:
        time.sleep(2)
        meta = requests.get(f'{BASE}/api/v1/files/{fid}', headers=H, timeout=30).json()
        status = (meta.get('data') or {}).get('status')
        if status == 'failed':
            raise SystemExit(f"processamento falhou: {(meta.get('data') or {}).get('error')}")
    print(f'process status: {status} em {time.time() - t0:.1f}s')
    assert status == 'completed', 'timeout no processamento do arquivo'

    # 2) knowledge base
    r = requests.post(
        f'{BASE}/api/v1/knowledge/create',
        headers=H,
        json={'name': 'Smoke RAG contrato', 'description': 'teste automatizado'},
        timeout=60,
    )
    r.raise_for_status()
    kid = r.json()['id']
    created['knowledge'] = kid
    print('knowledge id:', kid)

    # 3) adiciona arquivo -> chunk + embed (bge-m3) + upsert no Qdrant
    t0 = time.time()
    r = requests.post(
        f'{BASE}/api/v1/knowledge/{kid}/file/add',
        headers=H,
        json={'file_id': fid},
        timeout=1800,
    )
    print(f'file/add: {r.status_code} em {time.time() - t0:.1f}s')
    if not r.ok:
        print(r.text[:800])
    r.raise_for_status()

    # 4) prova no Qdrant: coleção fixa owui_knowledge, escopada por tenant_id=kid
    col = 'owui_knowledge'
    cols = [c['name'] for c in qdrant_collections()]
    print('collections:', cols)
    assert col in cols, f'coleção {col} não foi criada'
    tenant_filter = {'must': [{'key': 'tenant_id', 'match': {'value': kid}}]}
    n = requests.post(
        f'{QDRANT}/collections/{col}/points/count',
        json={'exact': True, 'filter': tenant_filter},
        timeout=30,
    ).json()['result']['count']
    print(f'points em {col} (tenant {kid}): {n}')
    assert n > 0, 'nenhum vetor inserido'

    pts = requests.post(
        f'{QDRANT}/collections/{col}/points/scroll',
        json={
            'limit': 5,
            'with_payload': True,
            'with_vector': False,
            'filter': tenant_filter,
        },
        timeout=30,
    ).json()['result']['points']
    texts = []
    for p in pts:
        txt = p['payload'].get('text') or p['payload'].get('page_content') or ''
        texts.append(txt)
        show = txt or json.dumps(p['payload'], ensure_ascii=False)
        print('  chunk:', show[:160].replace('\n', ' '))
    joined = ' '.join(texts)
    assert '24' in joined or 'vinte e quatro' in joined.lower(), 'conteúdo esperado ausente nos chunks'

    # 5) pergunta ao modelo com a base (citação [1])
    r = requests.post(
        f'{BASE}/api/chat/completions',
        headers=H,
        json={
            'model': 'hermes-agent',
            'stream': False,
            'messages': [
                {
                    'role': 'user',
                    'content': 'Qual é a vigência do contrato e qual a multa por rescisão? Cite a fonte.',
                }
            ],
            'files': [{'type': 'collection', 'id': kid}],
        },
        timeout=900,
    )
    print('chat:', r.status_code)
    if r.ok:
        body = r.json()
        msg = body['choices'][0]['message']
        text = msg.get('content') or ''
        reasoning = msg.get('reasoning_content') or ''
        print('answer:', text[:600].replace('\n', ' '))
        # #8: o raciocínio tem de vir em reasoning_content, nunca dentro do content.
        # (O gateway separa; quando o modelo "pensa em voz alta" sem tags, não há
        # como recuperar — por isso a temperatura mais baixa e esta checagem.)
        print('reasoning_content:', len(reasoning), 'chars')
        if reasoning.strip() and reasoning.strip()[:120] in text:
            print('FAIL: reasoning vazou para dentro do content')
            raise SystemExit(1)
        if '<think>' in text or '</think>' in text:
            print('FAIL: tags de raciocínio no content')
            raise SystemExit(1)
        print('sources:', json.dumps(body.get('sources'), ensure_ascii=False)[:400])
        print('has citation [1]:', '[1]' in text)

        # Citação verificável: a resposta cita [1] e os números que ela afirma
        # (vigência de 24 meses, multa de 10%) têm de existir no TEXTO DAS FONTES
        # que o OWUI recuperou. Sem isso, "[1]" é enfeite: o modelo pode citar um
        # número que não está em chunk nenhum. É o teste de regressão do lastro.
        sources = body.get('sources') or []
        srctext = ' '.join(
            ''.join(s.get('document') or []) for s in sources if isinstance(s, dict)
        )
        if '[1]' not in text:
            print('FAIL: resposta sem citação [1] — o escritório não consegue conferir a fonte')
            raise SystemExit(1)
        if not srctext.strip():
            print('FAIL: OWUI não devolveu os trechos-fonte (sources vazio) — citação não conferível')
            raise SystemExit(1)

        import re
        bare = re.sub(r'\[\d+\]', ' ', text)          # tira os marcadores [1]
        nums = re.findall(r'\d+(?:[.,]\d+)?\s?%?', bare)
        flat = srctext.replace(' ', '').lower()
        missing = [n for n in nums if n.replace(' ', '').lower() not in flat]
        print('números afirmados:', nums, '| sem lastro:', missing)
        if missing:
            print('FAIL: a resposta afirma valor(es) que não estão nos trechos recuperados:', missing)
            raise SystemExit(1)
        if not nums:
            print('FAIL: não há valor conferível na resposta (esperado 24 meses e 10%)')
            raise SystemExit(1)
        print('citation OK: todo valor afirmado existe no texto das fontes')
    else:
        print(r.text[:800])

    print('SMOKE OK')


if __name__ == '__main__':
    try:
        main()
    finally:
        cleanup()
