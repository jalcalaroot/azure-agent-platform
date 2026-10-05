"""Chunking de Markdown: respeta los encabezados y empaqueta parrafos.

Cada chunk lleva el encabezado de su seccion como prefijo, asi un fragmento
suelto (por ejemplo una fila de tabla) conserva el contexto de donde viene
cuando se recupera por similitud vectorial.
"""

import hashlib
import re

_HEADING = re.compile(r"^(#{1,6})\s+(.*)$")


def _sections(markdown: str) -> list[tuple[str, str]]:
    sections: list[tuple[str, list[str]]] = [("", [])]
    in_fence = False
    for line in markdown.splitlines():
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
        match = None if in_fence else _HEADING.match(line)
        if match:
            sections.append((match.group(2).strip(), []))
        else:
            sections[-1][1].append(line)
    return [(heading, "\n".join(lines).strip()) for heading, lines in sections]


def _split_long(paragraph: str, max_chars: int) -> list[str]:
    if len(paragraph) <= max_chars:
        return [paragraph]
    pieces, current = [], ""
    for line in paragraph.splitlines():
        while len(line) > max_chars:
            if current:
                pieces.append(current)
                current = ""
            pieces.append(line[:max_chars])
            line = line[max_chars:]
        candidate = f"{current}\n{line}" if current else line
        if len(candidate) > max_chars and current:
            pieces.append(current)
            current = line
        else:
            current = candidate
    if current:
        pieces.append(current)
    return pieces


def chunk_markdown(markdown: str, max_chars: int = 1200) -> list[dict]:
    chunks: list[dict] = []
    for heading, body in _sections(markdown):
        if not body:
            continue
        prefix = f"{heading}\n" if heading else ""
        budget = max(max_chars - len(prefix), 200)
        current = ""
        for paragraph in re.split(r"\n\s*\n", body):
            paragraph = paragraph.strip()
            if not paragraph:
                continue
            for piece in _split_long(paragraph, budget):
                candidate = f"{current}\n\n{piece}" if current else piece
                if len(candidate) > budget and current:
                    chunks.append(_make(prefix + current, len(chunks)))
                    current = piece
                else:
                    current = candidate
        if current:
            chunks.append(_make(prefix + current, len(chunks)))
    return chunks


def _make(text: str, index: int) -> dict:
    return {
        "chunk_index": index,
        "content": text,
        "content_hash": hashlib.sha256(text.encode("utf-8")).hexdigest(),
    }
