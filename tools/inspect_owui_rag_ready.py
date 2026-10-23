import sqlite3

c = sqlite3.connect('/app/backend/data/webui.db')
for table in ('config', 'api_key', 'knowledge', 'file', 'user'):
    cols = [r[1] for r in c.execute(f'PRAGMA table_info({table})')]
    n = c.execute(f'select count(*) from {table}').fetchone()[0]
    print(f'{table}: {n} rows | cols={cols}')

print('--- api_key DDL ---')
print(c.execute("select sql from sqlite_master where name='api_key'").fetchone()[0])
print('--- users ---')
for row in c.execute('select id, email, role from user'):
    print(' ', row)
print('--- knowledge ---')
for row in c.execute('select id, name, user_id from knowledge'):
    print(' ', row)
