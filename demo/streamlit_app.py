"""Demo de Policy Hub: pregunta -> respuesta + los chunks que la sustentan.

Uso:
    export GATEWAY_URL="$(terraform output -raw api_base_url)"
    streamlit run demo/streamlit_app.py

El token sale de DefaultAzureCredential (az login). El scope es el de la App
Registration: api://policy-hub/.default.
"""

import os

import requests
import streamlit as st
from azure.identity import DefaultAzureCredential

GATEWAY_URL = os.environ["GATEWAY_URL"].rstrip("/")
SCOPE = os.environ.get("API_SCOPE", "api://policy-hub/.default")

st.title("Policy Hub — RAG Demo")
st.caption(f"Gateway: {GATEWAY_URL}")

question = st.text_input("Preguntá algo sobre los repos de infraestructura:")

if st.button("Preguntar") and question:
    token = DefaultAzureCredential().get_token(SCOPE).token
    response = requests.post(
        f"{GATEWAY_URL}/ask",
        headers={"Authorization": f"Bearer {token}"},
        json={"question": question},
        timeout=60,
    )
    if response.status_code == 400:
        st.error(f"Bloqueado por Content Safety: {response.json()['detail']['blocked']}")
    elif not response.ok:
        st.error(f"Error {response.status_code}: {response.text}")
    else:
        body = response.json()
        st.write(body["answer"])
        left, right = st.columns(2)
        left.metric("Latencia", f"{body['latency_ms']} ms")
        right.metric("Caché semántica", "hit" if body["cache_hit"] else "miss")
        with st.expander("Chunks usados"):
            st.json(body.get("sources", []))
