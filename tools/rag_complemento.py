#!/usr/bin/env python3
"""Gera o complemento de texto das paginas que o Docling perdeu.

O Docling (v1.37) as vezes classifica uma TABELA como figura: ele ate le o texto
(fica em `texts`, dentro da figura), mas o exportador de markdown escreve
`<!-- image -->` e descarta o que esta dentro. Medido em 2026-10-22 na apostila
de Matematica: a tabela de angulos da p.160 (com `a=e`, `c=g`) nao entrou na base.

Parametro de conversao nao resolve (`table_mode=accurate`, `force_ocr`, os quatro
`pdf_backend` e os formatos text/html dao o mesmo resultado). O que resolve e
este complemento: um `.md` com o texto dessas paginas, extraido do proprio PDF
(`pdftotext`), que o worker ingere como documento normal.

Uso (no host, como usuario):
    python3 tools/rag_complemento.py --dry-run          # so mostra as paginas
    python3 tools/rag_complemento.py                    # grava os complementos
    python3 tools/rag_complemento.py --limiar 0.5       # criterio mais duro
    python3 tools/rag_complemento.py --somente matematica

O arquivo gerado fica ao lado do PDF (`complemento-tabelas-<materia>.md`) e NAO
deve ser editado a mao: refaca com este script se o PDF mudar.
"""
import argparse
import collections
import csv
import datetime
import json
import os
import re
import subprocess
import sys
import unicodedata
import urllib.request

DOCS = '/home/usuario/documents'
MANIFEST = '/home/usuario/rag-state/manifest.csv'
QDRANT = 'http://127.0.0.1:6333'
COLL = 'owui_knowledge'
LIMIAR = 0.6      # abaixo disso a pagina perdeu mais de 40% do texto
MIN_CHARS = 120   # pagina curta (capa, titulo de secao) nao conta


def norm(s):
    return re.sub(r'\s+', ' ', s).strip()


def base_por_pagina(sha):
    """Texto que a base guardou, por pagina (0-based, como o OWUI grava)."""
    paginas, offset = collections.defaultdict(str), None
    while True:
        corpo = {'filter': {'must': [{'key': 'metadata.file_hash', 'match': {'value': sha}}]},
                 'limit': 1024, 'with_payload': ['metadata.page', 'text'], 'with_vector': False}
        if offset is not None:
            corpo['offset'] = offset
        req = urllib.request.Request(f'{QDRANT}/collections/{COLL}/points/scroll',
                                     data=json.dumps(corpo).encode(),
                                     headers={'Content-Type': 'application/json'})
        res = json.load(urllib.request.urlopen(req, timeout=180))['result']
        for p in res['points']:
            paginas[p['payload'].get('metadata', {}).get('page')] += p['payload'].get('text') or ''
        offset = res.get('next_page_offset')
        if offset is None:
            break
    return paginas


def limpar(texto):
    """Tira ruido de extracao: linha so com numero de pagina e excesso de branco."""
    linhas = []
    for linha in texto.splitlines():
        if re.fullmatch(r'\s*\d{1,3}\s*', linha):
            continue
        linhas.append(linha.rstrip())
    texto = '\n'.join(linhas)
    return re.sub(r'\n{3,}', '\n\n', texto).strip()


def pagina_pdf(pdf, n):
    out = subprocess.run(['pdftotext', '-f', str(n), '-l', str(n), pdf, '-'],
                         capture_output=True, text=True, errors='replace')
    return limpar(out.stdout)


def n_paginas(pdf):
    out = subprocess.run(['pdfinfo', pdf], capture_output=True, text=True)
    m = re.search(r'^Pages:\s+(\d+)', out.stdout, re.M)
    return int(m.group(1)) if m else 0


def documentos_ok(caminho):
    """Ultima linha do manifest por sha; so os que estao `ok` hoje."""
    with open(caminho, encoding='utf-8') as fh:
        rows = list(csv.DictReader(fh))
    ultimo = {}
    for r in rows:
        ultimo[r['sha256']] = r
    return [r for r in ultimo.values() if r['estado'] == 'ok']


def slug(texto):
    """'Apostila Médio - Matemática' -> 'apostila-medio-matematica' (nome unico na citacao)."""
    texto = unicodedata.normalize('NFKD', texto)
    texto = texto.encode('ascii', 'ignore').decode()
    return re.sub(r'[^a-z0-9]+', '-', texto.lower()).strip('-')[:55]


def main():
    ap = argparse.ArgumentParser(description='complemento de texto para paginas que o Docling perdeu')
    ap.add_argument('--dry-run', action='store_true', help='so mostra, nao grava')
    ap.add_argument('--limiar', type=float, default=LIMIAR,
                    help=f'gera para pagina com menos de X do texto do PDF (default {LIMIAR})')
    ap.add_argument('--min-chars', type=int, default=MIN_CHARS,
                    help=f'ignora pagina com menos de N chars no PDF (default {MIN_CHARS})')
    ap.add_argument('--somente', default='', help='so documentos cujo caminho contenha este trecho')
    args = ap.parse_args()

    total_paginas = 0
    gerados = 0
    for r in documentos_ok(MANIFEST):
        origem = r['origem']
        if not origem.lower().endswith('.pdf'):
            continue
        if args.somente and args.somente.lower() not in origem.lower():
            continue
        pdf = os.path.join(DOCS, origem)
        if not os.path.exists(pdf):
            print(f'!! sumiu do share: {origem}')
            continue

        n = n_paginas(pdf)
        base = base_por_pagina(r['sha256'])
        perdidas = []
        for pagina in range(1, n + 1):
            texto = pagina_pdf(pdf, pagina)
            if len(texto) < args.min_chars:
                continue
            na_base = norm(re.sub(r'<!-- image -->|<!-- formula-not-decoded -->', '',
                                  base.get(pagina - 1, '')))
            if len(na_base) < args.limiar * len(texto):
                perdidas.append((pagina, len(texto), len(na_base)))

        if not perdidas:
            print(f'== {origem}: nada a fazer ({n} paginas conferidas)')
            continue

        total_paginas += len(perdidas)
        print(f'== {origem}: {len(perdidas)} pagina(s) com perda')
        for pagina, chars_pdf, chars_base in perdidas:
            print(f'   p.{pagina}: {chars_pdf} chars no PDF, {chars_base} na base')

        if args.dry_run:
            continue

        pasta = os.path.dirname(pdf)
        destino = os.path.join(
            pasta, f'complemento-{slug(os.path.splitext(os.path.basename(pdf))[0])}.md')
        hoje = datetime.date.today().isoformat()
        partes = [
            f'# Complemento de tabelas — {os.path.basename(pdf)}',
            '',
            f'> **Arquivo gerado** por `tools/rag_complemento.py` em {hoje}. Não editar à mão:',
            '> refaça com o script se o PDF mudar.',
            '>',
            '> O conversor (Docling) transformou as tabelas destas páginas em imagem e o texto',
            '> não entrou na base. Aqui está esse texto, extraído do próprio PDF, para a busca',
            '> encontrar (as palavras da tabela passam a ser citáveis no chat).',
            '>',
            f'> Fonte: `{origem}`',
            f'> sha256 do PDF: `{r["sha256"]}`',
            f'> Páginas com perda de texto (menos de {int(args.limiar * 100)}% do original): {len(perdidas)}',
            '',
        ]
        for pagina, _, _ in perdidas:
            partes.append(f'## Página {pagina}')
            partes.append('')
            partes.append(pagina_pdf(pdf, pagina))
            partes.append('')
        conteudo = '\n'.join(partes).rstrip() + '\n'

        with open(destino, 'w', encoding='utf-8', newline='') as fh:
            fh.write(conteudo)
        os.chmod(destino, 0o644)
        gerados += 1
        print(f'   -> {destino} ({len(conteudo)} chars, {len(perdidas)} paginas)')

    print()
    if args.dry_run:
        print(f'DRY-RUN: {total_paginas} pagina(s) seriam copiadas; nada foi escrito')
    else:
        print(f'{gerados} complemento(s) gravado(s), {total_paginas} pagina(s) no total')
        if gerados:
            print('o worker ingere em ate 15 min (ou rode: rag-ingest)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
