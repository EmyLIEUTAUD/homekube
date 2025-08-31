# homekube
Infra perso

# Installation
## Cilium
```
helm repo add cilium https://helm.cilium.io/
helm repo update

helm install cilium cilium/cilium \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set operator.replicas=1 \
  --set operator.rollOutPods=true \
  --set rollOutCiliumPods=true
```

## FluxCD
```bash
export GITHUB_TOKEN=<your-token>
export GITHUB_USER=<your-username>

flux bootstrap github \
  --owner=$GITHUB_USER \
  --repository=homekube \
  --branch=main \
  --path=./k3s/flux \
  --personal
```
