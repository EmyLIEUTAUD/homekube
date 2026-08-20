#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="immich"
CLUSTER="immich-database"
SECRET="immich-database-app"
APP_DEPLOYMENTS=("immich-server" "immich-machine-learning")
declare -A ORIGINAL_REPLICAS=()
TOC_LIST=""

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

PGHOST=$(kubectl get secret "$SECRET" -n "$NAMESPACE" -o jsonpath='{.data.host}' | base64 --decode)
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
echo "Hôte       : $PGHOST"
echo "Base       : $PGDATABASE"
echo
echo "ATTENTION : la restauration utilise --clean et supprime les objets existants."
read -r -p "Immich sera arrêté pendant la restauration. Continuer ? [y/N] " confirmation

if [[ "$confirmation" != "y" && "$confirmation" != "Y" ]]; then
  echo "Restauration annulée."
  exit 0
fi

restart_immich() {
  for deployment in "${!ORIGINAL_REPLICAS[@]}"; do
    echo "Redémarrage de $deployment avec ${ORIGINAL_REPLICAS[$deployment]} replica(s)..."
    kubectl scale deployment "$deployment" -n "$NAMESPACE" \
      --replicas="${ORIGINAL_REPLICAS[$deployment]}" >/dev/null
  done
}

for deployment in "${APP_DEPLOYMENTS[@]}"; do
  if kubectl get deployment "$deployment" -n "$NAMESPACE" >/dev/null 2>&1; then
    ORIGINAL_REPLICAS[$deployment]=$(kubectl get deployment "$deployment" -n "$NAMESPACE" \
      -o jsonpath='{.spec.replicas}')
  fi
done

echo "Arrêt des composants Immich actifs..."
for deployment in "${!ORIGINAL_REPLICAS[@]}"; do
  if [[ "${ORIGINAL_REPLICAS[$deployment]}" != "0" ]]; then
    kubectl scale deployment "$deployment" -n "$NAMESPACE" --replicas=0 >/dev/null
  fi
done

TOC_LIST=$(mktemp)
REMOTE_DUMP="/var/lib/postgresql/data/immich-restore-$$.dump"
REMOTE_TOC_LIST="/var/lib/postgresql/data/immich-restore-$$.list"

cleanup_restore() {
  rm -f "$TOC_LIST"
  kubectl exec -n "$NAMESPACE" "$PRIMARY_POD" -- \
    rm -f "$REMOTE_DUMP" "$REMOTE_TOC_LIST" >/dev/null 2>&1 || true
  restart_immich
}

trap cleanup_restore EXIT

echo "Copie du dump dans le pod..."
kubectl cp "$DUMP_FILE" "$NAMESPACE/$PRIMARY_POD:$REMOTE_DUMP" -c postgres

echo "Analyse du dump..."
kubectl exec -n "$NAMESPACE" "$PRIMARY_POD" -c postgres -- \
  pg_restore --list "$REMOTE_DUMP" | sed '/EXTENSION/d' > "$TOC_LIST"

echo "Préparation de la restauration..."
kubectl exec -i -n "$NAMESPACE" "$PRIMARY_POD" -c postgres -- \
  sh -c "cat > '$REMOTE_TOC_LIST'" < "$TOC_LIST"

echo "Restauration en cours (mode verbeux)..."
kubectl exec -n "$NAMESPACE" "$PRIMARY_POD" -c postgres -- \
  env PGHOST="$PGHOST" PGPASSWORD="$PGPASSWORD" pg_restore \
    --username="$PGUSER" \
    --dbname="$PGDATABASE" \
    --clean \
    --if-exists \
    --no-owner \
    --no-acl \
    --use-list="$REMOTE_TOC_LIST" \
    --verbose \
    --exit-on-error \
    "$REMOTE_DUMP"

echo "Restauration terminée."