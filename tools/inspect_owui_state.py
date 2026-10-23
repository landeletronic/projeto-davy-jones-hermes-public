import sqlite3

c = sqlite3.connect('/app/backend/data/webui.db')
print('--- files ---')
for row in c.execute('select id, filename, data from file'):
    print(row)
print('--- knowledge ---')
for row in c.execute('select id, name, data from knowledge'):
    print(row)
print('--- api_keys ---')
for row in c.execute('select id, user_id, substr(key,1,10) from api_key'):
    print(row)
print('--- enable_api_keys ---')
print(c.execute("select value from config where key='auth.enable_api_keys'").fetchone())
