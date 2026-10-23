#!/usr/bin/env python3
"""Banco de questões do eixo de estudos: provas + gabaritos do share -> SQLite.

Por que existe (desenho: docs/plans/BANCO-DE-QUESTOES.md): o RAG responde "o que
diz o edital"; ele **não** responde "quantas questões de matemática caíram em
2025" nem "qual a resposta da Q26 de 2024" (o ano está no nome do arquivo, não no
texto — medido em 2026-10-21). Isso é consulta ao banco.

Roda no HOST, só stdlib + `sqlite3`. Texto dos PDFs via `pdftotext` (poppler);
gabarito em imagem via `pdftoppm` + `tesseract` (OCR, 300 dpi).

Regra de ouro: **o importador não inventa**. Ano que não fechar 50 questões / 50
respostas fica `revisar`; `conferir` falha e o relatório diz o que falta. Nada é
apagado do share — o banco é derivado e pode ser reconstruído.

Uso (host):

  questoes importar            # lê o share e (re)importa o que mudou
  questoes conferir            # 50/50 por ano; sai != 0 se algum ano ficou `revisar`
  questoes consultar --ano 2025 --disciplina matematica --numero 26
  questoes estatisticas         # contagens; --publicar escreve o .md citável no RAG
  questoes exportar --csv /var/tmp/questoes.csv

Banco: ~/rag-state/questoes.db (entra no backup diário junto com rag-state).
Relatório: <share>/_relatorio/QUESTOES.md.
"""

import argparse
import csv
import hashlib
import json
import os
import re
import sqlite3
import subprocess
import sys
import tempfile
from datetime import datetime

DOCS = os.environ.get('RAG_DOCUMENTS', '/home/tlandskron/documents')
STATE = os.environ.get('RAG_STATE', '/home/tlandskron/rag-state')
DB = os.path.join(STATE, 'questoes.db')
RELATORIO = '_relatorio/QUESTOES.md'
# Documento citável no RAG (entra pelo worker, tipo `doc`, base Tiradentes BM).
ESTATISTICAS = 'referencias/estatisticas-questoes.md'

CORTE_MATEMATICA = 26          # 1..25 português, 26..50 matemática (fallback)
DISCIPLINAS = {'portugues': 'Língua Portuguesa', 'matematica': 'Matemática'}
TOTAL_QUESTOES = 50

RE_QUESTAO = re.compile(r'^\s*Quest[aã]o\s+(\d{1,3})\b\s*(.*)$', re.I)
# A indentação das alternativas varia DENTRO do mesmo ano (3 espaços na Q7 de
# 2021, 13 na Q6) — por isso `^\s*`, não `^\s{0,8}`.
RE_ALTERNATIVA = re.compile(r'^\s*\(?\s*([A-Ea-e])\s*[\)\.]\s*(.*)$')
RE_SECAO = re.compile(
    r'^\s*(?:PROVA\s+DE\s+)?(L[ÍI]NGUA\s+PORTUGUESA|MATEM[ÁA]TICA)\s*\.?\s*$', re.I)
# Mobília de página (cabeçalho/rodapé): não é conteúdo de questão.
RE_RUIDO = re.compile(
    r'(Col[ée]gio Tiradentes\s*[–-]\s*Concurso de Admiss[ãa]o'
    r'|L[ÍI]NGUA PORTUGUESA e MATEM[ÁA]TICA\s*[–-]'
    r'|PROVA DE L[ÍI]NGUA PORTUGUESA E MATEM[ÁA]TICA'
    r'|P[áa]gina\s+\d+)', re.I)
RE_PAR_PDF = re.compile(r'(?<![\d])(\d{1,3})\s+([A-Ea-e]{1,2})(?![\w])')
RE_PAR_TXT = re.compile(r'^\s*(\d{1,3})\s*[\)\.\-–:]?\s*([A-Ea-e])\s*$', re.M)
RE_ARQUIVO = re.compile(r'^(prova|gabarito)-(\d{4})\.(pdf|txt|md)$', re.I)


class Falha(Exception):
    """Erro de um ano só: vira situação `revisar` no relatório."""


def agora():
    # Horário LOCAL com offset (o relatório é lido no Explorer, como o INGESTAO.md).
    return datetime.now().astimezone().isoformat(timespec='seconds')


def sha256(caminho):
    h = hashlib.sha256()
    with open(caminho, 'rb') as fh:
        for bloco in iter(lambda: fh.read(1 << 20), b''):
            h.update(bloco)
    return h.hexdigest()


def normalizar(texto):
    return re.sub(r'\s+', ' ', texto or '').strip()


def letra_de(token):
    """'C', 'Cc', 'c' -> 'C'. OCR repete a letra em célula estreita; 'De' não é letra."""
    token = (token or '').strip()
    if token and len(set(token.upper())) == 1 and token[0].upper() in 'ABCDE':
        return token[0].upper()
    return ''


def rodar(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


# ---------------------------------------------------------------------------
# leitura dos arquivos
# ---------------------------------------------------------------------------

def texto_pdf(caminho):
    r = rodar(['pdftotext', '-layout', caminho, '-'])
    if r.returncode != 0:
        raise Falha(f'pdftotext falhou em {os.path.basename(caminho)}: {r.stderr.strip()[:200]}')
    return r.stdout


def paginas_pdf(caminho):
    r = rodar(['pdfinfo', caminho])
    m = re.search(r'^Pages:\s+(\d+)', r.stdout, re.M)
    return int(m.group(1)) if m else 0


def disciplina_por_numero(numero):
    return 'matematica' if numero >= CORTE_MATEMATICA else 'portugues'


def _sem_mobilia(linhas):
    """Remove cabeçalho/rodapé e número de página das bordas da página."""
    def ruido(linha):
        t = linha.strip()
        if not t:
            return False
        return bool(RE_RUIDO.search(t)) or bool(re.fullmatch(r'\d{1,3}', t))

    while linhas and (not linhas[0].strip() or ruido(linhas[0])):
        linhas.pop(0)
    while linhas and (not linhas[-1].strip() or ruido(linhas[-1])):
        linhas.pop()
    return linhas


def ler_prova(texto):
    """{'numero': {enunciado, pagina, disciplina, alternativas{letra: texto}}}."""
    questoes = {}
    secao = None
    atual = None
    alternativa = None
    fim_alternativas = False
    duplicadas = []

    for pagina, pagina_txt in enumerate(texto.replace('\r\n', '\n').split('\f'), start=1):
        for linha in _sem_mobilia([l.rstrip() for l in pagina_txt.split('\n')]):
            msec = RE_SECAO.match(linha)
            # Cabeçalho de verdade é CAIXA ALTA e curto ("MATEMÁTICA", "PROVA DE
            # MATEMÁTICA"). Minúsculo no meio de um texto ("língua portuguesa.") é
            # frase, não seção — trocar a disciplina ali seria erro silencioso.
            if msec and linha.strip() == linha.strip().upper():
                secao = 'matematica' if 'MATEM' in msec.group(1).upper() else 'portugues'
                continue

            mq = RE_QUESTAO.match(linha)
            if mq:
                numero = int(mq.group(1))
                if 1 <= numero <= 100:
                    if numero in questoes:
                        # referência no meio de um texto ("Questão 5 do Texto 2") não
                        # pode sobrescrever a questão de verdade
                        duplicadas.append(numero)
                        atual = None
                        alternativa = None
                        continue
                    resto = re.sub(r'^[\s\.\)\-–—:]*', '', mq.group(2))
                    atual = {'numero': numero, 'enunciado': [resto], 'pagina': pagina,
                             'disciplina': secao or disciplina_por_numero(numero),
                             'alternativas': {}}
                    questoes[numero] = atual
                    alternativa = None
                    fim_alternativas = False
                    continue

            if atual is None:
                continue

            if not linha.strip():
                # Linha em branco depois das alternativas fecha a questão: o que
                # vier depois é texto de leitura/instrução, não letra (E) infinda.
                if alternativa or atual['alternativas']:
                    alternativa = None
                    fim_alternativas = True
                continue

            ma = RE_ALTERNATIVA.match(linha)
            if ma:
                letra = ma.group(1).upper()
                resto = normalizar(ma.group(2))
                if letra in atual['alternativas']:
                    atual['alternativas'][letra] = normalizar(
                        atual['alternativas'][letra] + ' ' + resto)
                else:
                    atual['alternativas'][letra] = resto
                alternativa = letra
                fim_alternativas = False
            elif alternativa:
                atual['alternativas'][alternativa] = normalizar(
                    atual['alternativas'][alternativa] + ' ' + linha.strip())
            elif not fim_alternativas:
                atual['enunciado'].append(linha.strip())

    for q in questoes.values():
        q['enunciado'] = normalizar(' '.join(q['enunciado']))
    return {'questoes': questoes, 'duplicadas': duplicadas}


def ler_pares_texto(texto):
    """Gabarito em texto: '(1  C  26  C)' ou '1D' por linha."""
    pares = {}
    for linha in texto.replace('\r\n', '\n').split('\n'):
        for n, token in RE_PAR_PDF.findall(linha):
            numero, letra = int(n), letra_de(token)
            if letra and 1 <= numero <= 100:
                pares.setdefault(numero, letra)
    if len(pares) < TOTAL_QUESTOES:
        for n, token in RE_PAR_TXT.findall(texto):
            numero, letra = int(n), letra_de(token)
            if letra and 1 <= numero <= 100:
                pares.setdefault(numero, letra)
    return pares


def _grade_por_coordenadas(imagem):
    """Lê tabela em GRADE (números numa linha, letras na de baixo) via TSV.

    O gabarito de 2023 é uma grade com bordas: o OCR de texto corrido embaralha
    tudo. Já o modo esparso (--psm 11) devolve cada célula com coordenada, e o
    pareamento número->letra é geométrico (letra abaixo, mesma coluna).
    """
    with tempfile.TemporaryDirectory(prefix='questoes-tsv-') as tmp:
        base = os.path.join(tmp, 'out')
        r = rodar(['tesseract', imagem, base, '-l', 'eng', '--psm', '11', 'tsv'])
        if r.returncode != 0:
            return {}
        caminho = base + '.tsv'
        if not os.path.exists(caminho):
            return {}
        numeros, letras = [], []
        with open(caminho, encoding='utf-8', errors='replace') as fh:
            for row in csv.DictReader(fh, delimiter='\t', quoting=csv.QUOTE_NONE):
                t = (row.get('text') or '').strip()
                if not t:
                    continue
                try:
                    x = int(row['left']) + int(row['width']) // 2
                    y = int(row['top']) + int(row['height']) // 2
                except (KeyError, ValueError):
                    continue
                if re.fullmatch(r'\d{1,2}[\).]?', t):
                    numeros.append((int(t.rstrip(').')), x, y))
                elif re.fullmatch(r'[A-Ea-e]{1,2}', t):
                    letras.append((t[0].upper(), x, y))
    pares = {}
    for numero, x, y in numeros:
        if not 1 <= numero <= 100:
            continue
        candidatas = [(l, xl, yl) for l, xl, yl in letras
                      if 40 < yl - y < 130 and abs(xl - x) < 35]
        if candidatas:
            letra = min(candidatas, key=lambda c: (abs(c[1] - x), c[2] - y))[0]
            pares.setdefault(numero, letra)
    return pares


def ocr_gabarito(caminho):
    """(respostas, fonte) de um gabarito que é imagem dentro do PDF."""
    if not (os.path.exists('/usr/bin/tesseract') or os.path.exists('/usr/local/bin/tesseract')):
        raise Falha('gabarito é imagem e o tesseract não está instalado')
    with tempfile.TemporaryDirectory(prefix='questoes-ocr-') as tmp:
        base = os.path.join(tmp, 'p')
        r = rodar(['pdftoppm', '-r', '300', '-png', caminho, base])
        if r.returncode != 0:
            raise Falha(f'pdftoppm falhou: {r.stderr.strip()[:200]}')
        imagens = sorted(os.path.join(tmp, f) for f in os.listdir(tmp) if f.endswith('.png'))
        pares, fontes = {}, set()
        for imagem in imagens:
            # 1) tabela de duas colunas ("1 C 26 c") -> texto corrido resolve
            r = rodar(['tesseract', imagem, '-', '-l', 'eng', '--psm', '6'])
            corrida = ler_pares_texto(r.stdout)
            if len(corrida) > len(pares):
                pares, fontes = corrida, {'ocr-tabela'}
            # 2) grade (números numa linha, letras na de baixo)
            grade = _grade_por_coordenadas(imagem)
            if len(grade) > len(pares):
                pares, fontes = grade, {'ocr-grade'}
        if len(pares) >= TOTAL_QUESTOES:
            return pares, sorted(fontes)[0]
        raise Falha(f'OCR leu {len(pares)} de {TOTAL_QUESTOES} respostas '
                    f'(gabarito em imagem ilegível: digite gabarito-<ano>.txt)')


def ler_gabarito(caminho):
    """(respostas, fonte). Tenta texto; se não fechar, OCR."""
    ext = os.path.splitext(caminho)[1].lower()
    if ext in ('.txt', '.md'):
        with open(caminho, encoding='utf-8', errors='replace') as fh:
            pares = ler_pares_texto(fh.read())
        fonte = 'txt'
    else:
        pares = ler_pares_texto(texto_pdf(caminho))
        fonte = 'texto'
        if len(pares) < TOTAL_QUESTOES:
            pares, fonte = ocr_gabarito(caminho)
    return pares, fonte


# ---------------------------------------------------------------------------
# banco
# ---------------------------------------------------------------------------

SCHEMA = """
CREATE TABLE IF NOT EXISTS arquivo (
    caminho TEXT PRIMARY KEY,
    sha256 TEXT NOT NULL,
    importado_em TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS prova (
    ano TEXT PRIMARY KEY,
    arquivo TEXT NOT NULL,
    sha256 TEXT NOT NULL,
    paginas INTEGER NOT NULL DEFAULT 0,
    questoes INTEGER NOT NULL DEFAULT 0,
    importado_em TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS questao (
    ano TEXT NOT NULL,
    numero INTEGER NOT NULL,
    disciplina TEXT NOT NULL,
    enunciado TEXT NOT NULL,
    pagina INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (ano, numero)
);
CREATE TABLE IF NOT EXISTS alternativa (
    ano TEXT NOT NULL,
    numero INTEGER NOT NULL,
    letra TEXT NOT NULL,
    texto TEXT NOT NULL,
    PRIMARY KEY (ano, numero, letra)
);
CREATE TABLE IF NOT EXISTS gabarito (
    ano TEXT NOT NULL,
    numero INTEGER NOT NULL,
    letra TEXT NOT NULL,
    fonte TEXT NOT NULL,
    PRIMARY KEY (ano, numero)
);
CREATE TABLE IF NOT EXISTS ano_status (
    ano TEXT PRIMARY KEY,
    prova_ok INTEGER NOT NULL DEFAULT 0,
    gabarito_ok INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL,
    detalhe TEXT NOT NULL DEFAULT '',
    atualizado_em TEXT NOT NULL
);
"""


def conectar(caminho=DB):
    os.makedirs(os.path.dirname(caminho) or '.', exist_ok=True)
    conn = sqlite3.connect(caminho)
    conn.row_factory = sqlite3.Row
    conn.executescript(SCHEMA)
    return conn


def descobrir(docs=DOCS):
    """{ano: {'prova': caminho, 'gabarito': caminho}} varrendo o share."""
    por_ano = {}
    raiz = os.path.join(docs, 'concurso')
    for pasta, _, arquivos in os.walk(raiz):
        for nome in arquivos:
            m = RE_ARQUIVO.match(nome)
            if not m:
                continue
            tipo, ano = m.group(1).lower(), m.group(2)
            por_ano.setdefault(ano, {}).setdefault(tipo, os.path.join(pasta, nome))
    return por_ano


def _gravar_ano(conn, ano, prova, gabarito, questoes, paginas, respostas, fonte,
                duplicadas):
    conn.execute('DELETE FROM questao WHERE ano = ?', (ano,))
    conn.execute('DELETE FROM alternativa WHERE ano = ?', (ano,))
    conn.execute('DELETE FROM gabarito WHERE ano = ?', (ano,))
    for numero, q in sorted(questoes.items()):
        conn.execute(
            'INSERT INTO questao (ano, numero, disciplina, enunciado, pagina) VALUES (?,?,?,?,?)',
            (ano, numero, q['disciplina'], q['enunciado'], q['pagina']))
        for letra, texto in sorted(q['alternativas'].items()):
            conn.execute(
                'INSERT INTO alternativa (ano, numero, letra, texto) VALUES (?,?,?,?)',
                (ano, numero, letra, texto))
    for numero, letra in sorted(respostas.items()):
        conn.execute('INSERT INTO gabarito (ano, numero, letra, fonte) VALUES (?,?,?,?)',
                     (ano, numero, letra, fonte))
    if prova:
        conn.execute(
            'INSERT OR REPLACE INTO prova (ano, arquivo, sha256, paginas, questoes, importado_em) '
            'VALUES (?,?,?,?,?,?)',
            (ano, os.path.relpath(prova, DOCS), sha256(prova), paginas, len(questoes), agora()))

    faltando_q = [n for n in range(1, TOTAL_QUESTOES + 1) if n not in questoes]
    faltando_r = [n for n in range(1, TOTAL_QUESTOES + 1) if n not in respostas]
    problemas = []
    if prova and len(questoes) != TOTAL_QUESTOES:
        problemas.append(f'{len(questoes)} questões')
    if prova and faltando_q:
        problemas.append('questões faltando ' + ','.join(map(str, faltando_q[:8]))
                         + ('...' if len(faltando_q) > 8 else ''))
    if gabarito and len(respostas) != TOTAL_QUESTOES:
        problemas.append(f'{len(respostas)} respostas')
    if gabarito and faltando_r:
        problemas.append('respostas faltando ' + ','.join(map(str, faltando_r[:8]))
                         + ('...' if len(faltando_r) > 8 else ''))
    if duplicadas:
        problemas.append('marcador repetido em ' + ','.join(map(str, sorted(set(duplicadas)))))
    if not gabarito and prova:
        problemas.append('sem gabarito')
    if gabarito and not prova:
        problemas.append('sem prova (só edital)')

    if prova and gabarito and not faltando_q and not faltando_r and len(questoes) == TOTAL_QUESTOES \
            and len(respostas) == TOTAL_QUESTOES and not duplicadas:
        status, detalhe = 'ok', ''
    elif not prova and gabarito:
        status, detalhe = 'sem_prova', '; '.join(problemas)
    elif prova and not gabarito:
        status, detalhe = 'sem_gabarito', '; '.join(problemas)
    else:
        status, detalhe = 'revisar', '; '.join(problemas)

    conn.execute(
        'INSERT OR REPLACE INTO ano_status (ano, prova_ok, gabarito_ok, status, detalhe, atualizado_em) '
        'VALUES (?,?,?,?,?,?)',
        (ano, int(status == 'ok' and bool(prova)), int(status == 'ok' and bool(gabarito)),
         status, detalhe, agora()))
    return status, detalhe


def importar(docs=DOCS, db=DB, forcar=False, quieto=False):
    por_ano = descobrir(docs)
    if not por_ano:
        print(f'nada a importar: {os.path.join(docs, "concurso")} não tem prova-<ano>/gabarito-<ano>')
        return 0

    conn = conectar(db)
    with conn:
        for ano in sorted(por_ano):
            caminhos = por_ano[ano]
            prova = caminhos.get('prova')
            gabarito = caminhos.get('gabarito')

            mudou = forcar
            for caminho in (prova, gabarito):
                if not caminho:
                    continue
                linha = conn.execute('SELECT sha256 FROM arquivo WHERE caminho = ?',
                                     (os.path.relpath(caminho, docs),)).fetchone()
                if linha is None or linha['sha256'] != sha256(caminho):
                    mudou = True
            if not mudou:
                continue

            questoes, duplicadas, paginas = {}, [], 0
            if prova:
                if os.path.splitext(prova)[1].lower() == '.pdf':
                    texto = texto_pdf(prova)
                    paginas = paginas_pdf(prova)
                else:
                    with open(prova, encoding='utf-8', errors='replace') as fh:
                        texto = fh.read()
                lido = ler_prova(texto)
                questoes, duplicadas = lido['questoes'], lido['duplicadas']

            respostas, fonte = {}, '-'
            try:
                if gabarito:
                    respostas, fonte = ler_gabarito(gabarito)
            except Falha as exc:
                respostas, fonte = {}, f'falha: {exc}'

            status, detalhe = _gravar_ano(conn, ano, prova, gabarito, questoes, paginas,
                                          respostas, fonte, duplicadas)
            for caminho in (prova, gabarito):
                if caminho:
                    conn.execute(
                        'INSERT OR REPLACE INTO arquivo (caminho, sha256, importado_em) VALUES (?,?,?)',
                        (os.path.relpath(caminho, docs), sha256(caminho), agora()))
            if not quieto:
                print(f'{ano}: {status:12} {len(questoes):3} questões {len(respostas):3} respostas'
                      f' ({fonte})' + (f' — {detalhe}' if detalhe else ''))

    escrever_relatorio(conn, docs)
    conn.close()
    return 0


# ---------------------------------------------------------------------------
# relatórios
# ---------------------------------------------------------------------------

def _linhas_status(conn):
    return conn.execute('SELECT * FROM ano_status ORDER BY ano').fetchall()


def escrever_relatorio(conn, docs=DOCS):
    linhas = _linhas_status(conn)
    total_q = conn.execute('SELECT COUNT(*) FROM questao').fetchone()[0]
    total_r = conn.execute('SELECT COUNT(*) FROM gabarito').fetchone()[0]
    alt = conn.execute('SELECT COUNT(*) FROM alternativa').fetchone()[0]
    figura = conn.execute("SELECT COUNT(*) FROM alternativa WHERE trim(texto) = ''").fetchone()[0]

    out = ['# Banco de questões — Colégio Tiradentes BM/RS', '',
           f'Atualizado em **{agora()}**. Gerado por `tools/questoes.py` — não editar à mão.', '',
           f'**{total_q} questões**, **{alt} alternativas** (**{figura}** só-figura), '
           f'**{total_r} respostas** de gabarito.', '',
           '| Ano | Questões | Respostas | Sem alternativas | Situação | Observação |',
           '|---|---|---|---|---|---|']
    for s in linhas:
        q = conn.execute('SELECT COUNT(*) FROM questao WHERE ano = ?', (s['ano'],)).fetchone()[0]
        r = conn.execute('SELECT COUNT(*) FROM gabarito WHERE ano = ?', (s['ano'],)).fetchone()[0]
        sem_alt = conn.execute(
            'SELECT COUNT(*) FROM questao q WHERE q.ano = ? AND NOT EXISTS '
            '(SELECT 1 FROM alternativa a WHERE a.ano = q.ano AND a.numero = q.numero)',
            (s['ano'],)).fetchone()[0]
        out.append(f"| {s['ano']} | {q} | {r} | {sem_alt} | {s['status']} | {s['detalhe'] or '—'} |")
    out += ['', '## Situação', '',
            '- `ok`: 50 questões (1–50) e 50 respostas, sem buraco.',
            '- `revisar`: arquivo presente mas incompleto — o importador **não inventa**; corrija o PDF/.txt.',
            '- `sem_prova`: só o gabarito (ex.: 2027, que tem edital e gabarito, mas prova ainda não publicada).',
            '- `sem_gabarito`: prova sem gabarito legível.',
            '- `Sem alternativas`: a questão cujas opções são **figura/tabela** no PDF (ex.: 2022 Q48) — '
            'não há texto para extrair; o enunciado e o gabarito continuam válidos.',
            '- `só-figura`: a alternativa existe, mas o conteúdo é uma imagem (ex.: gráfico da 2023 Q47). '
            'A consulta mostra `[figura/tabela no PDF]`; para resolver, abra o PDF.', '']
    caminho = os.path.join(docs, RELATORIO)
    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    conteudo = '\n'.join(out)
    anterior = None
    if os.path.exists(caminho):
        with open(caminho, encoding='utf-8') as fh:
            anterior = fh.read()
    if anterior != conteudo:
        tmp = caminho + '.tmp'
        with open(tmp, 'w', encoding='utf-8') as fh:
            fh.write(conteudo)
        os.replace(tmp, caminho)
    return caminho


def estatisticas(conn):
    """Lista de dicts por ano com contagens e distribuição de respostas."""
    dados = []
    for s in _linhas_status(conn):
        ano = s['ano']
        port = conn.execute("SELECT COUNT(*) FROM questao WHERE ano = ? AND disciplina = 'portugues'",
                            (ano,)).fetchone()[0]
        mat = conn.execute("SELECT COUNT(*) FROM questao WHERE ano = ? AND disciplina = 'matematica'",
                           (ano,)).fetchone()[0]
        dist = {l: 0 for l in 'ABCDE'}
        for row in conn.execute('SELECT letra, COUNT(*) AS n FROM gabarito WHERE ano = ? GROUP BY letra',
                                (ano,)):
            if row['letra'] in dist:
                dist[row['letra']] = row['n']
        dados.append({'ano': ano, 'portugues': port, 'matematica': mat,
                      'total': port + mat, 'dist': dist, 'status': s['status']})
    return dados


def markdown_estatisticas(conn):
    dados = estatisticas(conn)
    total_p = sum(d['portugues'] for d in dados)
    total_m = sum(d['matematica'] for d in dados)
    total_r = conn.execute('SELECT COUNT(*) FROM gabarito').fetchone()[0]
    out = ['# Estatísticas das questões — Colégio Tiradentes BM/RS', '',
           f'Gerado em **{datetime.now().strftime("%Y-%m-%d")}** por `tools/questoes.py` '
           'a partir das provas do share.',
           'Documento derivado: **não editar à mão** (a próxima importação o reescreve).', '',
           '## Questões por ano e disciplina', '',
           '| Ano | Língua Portuguesa | Matemática | Total |', '|---|---|---|---|']
    for d in dados:
        if d['total'] == 0:
            continue
        out.append(f"| {d['ano']} | {d['portugues']} | {d['matematica']} | {d['total']} |")
    out += [f'| **Total** | **{total_p}** | **{total_m}** | **{total_p + total_m}** |', '',
            '## Distribuição das respostas do gabarito', '',
            '| Ano | A | B | C | D | E | Total |', '|---|---|---|---|---|---|---|']
    for d in dados:
        if sum(d['dist'].values()) == 0:
            continue
        out.append('| ' + d['ano'] + ' | ' + ' | '.join(str(d['dist'][l]) for l in 'ABCDE')
                   + f" | {sum(d['dist'].values())} |")
    out += [f'| **Total** | ' + ' | '.join(
        f"**{sum(d['dist'][l] for d in dados)}**" for l in 'ABCDE') + f' | **{total_r}** |', '',
        '## Cobertura', '',
        '| Ano | Situação |', '|---|---|']
    for d in dados:
        out.append(f"| {d['ano']} | {d['status']} |")
    out.append('')
    return '\n'.join(out)


def publicar_estatisticas(conn, docs=DOCS):
    caminho = os.path.join(docs, ESTATISTICAS)
    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    conteudo = markdown_estatisticas(conn)
    anterior = None
    if os.path.exists(caminho):
        with open(caminho, encoding='utf-8') as fh:
            anterior = fh.read()
    if anterior != conteudo:
        tmp = caminho + '.tmp'
        with open(tmp, 'w', encoding='utf-8') as fh:
            fh.write(conteudo)
        os.replace(tmp, caminho)
        return caminho, True
    return caminho, False


def conferir(conn, quieto=False):
    linhas = _linhas_status(conn)
    problemas = []
    if not linhas:
        print('banco vazio: rode `questoes importar`')
        return 1
    for s in linhas:
        q = conn.execute('SELECT COUNT(*) FROM questao WHERE ano = ?', (s['ano'],)).fetchone()[0]
        r = conn.execute('SELECT COUNT(*) FROM gabarito WHERE ano = ?', (s['ano'],)).fetchone()[0]
        if not quieto:
            print(f"{s['ano']}: {s['status']:12} {q:3} questões {r:3} respostas"
                  + (f" — {s['detalhe']}" if s['detalhe'] else ''))
        if s['status'] == 'revisar':
            problemas.append(f"{s['ano']}: {s['detalhe']}")
        if s['status'] in ('ok', 'sem_prova') and q not in (0, TOTAL_QUESTOES):
            problemas.append(f"{s['ano']}: {q} questões")
        if s['status'] in ('ok', 'sem_gabarito') and r not in (0, TOTAL_QUESTOES):
            problemas.append(f"{s['ano']}: {r} respostas")
    if problemas:
        print('\nFALHA — anos incompletos (o importador não inventa):')
        for p in problemas:
            print('  ' + p)
        return 1
    print(f'\nok: {len(linhas)} ano(s) conferido(s) — 50/50 onde há prova e gabarito')
    return 0


# ---------------------------------------------------------------------------
# consulta / exportação
# ---------------------------------------------------------------------------

def consultar(conn, ano=None, disciplina=None, numero=None, texto=None, limite=10,
              com_alternativas=True):
    sql = ('SELECT q.ano, q.numero, q.disciplina, q.enunciado, q.pagina, g.letra, g.fonte '
           'FROM questao q LEFT JOIN gabarito g ON g.ano = q.ano AND g.numero = q.numero WHERE 1=1')
    args = []
    if ano:
        sql += ' AND q.ano = ?'
        args.append(str(ano))
    if disciplina:
        sql += ' AND q.disciplina = ?'
        args.append(disciplina)
    if numero:
        sql += ' AND q.numero = ?'
        args.append(int(numero))
    if texto:
        sql += ' AND q.enunciado LIKE ?'
        args.append(f'%{texto}%')
    sql += ' ORDER BY q.ano, q.numero LIMIT ?'
    args.append(int(limite))
    linhas = conn.execute(sql, args).fetchall()
    if not linhas:
        print('nenhuma questão encontrada')
        return 1
    for linha in linhas:
        gab = linha['letra'] or '—'
        print(f"\n{linha['ano']} Q{linha['numero']} [{DISCIPLINAS.get(linha['disciplina'], linha['disciplina'])}]"
              f" (p. {linha['pagina']})  gabarito: {gab}")
        print(f"  {linha['enunciado']}")
        if com_alternativas:
            for alt in conn.execute('SELECT letra, texto FROM alternativa WHERE ano = ? AND numero = ? '
                                    'ORDER BY letra', (linha['ano'], linha['numero'])):
                texto = alt['texto'] or '[figura/tabela no PDF — não há texto para extrair]'
                print(f"    ({alt['letra']}) {texto}")
    return 0


def exportar(conn, destino, formato='csv'):
    linhas = conn.execute(
        'SELECT q.ano, q.numero, q.disciplina, q.enunciado, q.pagina, g.letra '
        'FROM questao q LEFT JOIN gabarito g ON g.ano = q.ano AND g.numero = q.numero '
        'ORDER BY q.ano, q.numero').fetchall()
    alts = {}
    for a in conn.execute('SELECT ano, numero, letra, texto FROM alternativa ORDER BY ano, numero, letra'):
        alts.setdefault((a['ano'], a['numero']), {})[a['letra']] = a['texto']
    with open(destino, 'w', encoding='utf-8', newline='') as fh:
        w = csv.writer(fh, delimiter=';' if formato == 'csv' else ',')
        w.writerow(['ano', 'numero', 'disciplina', 'pagina', 'gabarito', 'enunciado',
                    'A', 'B', 'C', 'D', 'E'])
        for linha in linhas:
            alt = alts.get((linha['ano'], linha['numero']), {})
            w.writerow([linha['ano'], linha['numero'], linha['disciplina'], linha['pagina'],
                        linha['letra'] or '', linha['enunciado'],
                        alt.get('A', ''), alt.get('B', ''), alt.get('C', ''),
                        alt.get('D', ''), alt.get('E', '')])
    print(f'exportado: {destino} ({len(linhas)} questões)')
    return 0


# ---------------------------------------------------------------------------

def main(argv=None):
    p = argparse.ArgumentParser(description='Banco de questões do eixo de estudos.')
    p.add_argument('--db', default=DB)
    p.add_argument('--documents', default=DOCS)
    sub = p.add_subparsers(dest='cmd')

    i = sub.add_parser('importar', help='lê o share e (re)importa o que mudou')
    i.add_argument('--forcar', action='store_true')
    i.add_argument('--quiet', action='store_true')

    c = sub.add_parser('conferir', help='50 questões/50 respostas por ano')
    c.add_argument('--quiet', action='store_true')

    q = sub.add_parser('consultar', help='busca por ano/disciplina/número/texto')
    q.add_argument('--ano')
    q.add_argument('--disciplina', choices=sorted(DISCIPLINAS))
    q.add_argument('--numero', type=int)
    q.add_argument('--texto')
    q.add_argument('--limite', type=int, default=10)
    q.add_argument('--sem-alternativas', action='store_true')

    e = sub.add_parser('estatisticas', help='contagens por ano/disciplina')
    e.add_argument('--publicar', action='store_true',
                   help='escreve referencias/estatisticas-questoes.md no share (vai ao RAG)')
    e.add_argument('--json', action='store_true')

    x = sub.add_parser('exportar', help='CSV/MD com as questões')
    x.add_argument('--destino', required=True)
    x.add_argument('--formato', choices=['csv', 'md'], default='csv')

    args = p.parse_args(argv)
    if not args.cmd:
        args.cmd = 'importar'
        args.forcar = False
        args.quiet = False

    if args.cmd == 'importar':
        return importar(args.documents, args.db, args.forcar, args.quiet)

    conn = conectar(args.db)
    try:
        if args.cmd == 'conferir':
            return conferir(conn, args.quiet)
        if args.cmd == 'consultar':
            return consultar(conn, args.ano, args.disciplina, args.numero, args.texto,
                             args.limite, not args.sem_alternativas)
        if args.cmd == 'estatisticas':
            dados = estatisticas(conn)
            if args.json:
                print(json.dumps(dados, ensure_ascii=False, indent=2))
            else:
                print(markdown_estatisticas(conn))
            if args.publicar:
                caminho, mudou = publicar_estatisticas(conn, args.documents)
                print(('publicado: ' if mudou else 'sem mudança: ') + caminho, file=sys.stderr)
            return 0
        if args.cmd == 'exportar':
            return exportar(conn, args.destino, args.formato)
    finally:
        conn.close()
    return 0


if __name__ == '__main__':
    sys.exit(main())
