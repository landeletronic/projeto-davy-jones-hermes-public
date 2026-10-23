import sqlite3

c = sqlite3.connect('/app/backend/data/webui.db')
print('=== config rag.* / vector ===')
for k, v in c.execute(
    "select key, value from config where key like 'rag.%' or key like '%vector%' order by key"
):
    print(k, '=>', str(v)[:200])

print('=== chroma collections ===')
c2 = sqlite3.connect('/app/backend/data/vector_db/chroma.sqlite3')
try:
    for row in c2.execute('select id, name from collections'):
        print(row)
except Exception as exc:  # noqa: BLE001
    print('chroma error:', exc)
