"""Azure AI Content Safety via REST con la Managed Identity (sin keys).

- Prompt Shields (text:shieldPrompt): detecta ataques directos en la pregunta
  y tambien inyeccion INDIRECTA en los documentos recuperados - en RAG el
  contenido recuperado es no confiable.
- text:analyze: filtro de severidad sobre la respuesta generada.

Si Content Safety falla, la llamada propaga la excepcion: el sistema falla
cerrado en vez de responder sin guardrails.
"""

import httpx

from .clients import cognitive_token, settings

API_VERSION = "2024-09-01"
CATEGORIES = ["Hate", "SelfHarm", "Sexual", "Violence"]
MAX_DOCUMENTS = 5


class ContentBlocked(Exception):
    def __init__(self, reason: str):
        super().__init__(reason)
        self.reason = reason


def _post(path: str, payload: dict) -> dict:
    url = f"{settings().content_safety_endpoint.rstrip('/')}/contentsafety/{path}"
    response = httpx.post(
        url,
        params={"api-version": API_VERSION},
        json=payload,
        headers={"Authorization": f"Bearer {cognitive_token()}"},
        timeout=15,
    )
    response.raise_for_status()
    return response.json()


def shield_prompt(user_prompt: str, documents: list[str] | None = None) -> dict:
    data = _post(
        "text:shieldPrompt",
        {"userPrompt": user_prompt, "documents": (documents or [])[:MAX_DOCUMENTS]},
    )
    return {
        "user_attack": bool(data["userPromptAnalysis"]["attackDetected"]),
        "document_attacks": [bool(d["attackDetected"]) for d in data.get("documentsAnalysis", [])],
    }


def analyze_text(text: str) -> list[dict]:
    data = _post(
        "text:analyze",
        {"text": text[:10000], "categories": CATEGORIES, "outputType": "FourSeverityLevels"},
    )
    return data.get("categoriesAnalysis", [])


def is_unsafe(analysis: list[dict], threshold: int) -> bool:
    return any(item.get("severity", 0) >= threshold for item in analysis)
