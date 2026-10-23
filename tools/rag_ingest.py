#!/usr/bin/env python3
"""Worker de ingestão do eixo de estudos: share `documentos` -> base do OWUI.

O caminho de um arquivo (desenho: docs/plans/DESENHO-INBOX-DOCUMENTS.md §6):

  1. varre ~/documents (pula o que começa com `_` e o LEIA-ME.txt);
  2. ignora arquivo com menos de 30 s de idade (cópia em andamento pelo Explorer);
  3. calcula o SHA-256 e consulta ~/rag-state/manifest.csv;
  4. se é novo, roda o upload DENTRO do container (a pasta está montada :ro em
     /documents) via tools/owui_upload.py;
  5. grava a linha no manifest e reescreve _relatorio/INGESTAO.md no share;
  6. falhou? copia para _rejeitados/ com <arquivo>.motivo.txt (para o usuário ver
     no Explorer e corrigir);
  7. publica o estado no textfile do node-exporter (hermes_rag_*, Fase 4) — é o
     que o Prometheus/Grafana leem e o que o alerta de "pendente > 24 h" olha.

Regra de ouro: o processo **nunca** apaga conhecimento sozinho. Remoção de arquivo que
saiu do share é explícita:

  python3 tools/rag_ingest.py --remover <sha256|prefixo>

Exceção (atualização, não remoção): o **mesmo caminho** com conteúdo novo é uma versão
nova do mesmo documento — a nova sobe e a antiga sai da base (marcada `substituido` no
manifest). O texto que você corrigiu não fica citável ao lado do corrigido.

Uso (host, roda como tlandskron — o mesmo dono do share):

  python3 tools/rag_ingest.py --dry-run     # mostra o que faria; não escreve nada
  python3 tools/rag_ingest.py               # ingere o que é novo (e substitui versões)
  python3 tools/rag_ingest.py --retentar    # tenta de novo o que está em `falhou`

Só usa a biblioteca padrão do Python (host não tem venv).
"""

import argparse
import csv
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone

DOCS = os.environ.get('RAG_DOCUMENTS', '/home/tlandskron/documents')
STATE = os.environ.get('RAG_STATE', '/home/tlandskron/rag-state')
CONTAINER = 'open-webui'
ADMIN = os.environ.get('RAG_ADMIN_EMAIL', 'admin@example.com')
HERE = os.path.dirname(os.path.abspath(__file__))
UPLOADER = os.path.join(HERE, 'owui_upload.py')

MANIFEST = 'manifest.csv'
LOG = 'ingest.log'
COLS = [
    'sha256', 'bytes', 'origem', 'tipo', 'ano',
    'knowledge_id', 'file_id', 'ingerido_em', 'duracao_s', 'estado',
]

# Uma base por concurso (§9). O slug é a pasta em concurso/; a chave é o nome da base.
BASES = {'tiradentes-bm': 'Tiradentes BM'}
BASE_DEFAULT = 'Tiradentes BM'
SLUG_DEFAULT = 'tiradentes-bm'

SUFIXOS = {'.pdf', '.docx', '.txt', '.md'}
TIPOS = ('edital', 'prova', 'gabarito', 'resumo')
IGNORAR = {'leia-me.txt'}

MIN_IDADE = 30  # s: arquivo mais novo que isso ainda está sendo copiado (§6.3)


class Falha(Exception):
    """Erro de um arquivo só: vira linha `falhou` + cópia em _rejeitados/."""


def agora():
    # Horário LOCAL com offset (2026-10-22T10:47:57-03:00): o relatório é lido no
    # Explorer pelo dono do lab, e um "13:47Z" não bate com o relógio da parede.
    # O offset mantém o instante sem ambiguidade para comparar com log de container.
    return datetime.now().astimezone().replace(microsecond=0).isoformat()


DRY = False  # --dry-run: nada é escrito (nem o log) — o script é somente leitura


def log(msg, stream=True):
    linha = f'{agora()}  {msg}'
    if stream:
        print(linha, flush=True)
    if DRY:
        return
    try:
        os.makedirs(STATE, exist_ok=True)
        with open(os.path.join(STATE, LOG), 'a', encoding='utf-8') as fh:
            fh.write(linha + '\n')
    except OSError as exc:
        print(f'  aviso: não consegui escrever o log em {STATE}: {exc}', file=sys.stderr)


# --------------------------------------------------------------------------- #
# manifest
# --------------------------------------------------------------------------- #
def carregar_manifest():
    path = os.path.join(STATE, MANIFEST)
    if not os.path.exists(path):
        return []
    with open(path, newline='', encoding='utf-8-sig') as fh:
        return [{k: (row.get(k) or '') for k in COLS} for row in csv.DictReader(fh)]


def gravar_manifest(rows):
    os.makedirs(STATE, exist_ok=True)
    path = os.path.join(STATE, MANIFEST)
    tmp = path + '.tmp'
    with open(tmp, 'w', newline='', encoding='utf-8') as fh:
        w = csv.DictWriter(fh, fieldnames=COLS, lineterminator='\n')
        w.writeheader()
        for row in rows:
            w.writerow({k: row.get(k, '') for k in COLS})
    os.replace(tmp, path)


def estado_por_sha(rows, sha):
    """Estado da linha mais recente daquele conteúdo (o manifest é histórico)."""
    for row in reversed(rows):
        if row['sha256'] == sha:
            return row['estado']
    return ''


def ok_por_origem(rows, origem):
    for row in reversed(rows):
        if row['origem'] == origem and row['estado'] == 'ok':
            return row
    return None


# --------------------------------------------------------------------------- #
# varredura
# --------------------------------------------------------------------------- #
def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as fh:
        for bloco in iter(lambda: fh.read(1 << 20), b''):
            h.update(bloco)
    return h.hexdigest()


def candidatos(docs):
    """Caminhos relativos (com `/`) dos documentos que o worker considera."""
    achados = []
    for raiz, dirs, files in os.walk(docs):
        dirs[:] = sorted(d for d in dirs if not d.startswith(('_', '.')))
        for nome in sorted(files):
            if nome.startswith(('_', '.')) or nome.lower() in IGNORAR:
                continue
            if os.path.splitext(nome)[1].lower() not in SUFIXOS:
                continue
            full = os.path.join(raiz, nome)
            rel = os.path.relpath(full, docs).replace(os.sep, '/')
            achados.append(rel)
    return achados


def classificar(rel):
    """(slug, base, ano, tipo) a partir do caminho relativo."""
    partes = rel.split('/')
    nome = partes[-1]
    stem = os.path.splitext(nome)[0].lower()

    slug, base, prefixo = SLUG_DEFAULT, BASE_DEFAULT, ''
    if partes[0] == 'concurso' and len(partes) >= 3:
        slug = partes[1]
        base = BASES.get(slug, slug.replace('-', ' ').title())
    elif partes[0] == 'referencias' and len(partes) >= 3:
        slug = partes[1]
        base = BASES.get(slug, slug.replace('-', ' ').title())
    elif partes[0] in ('referencias', 'incoming'):
        prefixo = partes[0]  # triagem: sem concurso no caminho -> base default

    ano = ''
    for p in partes[:-1]:
        if re.fullmatch(r'\d{4}', p):
            ano = p
            break
    if not ano:
        m = re.search(r'(?<!\d)(\d{4})(?!\d)', stem)
        ano = m.group(1) if m else ''

    tokens = [t for t in stem.split('-') if t]
    tipo = tokens[0] if tokens and tokens[0] in TIPOS else 'doc'
    return slug, base, ano, tipo


def aviso_extracao(sufixo, chars, tamanho):
    """Vale avisar que a extração parece falha?

    PDF escaneado devolve quase nada de texto em relação ao tamanho do arquivo
    (é o caso do gabarito de 2022: 780 chars numa prova de 20 páginas). Já um
    .txt entrega ~1:1, então 190 chars de um arquivo de 239 bytes é o conteúdo
    inteiro (gabarito digitado) — avisar ali é alarme falso.
    """
    if chars >= 200:
        return ''
    if sufixo == '.pdf' or chars < 0.5 * max(tamanho, 1):
        return f'  aviso: só {chars} chars extraídos (escaneado? OCR falhou?)'
    return ''


def nome_achatado(rel, slug, ano, prefixo=''):
    """Nome que aparece na citação: <slug>-<ano>-<resto>.pdf (sem pasta, §18.6)."""
    partes = rel.split('/')
    stem = os.path.splitext(partes[-1])[0].lower()
    ext = os.path.splitext(partes[-1])[1].lower()
    tokens = [t for t in stem.split('-') if t and t != ano]

    limites = 60
    resto = '-'.join(tokens)[:limites]
    pedacos = [slug]
    if prefixo:
        pedacos.append(prefixo)
    if ano:
        pedacos.append(ano)
    if resto:
        pedacos.append(resto)
    return '-'.join(pedacos) + ext


# --------------------------------------------------------------------------- #
# container
# --------------------------------------------------------------------------- #
def preflight():
    """Falha cedo e com mensagem clara se o container não tem o share montado."""
    try:
        r = subprocess.run(
            ['docker', 'inspect', '-f', '{{range .Mounts}}{{.Source}}|{{.Destination}}|{{.RW}}\n{{end}}',
             CONTAINER],
            capture_output=True, text=True, timeout=60,
        )
    except FileNotFoundError:
        raise SystemExit('docker não encontrado neste host')
    if r.returncode != 0:
        raise SystemExit(f'container {CONTAINER} não está rodando: {r.stderr.strip()[:300]}')
    if f'{DOCS}|/documents|false' not in r.stdout:
        raise SystemExit(
            f'o container {CONTAINER} não tem {DOCS} montado em /documents:ro\n'
            '  rode: powershell -File ops\\deploy\\sync-to-host.ps1\n'
            '  e:    ssh davy-jones-hermes \'cd /home/tlandskron/hermes-architect && docker compose up -d open-webui\''
        )
    if not os.path.exists(UPLOADER):
        raise SystemExit(f'uploader ausente: {UPLOADER}')
    r = subprocess.run(
        ['docker', 'cp', UPLOADER, f'{CONTAINER}:/tmp/owui_upload.py'],
        capture_output=True, text=True, timeout=120,
    )
    if r.returncode != 0:
        raise SystemExit(f'docker cp do uploader falhou: {r.stderr.strip()[:300]}')


def _exec(args, timeout):
    return subprocess.run(
        ['docker', 'exec', CONTAINER, 'python', '/tmp/owui_upload.py'] + args,
        capture_output=True, text=True, timeout=timeout,
    )


def _resultado(saida):
    for linha in reversed(saida.splitlines()):
        if linha.startswith('RESULT '):
            try:
                return json.loads(linha[len('RESULT '):])
            except ValueError:
                break
    return None


def subir(rel, nome, base):
    """Roda o uploader no container e devolve o RESULT (dict). Levanta Falha."""
    caminho = f'/documents/{rel}'
    t0 = time.time()
    try:
        r = _exec(['--path', caminho, '--name', nome, '--kb', base, '--admin-email', ADMIN], 3700)
    except subprocess.TimeoutExpired:
        raise Falha('timeout do docker exec (Docling travou?)')
    out = _resultado(r.stdout)
    if r.returncode != 0 or not out or not out.get('ok'):
        detalhe = (r.stdout or '') + (r.stderr or '')
        ultimas = ' / '.join(linha.strip() for linha in detalhe.strip().splitlines()[-3:])
        raise Falha(ultimas or f'exit {r.returncode} sem mensagem')
    out['duracao_s'] = round(time.time() - t0, 1)
    return out


def remover_do_owui(file_id):
    try:
        r = _exec(['--remove-file', file_id, '--admin-email', ADMIN], 1200)
    except subprocess.TimeoutExpired:
        raise Falha('timeout ao remover o arquivo do OWUI')
    out = _resultado(r.stdout)
    if r.returncode != 0 or not out or not out.get('removed'):
        detalhe = (r.stdout or '') + (r.stderr or '')
        ultimas = ' / '.join(linha.strip() for linha in detalhe.strip().splitlines()[-3:])
        raise Falha(ultimas or f'exit {r.returncode} sem mensagem')
    return out


# --------------------------------------------------------------------------- #
# rejeitados e relatório
# --------------------------------------------------------------------------- #
def rejeitar(docs, origem, nome, motivo):
    pasta = os.path.join(docs, '_rejeitados')
    os.makedirs(pasta, exist_ok=True)
    destino = os.path.join(pasta, nome)
    try:
        shutil.copy2(os.path.join(docs, origem), destino)
        with open(destino + '.motivo.txt', 'w', encoding='utf-8') as fh:
            fh.write(f'origem: {origem}\nquando: {agora()}\n\n{motivo}\n')
    except OSError as exc:
        log(f'  aviso: não consegui copiar {origem} para _rejeitados/: {exc}')


def relatorio(docs, rows, novos, repetidos, pendentes, falhas):
    pasta = os.path.join(docs, '_relatorio')
    os.makedirs(pasta, exist_ok=True)
    na_base = [r for r in rows if r['estado'] == 'ok']
    linhas = [
        '# Ingestão de documentos — última execução',
        '',
        f'- **Quando:** {agora()}',
        f'- **Documentos na base:** {len(na_base)}',
        f'- **Novos nesta execução:** {len(novos)}',
        f'- **Já ingeridos (mesmo SHA-256):** {len(repetidos)}',
        f'- **Aguardando (cópia recente, entram na próxima):** {len(pendentes)}',
        f'- **Falhas nesta execução:** {len(falhas)}',
        '',
    ]
    if falhas:
        linhas += ['## Falhas (copiadas para `_rejeitados/`)', '',
                   '| Arquivo | Motivo |', '|---|---|']
        for f in falhas:
            linhas.append(f'| `{f["nome"]}` | {f["motivo"].replace("|", "/")[:300]} |')
        linhas.append('')
    if pendentes:
        linhas += ['## Aguardando estabilizar', '',
                   '| Arquivo | Idade |', '|---|---|']
        for p in pendentes:
            linhas.append(f'| `{p["arquivo"]}` | {p["idade"]}s |')
        linhas.append('')
    if novos:
        linhas += ['## Ingeridos agora', '', '| Origem | Nome na citação | Vetores na base |', '|---|---|---|']
        for n in novos:
            linhas.append(f'| `{n["origem"]}` | `{n["nome"]}` | {n["points"]} |')
        linhas.append('')
    linhas += [
        '## Como remover um documento',
        '',
        'Apagar é decisão sua, nunca do processo:',
        '',
        '```',
        'python3 /home/tlandskron/hermes-architect/tools/rag_ingest.py --remover <sha256>',
        '```',
        '',
        'O SHA-256 de cada documento está em `~/rag-state/manifest.csv`.',
        '',
    ]
    with open(os.path.join(pasta, 'INGESTAO.md'), 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(linhas))


# --------------------------------------------------------------------------- #
# métricas (Fase 4) — o worker publica o próprio estado no textfile do
# node-exporter (`hermes_rag_*`). É o que o Prometheus/Grafana leem e o que o
# alerta de "pendente > 24 h" olha. Escrita atômica (tmp + replace) para o
# scraper nunca ler um arquivo pela metade.
# --------------------------------------------------------------------------- #
METRICS = os.environ.get(
    'RAG_METRICS', '/home/tlandskron/hermes-architect/ci/textfile/hermes_rag.prom')


def documentos_na_base(rows):
    return len([r for r in rows if r['estado'] == 'ok'])


def falhas_ativas(rows):
    """SHAs cujo estado ATUAL é `falhou` (o manifest é histórico: retry vira `ok`)."""
    shas = {r['sha256'] for r in rows if r['estado'] == 'falhou'}
    return len([s for s in shas if estado_por_sha(rows, s) == 'falhou'])


def rejeitados(docs):
    pasta = os.path.join(docs, '_rejeitados')
    if not os.path.isdir(pasta):
        return 0
    return len([n for n in os.listdir(pasta) if not n.endswith('.motivo.txt')])


def pendentes(docs, rows, idade_min=3600):
    """Arquivos no share há mais de 1 h que NÃO estão na base (por SHA-256).

    É o que o alerta de 24 h olha: documento que você colocou e nunca entrou.
    Cópia recém-caída (< 1 h) não conta — ela entra na execução seguinte.
    """
    idades = []
    agora_ts = time.time()
    for rel in candidatos(docs):
        full = os.path.join(docs, rel)
        try:
            idade = agora_ts - os.stat(full).st_mtime
            if idade < idade_min:
                continue
            if estado_por_sha(rows, sha256(full)) == 'ok':
                continue
        except OSError:
            continue
        idades.append(int(idade))
    return idades


def gravar_metricas(docs, rows, inicio, sucesso, aguardando=0, path=None):
    """Publica hermes_rag_* no textfile do node-exporter."""
    destino = path or METRICS
    pends = pendentes(docs, rows)
    valores = [
        ('hermes_rag_documentos_total',
         'Documentos com estado ok no manifest (na base do OWUI)',
         documentos_na_base(rows)),
        ('hermes_rag_falhas_total',
         'Conteudos cujo estado atual e falhou (so entram com --retentar)',
         falhas_ativas(rows)),
        ('hermes_rag_rejeitados_total',
         'Arquivos copiados para _rejeitados/ com o motivo',
         rejeitados(docs)),
        ('hermes_rag_aguardando_total',
         'Arquivos pulados nesta execucao por copia recente (< min-idade)',
         aguardando),
        ('hermes_rag_pendentes_total',
         'Arquivos no share ha mais de 1 h que nao estao na base',
         len(pends)),
        ('hermes_rag_pendente_mais_antigo_segundos',
         'Idade do pendente mais antigo em segundos (0 = nada pendente)',
         max(pends) if pends else 0),
        ('hermes_rag_ultima_execucao_timestamp_seconds',
         'Epoch da ultima execucao do worker', int(time.time())),
        ('hermes_rag_ultima_execucao_sucesso',
         '1 = ultima execucao sem falhas; 0 = com falhas', 1 if sucesso else 0),
        ('hermes_rag_ultima_execucao_duracao_segundos',
         'Duracao da ultima execucao em segundos',
         round(time.time() - inicio, 2)),
    ]
    pasta = os.path.dirname(destino)
    if pasta:
        os.makedirs(pasta, exist_ok=True)
    tmp = destino + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as fh:
        for nome, ajuda, valor in valores:
            fh.write(f'# HELP {nome} {ajuda}\n# TYPE {nome} gauge\n{nome} {valor}\n')
    os.chmod(tmp, 0o644)
    os.replace(tmp, destino)


# --------------------------------------------------------------------------- #
# comandos
# --------------------------------------------------------------------------- #
def cmd_remover(rows, alvo, dry, inicio=None):
    # `substituido` também é removível: é a versão antiga que ficou na base (antes da
    # substituição automática, ou quando a remoção automática falhou). Antes o comando
    # recusava justamente a linha que se quer limpar.
    pode = ('ok', 'substituido')
    exatos = [r for r in rows if r['sha256'] == alvo and r['estado'] in pode]
    achados = exatos or [r for r in rows if r['sha256'].startswith(alvo) and r['estado'] in pode]
    if not achados:
        print(f'nenhum documento na base para sha256 "{alvo}" (estados ok/substituido)', file=sys.stderr)
        return 1
    if len(achados) > 1:
        print(f'"{alvo}" casa com {len(achados)} documentos — use o sha256 inteiro:', file=sys.stderr)
        for r in achados:
            print(f'  {r["sha256"]}  {r["origem"]}', file=sys.stderr)
        return 1
    row = achados[0]
    if dry:
        print(f'DRY-RUN: removeria {row["origem"]} ({row["sha256"][:12]}…) file_id {row["file_id"]}')
        return 0
    preflight()
    try:
        remover_do_owui(row['file_id'])
    except Falha as exc:
        log(f'[remover] {row["origem"]}: FALHOU — {exc}')
        return 1
    row['estado'] = 'removido'
    gravar_manifest(rows)
    log(f'[remover] {row["origem"]} removido da base (file_id {row["file_id"]})')
    try:
        gravar_metricas(DOCS, rows, inicio or time.time(), sucesso=True)
    except OSError as exc:
        log(f'[aviso] métricas não publicadas ({METRICS}): {exc}')
    return 0


def main():
    global DOCS, STATE, DRY
    p = argparse.ArgumentParser(description='Ingere o share de documentos na base do OWUI.')
    p.add_argument('--dry-run', action='store_true', help='mostra o que faria; não escreve nada')
    p.add_argument('--retentar', action='store_true', help='tenta de novo o que está em falhou')
    p.add_argument('--substituir', action='store_true',
                   help='obsoleto: substituir a versão antiga já é o padrão (mantido para scripts antigos)')
    p.add_argument('--remover', metavar='SHA256', help='remove um documento da base (explícito)')
    p.add_argument('--documents', default=DOCS, help=f'share de documentos (default {DOCS})')
    p.add_argument('--state', default=STATE, help=f'estado do worker (default {STATE})')
    p.add_argument('--min-idade', type=int, default=MIN_IDADE,
                   help=f'idade mínima do arquivo em segundos (default {MIN_IDADE})')
    args = p.parse_args()

    DOCS, STATE = args.documents, args.state
    DRY = args.dry_run
    inicio = time.time()
    rows = carregar_manifest()

    if args.remover:
        return cmd_remover(rows, args.remover, args.dry_run, inicio)

    if not os.path.isdir(DOCS):
        raise SystemExit(f'share não existe: {DOCS}')

    arquivos = candidatos(DOCS)
    if not args.dry_run:
        preflight()
        log(f'== execução: {len(arquivos)} documento(s) no share')

    novos, repetidos, pendentes, falhas, usados = [], [], [], [], {}
    agora_ts = time.time()

    for rel in arquivos:
        full = os.path.join(DOCS, rel)
        try:
            st = os.stat(full)
        except OSError as exc:
            log(f'[erro] {rel}: {exc}')
            continue
        idade = agora_ts - st.st_mtime
        if idade < args.min_idade:
            pendentes.append({'arquivo': rel, 'idade': int(idade)})
            log(f'[pendente] {rel}: mtime {int(idade)}s (< {args.min_idade}s, cópia em andamento)')
            continue

        try:
            sha = sha256(full)
        except OSError as exc:
            log(f'[erro] {rel}: não consegui ler ({exc})')
            continue

        estado = estado_por_sha(rows, sha)
        if estado == 'ok':
            repetidos.append(rel)
            continue
        if estado == 'falhou' and not args.retentar:
            falhas.append({'nome': os.path.basename(rel), 'origem': rel,
                           'motivo': 'já falhou numa execução anterior (use --retentar)'})
            log(f'[falhou-antes] {rel}: pulado (use --retentar)')
            continue

        partes = rel.split('/')
        prefixo = partes[0] if partes[0] in ('referencias', 'incoming') and len(partes) == 2 else ''
        slug, base, ano, tipo = classificar(rel)
        nome = nome_achatado(rel, slug, ano, prefixo)
        if nome in usados and usados[nome] != sha:
            nome = f'{os.path.splitext(nome)[0]}-{sha[:6]}{os.path.splitext(nome)[1]}'
        usados[nome] = sha

        if prefixo:
            log(f'[aviso] {rel}: sem pasta de concurso — entra na base default "{base}"')

        antiga = ok_por_origem(rows, rel)
        nova_versao = bool(antiga and antiga['sha256'] != sha)
        if nova_versao:
            log(f'[substituido] {rel}: conteúdo novo (sha {sha[:12]}…); versão antiga '
                f'{antiga["sha256"][:12]}… sai da base')

        if args.dry_run:
            acao = 'substituiria' if nova_versao else 'subiria'
            print(f'DRY-RUN: {acao} {rel} -> {nome} (base "{base}", {st.st_size} bytes)')
            novos.append({'origem': rel, 'nome': nome, 'points': '-'})
            continue

        try:
            out = subir(rel, nome, base)
        except Falha as exc:
            motivo = str(exc)
            log(f'[falhou] {rel}: {motivo}')
            rejeitar(DOCS, rel, nome, motivo)
            falhas.append({'nome': nome, 'origem': rel, 'motivo': motivo})
            rows.append({
                'sha256': sha, 'bytes': str(st.st_size), 'origem': rel, 'tipo': tipo,
                'ano': ano, 'knowledge_id': '', 'file_id': '', 'ingerido_em': agora(),
                'duracao_s': '', 'estado': 'falhou',
            })
            continue

        rows.append({
            'sha256': sha,
            'bytes': str(st.st_size),
            'origem': rel,
            'tipo': tipo,
            'ano': ano,
            'knowledge_id': out['knowledge_id'],
            'file_id': out['file_id'],
            'ingerido_em': agora(),
            'duracao_s': str(out['duracao_s']),
            'estado': 'ok',
        })
        # A nova versão JÁ subiu: editar o arquivo no share é ATUALIZAR o documento,
        # não criar outro — sem isto a base fica com as duas versões e o RAG pode
        # citar justamente a resposta que você corrigiu. Removemos depois de subir,
        # de propósito: se a remoção falhar, a versão boa está garantida e o log diz
        # o comando exato para limpar à mão.
        if nova_versao and antiga['file_id']:
            try:
                remover_do_owui(antiga['file_id'])
                antiga['estado'] = 'substituido'
            except Falha as exc:
                log(f'[aviso] não consegui remover a versão antiga de {rel}: {exc}')
                log(f'        remova à mão: rag-ingest --remover {antiga["sha256"]}')
        novos.append({'origem': rel, 'nome': nome, 'points': out.get('points', 0)})
        aviso = aviso_extracao(os.path.splitext(rel)[1].lower(), out.get('chars', 0),
                               st.st_size)
        log(f'[novo] {rel} -> {nome} (base "{base}", {out.get("points", 0)} vetores, '
            f'{out["duracao_s"]}s, {out.get("chars", 0)} chars){aviso}')

    if not args.dry_run:
        gravar_manifest(rows)
        relatorio(DOCS, rows, novos, repetidos, pendentes, falhas)
        # Fase 4: publica o estado no textfile DEPOIS de gravar o manifest (o
        # documentos_total tem de refletir o que acabou de entrar na base).
        try:
            gravar_metricas(DOCS, rows, inicio, sucesso=not falhas,
                            aguardando=len(pendentes))
        except OSError as exc:
            log(f'[aviso] métricas não publicadas ({METRICS}): {exc}')
        log(f'== resumo: {len(novos)} novo(s), {len(repetidos)} já ingerido(s), '
            f'{len(pendentes)} aguardando, {len(falhas)} falha(s)')
        log(f'== relatório: {os.path.join(DOCS, "_relatorio", "INGESTAO.md")}')
    else:
        print(f'DRY-RUN: {len(novos)} seria(m) ingerido(s), {len(repetidos)} já ingerido(s), '
              f'{len(pendentes)} aguardando, {len(falhas)} em falha — nada foi escrito')

    if falhas:
        print(f'\n{len(falhas)} falha(s) — veja _rejeitados/ e '
              f'{os.path.join(STATE, LOG)}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
