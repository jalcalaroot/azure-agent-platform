import os
from dataclasses import dataclass


def _env(name: str, default: str | None = None) -> str:
    value = os.environ.get(name, default)
    if value is None or value == "":
        raise RuntimeError(f"Missing required app setting: {name}")
    return value


@dataclass(frozen=True)
class Settings:
    client_id: str | None
    cosmos_endpoint: str
    cosmos_database: str
    openai_endpoint: str
    embedding_deployment: str
    chat_deployment: str
    content_safety_endpoint: str
    openai_api_version: str = "2024-10-21"
    top_k: int = 5
    cache_similarity_threshold: float = 0.92
    # Content Safety con outputType FourSeverityLevels devuelve 0/2/4/6;
    # >= 4 (medium) bloquea.
    severity_threshold: int = 4


def load_settings() -> Settings:
    return Settings(
        client_id=os.environ.get("AZURE_CLIENT_ID") or None,
        cosmos_endpoint=_env("COSMOS_ENDPOINT"),
        cosmos_database=_env("COSMOS_DATABASE", "policyhub"),
        openai_endpoint=_env("AZURE_OPENAI_ENDPOINT"),
        embedding_deployment=_env("EMBEDDING_DEPLOYMENT"),
        chat_deployment=_env("CHAT_DEPLOYMENT"),
        content_safety_endpoint=_env("CONTENT_SAFETY_ENDPOINT"),
        top_k=int(os.environ.get("TOP_K", "5")),
        cache_similarity_threshold=float(os.environ.get("CACHE_SIMILARITY_THRESHOLD", "0.92")),
        severity_threshold=int(os.environ.get("SEVERITY_THRESHOLD", "4")),
    )
