#!/usr/bin/env bash
# Testa a conversão do Docling com os MESMOS campos que o Open WebUI envia.
# Requer o PDF em /tmp/contrato-teste.pdf no host.
set -u
out=/tmp/docling_conv.json
code=$(curl -s -o "$out" -w '%{http_code}' --max-time 900 \
  -F "files=@/tmp/contrato-teste.pdf;type=application/pdf" \
  -F "to_formats=md" \
  -F "image_export_mode=placeholder" \
  -F "do_ocr=true" \
  -F "ocr_lang=pt" \
  -F "table_mode=accurate" \
  http://127.0.0.1:5001/v1/convert/file)
echo "HTTP $code"
python3 - "$out" <<'PY'
import json
import sys

d = json.load(open(sys.argv[1]))
print('status:', d.get('status'))
print('processing_time:', d.get('processing_time'))
print('errors:', d.get('errors'))
md = (d.get('document') or {}).get('md_content') or ''
print('md chars:', len(md))
print('--- md sample ---')
print(md[:600])
PY
