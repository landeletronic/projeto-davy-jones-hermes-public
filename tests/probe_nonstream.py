"""Sonda 4: repetir o não-stream 3x e medir content/reasoning em cada chamada.

Objetivo: saber se o merge é intermitente (modelo) ou determinístico (OWUI).
"""

import os
import sqlite3
import time
from datetime import datetime, timedelta, timezone

import jwt
import requests

DB = '/app/backend/data/webui.db'
BASE = 'http://127.0.0.1:8080'
EMAIL = 'admin@example.com'


def _pid1_env(name):
    with open('/proc/1/environ', 'rb') as fh:
        for part in fh.read().split(b'\0'):
            if part.startswith(name.encode() + b'='):
                return part.split(b'=', 1)[1].decode()
    return ''


secret = os.environ.get('WEBUI_SECRET_KEY') or _pid1_env('WEBUI_SECRET_KEY')
c = sqlite3.connect(DB)
uid = c.execute('select id from user where email=?', (EMAIL,)).fetchone()[0]
stamp = c.execute('select session_stamp from auth where id=?', (uid,)).fetchone()[0]
tok = jwt.encode(
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
H = {'Authorization': f'Bearer {tok}'}

for i in range(3):
    t0 = time.time()
    r = requests.post(
        f'{BASE}/api/chat/completions',
        headers=H,
        json={
            'model': 'hermes-agent',
            'stream': False,
            'messages': [{'role': 'user', 'content': 'Responda apenas: 2+2=4. Nao explique.'}],
        },
        timeout=900,
    )
    m = r.json()['choices'][0]['message']
    content = m.get('content') or ''
    reasoning = m.get('reasoning_content') or ''
    print(
        'run %d: %5.1fs | content=%4d | reasoning=%5d | keys=%s | head=%r'
        % (i + 1, time.time() - t0, len(content), len(reasoning), list(m.keys()), content[:60])
    )
