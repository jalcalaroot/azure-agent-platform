"""Acceso a Cosmos DB: base de conocimiento vectorial, cache semantica y log.

Los containers knowledge_base y semantic_cache tienen indice vectorial sobre
/embedding (cosine). VectorDistance con cosine devuelve similitud: mas alto
es mas parecido, y ORDER BY VectorDistance ya ordena de mas a menos similar.
"""

import datetime
import hashlib
import uuid

from .clients import container

KNOWLEDGE_BASE = "knowledge_base"
SEMANTIC_CACHE = "semantic_cache"
REQUESTS = "requests"

_VECTOR_QUERY = (
    "SELECT TOP @k c.id, c.repo, c.source_url, c.chunk_index, c.content, "
    "VectorDistance(c.embedding, @embedding) AS score "
    "FROM c ORDER BY VectorDistance(c.embedding, @embedding)"
)


def _now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def upsert_chunks(chunks: list[dict]) -> int:
    kb = container(KNOWLEDGE_BASE)
    for chunk in chunks:
        kb.upsert_item(chunk)
    return len(chunks)


def delete_stale_chunks(repo: str, keep: int) -> int:
    """Borra los chunks de un repo con indice >= keep (el README se achico)."""
    kb = container(KNOWLEDGE_BASE)
    stale = list(
        kb.query_items(
            "SELECT c.id FROM c WHERE c.repo = @repo AND c.chunk_index >= @keep",
            parameters=[{"name": "@repo", "value": repo}, {"name": "@keep", "value": keep}],
            enable_cross_partition_query=True,
        )
    )
    for item in stale:
        kb.delete_item(item=item["id"], partition_key=item["id"])
    return len(stale)


def vector_search(embedding: list[float], k: int) -> list[dict]:
    return list(
        container(KNOWLEDGE_BASE).query_items(
            _VECTOR_QUERY,
            parameters=[{"name": "@k", "value": k}, {"name": "@embedding", "value": embedding}],
            enable_cross_partition_query=True,
        )
    )


def cache_lookup(embedding: list[float], threshold: float) -> dict | None:
    rows = list(
        container(SEMANTIC_CACHE).query_items(
            "SELECT TOP 1 c.id, c.question, c.answer, c.sources, "
            "VectorDistance(c.embedding, @embedding) AS score "
            "FROM c ORDER BY VectorDistance(c.embedding, @embedding)",
            parameters=[{"name": "@embedding", "value": embedding}],
            enable_cross_partition_query=True,
        )
    )
    if rows and rows[0]["score"] >= threshold:
        return rows[0]
    return None


def cache_put(question: str, embedding: list[float], answer: str, sources: list[dict]) -> None:
    normalized = " ".join(question.lower().split())
    container(SEMANTIC_CACHE).upsert_item(
        {
            "id": hashlib.sha256(normalized.encode("utf-8")).hexdigest(),
            "question": question,
            "embedding": embedding,
            "answer": answer,
            "sources": sources,
            "created_at": _now(),
        }
    )


def log_request(record: dict) -> None:
    container(REQUESTS).upsert_item({"id": str(uuid.uuid4()), "ts": _now(), **record})
