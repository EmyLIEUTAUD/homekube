#!/bin/bash

NAMESPACE=$1

if [ -z "$1" ]; then
  echo "Usage: sh $0 <nom-du-namespace>"
  exit 1
fi

(
  kubectl proxy & 
  kubectl get namespace $NAMESPACE -ojson |jq '.spec = {"finalizers":[]}' >temp.json
  curl -k -H "Content-Type: application/json" -X PUT --data-binary @temp.json 127.0.0.1:8001/api/v1/namespaces/$NAMESPACE/finalize
  rm -f temp.json
)
