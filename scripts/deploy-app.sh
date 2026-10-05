#!/usr/bin/env bash
# Publica app/ en el Function App (Flex Consumption, privado) con OneDeploy y
# build remoto, y lista las funciones que el host indexo.
#
# El Function App tiene publicNetworkAccess = Disabled y el SCM queda detras
# de la misma regla, asi que el acceso publico se abre solo durante el deploy
# y se cierra siempre al salir (trap), incluso si algo falla.
#
# Uso: scripts/deploy-app.sh [function-app-name] [resource-group]
set -euo pipefail

APP="${1:-func-jalcalaroot-agent}"
RG="${2:-jalcalaroot}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZIP="$(mktemp --suffix=.zip)"
SUB="$(az account show --query id -o tsv)"
SITE="https://management.azure.com/subscriptions/${SUB}/resourceGroups/${RG}/providers/Microsoft.Web/sites/${APP}?api-version=2025-03-01"
SCM="https://${APP}.scm.azurewebsites.net"

set_public_access() {
  az rest --method patch --url "$SITE" --body "{\"properties\":{\"publicNetworkAccess\":\"$1\"}}" \
    --query properties.publicNetworkAccess -o tsv
}
token() { az account get-access-token --resource https://management.azure.com --query accessToken -o tsv; }

trap 'echo "cerrando acceso publico..."; set_public_access Disabled >/dev/null; rm -f "$ZIP"' EXIT

(cd "$ROOT/app" && zip -qr "$ZIP" . -x "tests/*" ".venv/*" "__pycache__/*" "*/__pycache__/*" "*.pyc" ".pytest_cache/*" "requirements-dev.txt")

echo "acceso publico: $(set_public_access Enabled)"
# La API del SCM tarda un momento en aceptar conexiones tras abrir el acceso.
sleep 20

# Flex Consumption: az functionapp deploy --type zip da 415; OneDeploy exige application/zip.
ID="$(curl -sS -X POST "$SCM/api/publish?RemoteBuild=true" -H "Authorization: Bearer $(token)" \
  -H "Content-Type: application/zip" --data-binary "@$ZIP" --max-time 600 | tr -d '"')"
echo "deployment: $ID"

while true; do
  STATUS="$(curl -sS -H "Authorization: Bearer $(token)" "$SCM/api/deployments/$ID" --max-time 30 |
    python3 -c 'import sys,json; print(json.load(sys.stdin).get("status"))')"
  echo "status: $STATUS"
  case "$STATUS" in 4) break ;; 3) echo "deployment FALLO"; exit 1 ;; esac
  sleep 15
done

sleep 20
KEY="$(az functionapp keys list -g "$RG" -n "$APP" --query masterKey -o tsv)"
echo "funciones indexadas:"
curl -sS -m 60 "https://${APP}.azurewebsites.net/admin/functions?code=${KEY}" |
  python3 -c 'import sys,json; print(sorted(f["name"] for f in json.load(sys.stdin)))'
