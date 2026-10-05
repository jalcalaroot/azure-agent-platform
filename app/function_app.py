import azure.functions as func

from api import app as fastapi_app
from ingestion import bp as ingestion_blueprint

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)
app.register_functions(ingestion_blueprint)

_asgi = func.AsgiMiddleware(fastapi_app)


# FastAPI corre dentro del host de Functions via ASGI (patron oficial de
# Microsoft), pero con rutas explicitas por endpoint en vez de un catch-all
# ("/{*route}", que es lo que registra func.AsgiFunctionApp): en el host
# real el catch-all se trago las rutas /ingest de Durable Functions (FastAPI
# respondia 404 a POST /ingest), tanto con "/{*route}" como con "{*route}".
@app.function_name(name="ask")
@app.route(route="ask", methods=[func.HttpMethod.POST])
async def ask(req: func.HttpRequest, context: func.Context) -> func.HttpResponse:
    return await _asgi.handle_async(req, context)


@app.function_name(name="health")
@app.route(route="health", methods=[func.HttpMethod.GET])
async def health(req: func.HttpRequest, context: func.Context) -> func.HttpResponse:
    return await _asgi.handle_async(req, context)
