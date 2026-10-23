"""Gera um PDF de teste (2 páginas, texto ASCII) para validar a RAG jurídica.

Uso: python tools/make_test_pdf.py
Saída: tests/fixtures/contrato-teste.pdf
"""

from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / 'tests' / 'fixtures' / 'contrato-teste.pdf'

PAGES = [
    [
        'CONTRATO DE PRESTACAO DE SERVICOS ADVOCATICIOS',
        '',
        'Clausula 1a - OBJETO',
        'O escritorio prestara consultoria juridica e patrocinio em',
        'processos administrativos e judiciais.',
        '',
        'Clausula 2a - HONORARIOS',
        'Os honorarios mensais sao de R$ 3.500,00 (tres mil e quinhentos',
        'reais), pagos ate o dia 10 de cada mes.',
        '',
        'Clausula 3a - VIGENCIA',
        'O presente contrato tem vigencia de 24 (vinte e quatro) meses,',
        'renovavel automaticamente por igual periodo.',
    ],
    [
        'Clausula 4a - CONFIDENCIALIDADE',
        'As partes obrigam-se a manter sigilo sobre todas as informacoes',
        'do cliente, inclusive documentos e dados pessoais.',
        '',
        'Clausula 5a - RESCISAO',
        'A rescisao imotivada exige aviso previo de 30 (trinta) dias.',
        'A parte inadimplente pagara multa de 10% sobre o saldo devido.',
        '',
        'Clausula 6a - FORO',
        'Fica eleito o foro da Comarca de Sao Paulo/SP para dirimir',
        'eventuais controversias.',
        '',
        'Sao Paulo, 17 de outubro de 2026.',
    ],
]


def esc(text: str) -> str:
    return text.replace('\\', '\\\\').replace('(', '\\(').replace(')', '\\)')


def content_stream(lines):
    parts = ['BT', '/F1 12 Tf', '50 780 Td', '16 TL']
    for line in lines:
        parts.append(f'({esc(line)}) Tj')
        parts.append('T*')
    parts.append('ET')
    return '\n'.join(parts).encode('latin-1')


def build():
    objects = []  # 1-based
    objects.append(b'<< /Type /Catalog /Pages 2 0 R >>')

    page_ids = [3 + 2 * i for i in range(len(PAGES))]
    kids = ' '.join(f'{pid} 0 R' for pid in page_ids)
    objects.append(f'<< /Type /Pages /Kids [{kids}] /Count {len(PAGES)} >>'.encode())

    font_id = 3 + 2 * len(PAGES)

    for i, lines in enumerate(PAGES):
        stream = content_stream(lines)
        objects.append(
            (
                f'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
                f'/Resources << /Font << /F1 {font_id} 0 R >> >> '
                f'/Contents {page_ids[i] + 1} 0 R >>'
            ).encode()
        )
        objects.append(
            b'<< /Length ' + str(len(stream)).encode() + b' >>\nstream\n' + stream + b'\nendstream'
        )

    objects.append(b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>')

    out = bytearray(b'%PDF-1.4\n%\xe2\xe3\xcf\xd3\n')
    offsets = [0]
    for idx, obj in enumerate(objects, start=1):
        offsets.append(len(out))
        out += f'{idx} 0 obj\n'.encode() + obj + b'\nendobj\n'

    xref_pos = len(out)
    out += f'xref\n0 {len(objects) + 1}\n'.encode()
    out += b'0000000000 65535 f \n'
    for off in offsets[1:]:
        out += f'{off:010d} 00000 n \n'.encode()
    out += (
        f'trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref_pos}\n%%EOF\n'
    ).encode()

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(bytes(out))
    print(f'OK: {OUT} ({len(out)} bytes, {len(PAGES)} paginas)')


if __name__ == '__main__':
    build()
