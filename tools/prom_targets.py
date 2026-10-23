import json
import sys
import urllib.request

url = sys.argv[1] if len(sys.argv) > 1 else 'http://prometheus:9090/api/v1/targets?state=active'
with urllib.request.urlopen(url, timeout=10) as r:
    d = json.load(r)
for t in d['data']['activeTargets']:
    print(t['labels']['job'], t['health'], t.get('lastError', '') or '')
