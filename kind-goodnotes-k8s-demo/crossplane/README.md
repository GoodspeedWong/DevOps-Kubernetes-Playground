## Installation

```sh
helm repo add crossplane-stable https://charts.crossplane.io/stable

helm template crossplane crossplane-stable/crossplane \
  --version 2.2.1 \
  --namespace crossplane-system \
  --include-crds \
  -f values.yaml > manifest.yaml

kubectl apply -k kind-goodnotes-k8s-demo/namespaces
kubectl apply -k kind-goodnotes-k8s-demo/crossplane
```

## Verification

```sh
kubectl -n crossplane-system get pods
kubectl get crds | rg crossplane
```

## Notes

- `manifest.yaml` is rendered from the official Crossplane Helm chart and checked in for reproducible `kubectl diff -k` workflows.
- This baseline installs only Crossplane core. Providers, Functions, and Configurations should be layered on top as separate packages once the control plane is healthy.
