import logging

import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from rag.pipeline import answer_question
from rag.safety import ContentBlocked

logger = logging.getLogger(__name__)

# La autenticacion (JWT de Entra ID) y el rate limiting los resuelve API
# Management delante de este app; el Function App solo es alcanzable por su
# Private Endpoint.
app = FastAPI(title="Policy Hub RAG")


class AskRequest(BaseModel):
    question: str = Field(min_length=1, max_length=2000)


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/ask")
def ask(request: AskRequest) -> dict:
    try:
        return answer_question(request.question)
    except ContentBlocked as blocked:
        raise HTTPException(status_code=400, detail={"blocked": blocked.reason})
    except httpx.HTTPError:
        logger.exception("Content Safety no disponible")
        raise HTTPException(status_code=503, detail="Guardrails no disponibles")
