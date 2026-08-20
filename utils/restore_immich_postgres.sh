#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="immich"
CLUSTER="immich-database"
SECRET="immich-database-app"

usage() {
  echo "Usage: $0 <dump.dump>"
  echo
  echo "Restaure un dump pg_dump custom dans la base PostgreSQL d'Immich."
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

DUMP_FILE="$1"

if [[ ! -f "$DUMP_FILE" ]]; then
  echo "Erreur : fichier introuvable : $DUMP_FILE" >&2
  exit 1
fi

command -v kubectl >/dev/null || {
  echo "Erreur : kubectl est requis." >&2
  exit 1
}

PGUSER=$(kubectl get secret "$SECRET" -n "$NAMESPACE" -o jsonpath='{.data.user}' | base64 --decode)
PGDATABASE=$(kubectl get secret "$SECRET" -n "$NAMESPACE" -o jsonpath='{.data.dbname}' | base64 --decode)
PGPASSWORD=$(kubectl get secret "$SECRET" -n "$NAMESPACE" -o jsonpath='{.data.password}' | base64 --decode)
PRIMARY_POD=$(kubectl get pods -n "$NAMESPACE" \
  -l "cnpg.io/cluster=$CLUSTER,role=primary" \
  -o jsonpath='{.items[0].metadata.name}')

if [[ -z "$PRIMARY_POD" ]]; then
  echo "Erreur : aucun pod primaire trouvé pour le cluster $CLUSTER." >&2
  exit 1
fi

echo "Dump       : $DUMP_FILE"
echo "Pod primaire : $PRIMARY_POD"
echo "Base       : $PGDATABASE"
echo
echo "ATTENTION : la restauration utilise --clean et supprime les objets existants."
read -r -p "Immich est-il arrêté et veux-tu continuer ? [y/N] " confirmation

if [[ "$confirmation" != "y" && "$confirmation" != "Y" ]]; then
  echo "Restauration annulée."
  exit 0
fi

cat "$DUMP_FILE" | kubectl exec -i -n "$NAMESPACE" "$PRIMARY_POD" -- \
  env PGPASSWORD="$PGPASSWORD" pg_restore \
    --username="$PGUSER" \
    --dbname="$PGDATABASE" \
    --clean \
    --if-exists \
    --no-owner \
    --no-acl \
    --exit-on-error

echo "Restauration terminée."