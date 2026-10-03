"""Clientes de Azure construidos una sola vez por worker.

Todo se autentica con la Managed Identity del Function App (sin keys):
DefaultAzureCredential toma AZURE_CLIENT_ID para elegir la identidad
asignada por el usuario.
"""

from functools import lru_cache

from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from openai import AzureOpenAI

from .config import Settings, load_settings

COGNITIVE_SCOPE = "https://cognitiveservices.azure.com/.default"


@lru_cache(maxsize=1)
def settings() -> Settings:
    return load_settings()


@lru_cache(maxsize=1)
def credential() -> DefaultAzureCredential:
    return DefaultAzureCredential(managed_identity_client_id=settings().client_id)


@lru_cache(maxsize=1)
def openai_client() -> AzureOpenAI:
    s = settings()
    return AzureOpenAI(
        azure_endpoint=s.openai_endpoint,
        api_version=s.openai_api_version,
        azure_ad_token_provider=get_bearer_token_provider(credential(), COGNITIVE_SCOPE),
    )


@lru_cache(maxsize=1)
def _cosmos_database():
    s = settings()
    client = CosmosClient(s.cosmos_endpoint, credential=credential())
    return client.get_database_client(s.cosmos_database)


def container(name: str):
    return _cosmos_database().get_container_client(name)


def cognitive_token() -> str:
    return credential().get_token(COGNITIVE_SCOPE).token
