import azure.functions as func

from api import app as fastapi_app
from ingestion import bp as ingestion_blueprint

# FastAPI corre dentro del host de Functions via ASGI (patron oficial de
# Microsoft); las rutas /ingest de Durable Functions son mas especificas que
# el catch-all del ASGI y ganan el routing.
app = func.AsgiFunctionApp(app=fastapi_app, http_auth_level=func.AuthLevel.ANONYMOUS)
app.register_functions(ingestion_blueprint)
