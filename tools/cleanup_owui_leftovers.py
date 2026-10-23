import sqlite3
import time
import uuid

import requests

DB = '/app/backend/data/webui.db'
BASE = 'http://127.0.0.1:8080'

c = sqlite3.connect(DB)
row = c.execute("select value from config where key='auth.enable_api_keys'").fetchone()
prev = row[0] if row else None
c.execute("update config set value='true' where key='auth.enable_api_keys'")

uid = c.execute("select id from user where role='admin' limit 1").fetchone()[0]
key = 'sk-clean-' + uuid.uuid4().hex
now = int(time.time() * 1000)
c.execute(
    'insert into api_key (id, user_id, key, data, created_at, updated_at) values (?,?,?,?,?,?)',
    (str(uuid.uuid4()), uid, key, None, now, now),
)
c.commit()
H = {'Authorization': f'Bearer {key}'}

try:
    for kid, name in c.execute('select id, name from knowledge').fetchall():
        r = requests.delete(f'{BASE}/api/v1/knowledge/{kid}/delete', headers=H, timeout=60)
        print('knowledge', kid, name, '->', r.status_code, r.text[:300])

    for fid, fname in c.execute('select id, filename from file').fetchall():
        r = requests.delete(f'{BASE}/api/v1/files/{fid}', headers=H, timeout=120)
        print('file', fid, fname, '->', r.status_code, r.text[:300])
finally:
    c.execute('delete from api_key where key=?', (key,))
    if prev is not None:
        c.execute(
            "update config set value=? where key='auth.enable_api_keys'", (prev,)
        )
    c.commit()
    print('restored, api keys flag =', prev)
