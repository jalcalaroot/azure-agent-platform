from .clients import openai_client, settings

BATCH_SIZE = 16


def embed_texts(texts: list[str]) -> list[list[float]]:
    vectors: list[list[float]] = []
    for start in range(0, len(texts), BATCH_SIZE):
        batch = texts[start : start + BATCH_SIZE]
        response = openai_client().embeddings.create(
            model=settings().embedding_deployment, input=batch
        )
        vectors.extend(item.embedding for item in sorted(response.data, key=lambda d: d.index))
    return vectors
