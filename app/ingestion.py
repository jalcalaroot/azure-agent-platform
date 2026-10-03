"""Pipeline de ingesta con Durable Functions.

README publico de un repo -> chunk_document -> generate_embeddings (fan-out
por lotes) -> store_in_cosmos. Es idempotente: el id de cada chunk es
determinista (<repo>-<indice>), asi que reingestar sobrescribe en vez de
duplicar, y se borran los chunks que sobran si el README se achico.

Backend de Durable: provider Azure Storage sobre la conexion AzureWebJobsStorage
del host (identidad administrada).
"""

import json
import logging

import azure.durable_functions as df
import azure.functions as func
import httpx

from rag import chunking, embeddings, store

logger = logging.getLogger(__name__)

bp = df.Blueprint()

GITHUB_OWNER = "jalcalaroot"
# jalcalaroot-azure-bootstrap es privado (el documento de requisitos lo
# listaba como publico) - se reemplaza por azure-agent-platform, publico.
DEFAULT_REPOS = [
    "azure-virtual-network",
    "azure-aks-cluster",
    "azure-container-apps",
    "azure-agent-platform",
]
EMBED_BATCH = 8


def readme_url(repo: str) -> str:
    return f"https://raw.githubusercontent.com/{GITHUB_OWNER}/{repo}/main/README.md"


@bp.route(route="ingest", methods=["POST"])
@bp.durable_client_input(client_name="client")
async def start_ingest(req: func.HttpRequest, client) -> func.HttpResponse:
    try:
        body = req.get_json() if req.get_body() else {}
    except ValueError:
        return func.HttpResponse("Invalid JSON", status_code=400)
    repos = body.get("repos") or DEFAULT_REPOS
    if not all(isinstance(r, str) and r.replace("-", "").replace("_", "").isalnum() for r in repos):
        return func.HttpResponse("Invalid repo name", status_code=400)
    instance_id = await client.start_new("ingest_all", None, {"repos": repos})
    return func.HttpResponse(
        json.dumps({"instance_id": instance_id, "status_path": f"/ingest/{instance_id}"}),
        status_code=202,
        mimetype="application/json",
    )


@bp.route(route="ingest/{instance_id}", methods=["GET"])
@bp.durable_client_input(client_name="client")
async def ingest_status(req: func.HttpRequest, client) -> func.HttpResponse:
    status = await client.get_status(req.route_params["instance_id"])
    if status is None or status.runtime_status is None:
        return func.HttpResponse("Not found", status_code=404)
    runtime = getattr(status.runtime_status, "name", str(status.runtime_status))
    return func.HttpResponse(
        json.dumps({"instance_id": status.instance_id, "runtime_status": runtime, "output": status.output}),
        mimetype="application/json",
    )


@bp.orchestration_trigger(context_name="context")
def ingest_all(context: df.DurableOrchestrationContext):
    repos = context.get_input()["repos"]
    results = yield context.task_all([context.call_sub_orchestrator("ingest_document", r) for r in repos])
    return {"documents": results, "chunks_stored": sum(r["chunks"] for r in results)}


@bp.orchestration_trigger(context_name="context")
def ingest_document(context: df.DurableOrchestrationContext):
    repo = context.get_input()
    chunks = yield context.call_activity("chunk_document", repo)
    batches = [chunks[i : i + EMBED_BATCH] for i in range(0, len(chunks), EMBED_BATCH)]
    embedded = yield context.task_all([context.call_activity("generate_embeddings", b) for b in batches])
    stored = yield context.call_activity(
        "store_in_cosmos", {"repo": repo, "chunks": [c for batch in embedded for c in batch]}
    )
    return {"repo": repo, "chunks": stored}


@bp.activity_trigger(input_name="repo")
def chunk_document(repo: str) -> list[dict]:
    url = readme_url(repo)
    response = httpx.get(url, timeout=30, follow_redirects=True)
    response.raise_for_status()
    chunks = chunking.chunk_markdown(response.text)
    source_url = f"https://github.com/{GITHUB_OWNER}/{repo}/blob/main/README.md"
    for chunk in chunks:
        chunk.update(
            {"id": f"{repo}-{chunk['chunk_index']:04d}", "repo": repo, "source_url": source_url}
        )
    return chunks


@bp.activity_trigger(input_name="chunks")
def generate_embeddings(chunks: list[dict]) -> list[dict]:
    vectors = embeddings.embed_texts([c["content"] for c in chunks])
    return [{**c, "embedding": v} for c, v in zip(chunks, vectors)]


@bp.activity_trigger(input_name="payload")
def store_in_cosmos(payload: dict) -> int:
    chunks = sorted(payload["chunks"], key=lambda c: c["chunk_index"])
    stored = store.upsert_chunks(chunks)
    removed = store.delete_stale_chunks(payload["repo"], len(chunks))
    logger.info("%s: %d chunks guardados, %d obsoletos borrados", payload["repo"], stored, removed)
    return stored
