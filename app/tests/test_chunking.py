from rag.chunking import chunk_markdown

README = """# Proyecto

Intro corta.

## Recursos

| Recurso | Uso |
|---|---|
| VNet | Red |

## Uso

```bash
# esto no es un encabezado
terraform apply
```
"""


def test_headings_become_prefixes():
    chunks = chunk_markdown(README)
    texts = [c["content"] for c in chunks]
    assert any(t.startswith("Proyecto\nIntro corta.") for t in texts)
    assert any(t.startswith("Recursos\n") and "VNet" in t for t in texts)


def test_code_fence_comment_is_not_a_heading():
    chunks = chunk_markdown(README)
    uso = next(c["content"] for c in chunks if c["content"].startswith("Uso\n"))
    assert "# esto no es un encabezado" in uso


def test_indexes_are_sequential_and_hashes_stable():
    first = chunk_markdown(README)
    second = chunk_markdown(README)
    assert [c["chunk_index"] for c in first] == list(range(len(first)))
    assert [c["content_hash"] for c in first] == [c["content_hash"] for c in second]


def test_long_section_is_split_under_the_limit():
    body = "\n\n".join(f"Parrafo {i} " + "x" * 300 for i in range(20))
    chunks = chunk_markdown(f"# Largo\n\n{body}", max_chars=1000)
    assert len(chunks) > 1
    assert all(len(c["content"]) <= 1000 for c in chunks)


def test_empty_input_gives_no_chunks():
    assert chunk_markdown("") == []
