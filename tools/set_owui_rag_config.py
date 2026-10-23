"""Atualiza a config de RAG do Open WebUI (tabela `config`).

Roda DENTRO do container open-webui:
  docker cp set_owui_rag_config.py open-webui:/tmp/ && docker exec open-webui python /tmp/set_owui_rag_config.py

Por que SQL direto: as chaves `rag.*` são PersistentConfig — o OWUI lê o valor
do banco no boot e ignora mudanças de env depois da primeira execução.
"""

import json
import sqlite3
import sys

DB = '/app/backend/data/webui.db'

DOCLING_PARAMS = {
    'to_formats': ['md'],
    'do_ocr': True,
    'ocr_lang': ['pt'],
    'table_mode': 'accurate',
}

UPDATES = {
    'rag.embedding_engine': 'ollama',
    'rag.embedding_model': 'bge-m3',
    'rag.ollama.base_url': 'http://ollama:11434',
    'rag.content_extraction_engine': 'docling',
    'rag.docling_server_url': 'http://docling:5001',
    'rag.docling_api_key': '',
    'rag.docling_params': DOCLING_PARAMS,
}

DRY_RUN = '--dry-run' in sys.argv

c = sqlite3.connect(DB)
cols = [row[1] for row in c.execute('PRAGMA table_info(config)')]
print('config columns:', cols)

for key, value in UPDATES.items():
    raw = json.dumps(value)
    cur = c.execute('select value from config where key=?', (key,)).fetchone()
    if cur is None:
        print(f'  MISSING {key} (não será criada por SQL; use a UI)')
        continue
    print(f'  {key}: {cur[0]} -> {raw}')
    if not DRY_RUN:
        c.execute('update config set value=? where key=?', (raw, key))

if DRY_RUN:
    print('DRY RUN — nada gravado')
    c.rollback()
else:
    c.commit()
    print('OK — config atualizada. Reinicie o open-webui para recarregar.')
