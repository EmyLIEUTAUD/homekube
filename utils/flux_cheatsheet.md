# FluxCD Cheatsheet
## Synchronisation
### Repo Git
```bash
flux reconcile source git flux-system -n flux-system
```
### Kustomization
```bash
flux reconcile kustomization <kustomization>
```
## Get
### Helm Releases
```bash
flux get helmreleases -A
```
### Kustomizations
```bash
flux get kustomizations -A
```
### Git Sources
```bash
flux get sources git -A
```
