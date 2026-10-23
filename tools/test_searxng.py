import requests

r = requests.get(
    'http://searxng:8080/search',
    params={'q': 'contrato de prestacao de servicos', 'format': 'json'},
    timeout=30,
)
print('status', r.status_code)
d = r.json()
results = d.get('results', [])
print('results', len(results))
if results:
    print('first', results[0].get('url'))
