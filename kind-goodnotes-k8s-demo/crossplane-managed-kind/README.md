## Goal

Use the current `kind-goodnotes-k8s-demo` cluster as the Crossplane management cluster, and a second Kind cluster named `crossplane-workload` as the managed workload cluster.

Crossplane does not create a Kind cluster from inside Kubernetes. The Kind cluster is created on the host with Docker, then registered into Crossplane with `provider-kubernetes`.

## 1. Create the workload Kind cluster

```sh
kind create cluster \
  --name crossplane-workload \
  --config goodnotes-k8s-demo/cluster-config-crossplane-workload.yaml
```

## 2. Store the child cluster kubeconfig for Crossplane

```sh
CHILD_APISERVER_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' crossplane-workload-control-plane)

kind get kubeconfig --name crossplane-workload \
  | sed -E "s#server: https://127.0.0.1:[0-9]+#server: https://${CHILD_APISERVER_IP}:6443#" \
  | kubectl --context kind-goodnotes-k8s-demo -n crossplane-system \
  create secret generic crossplane-workload-kubeconfig \
  --from-file=kubeconfig=/dev/stdin \
  --dry-run=client -o yaml | kubectl apply -f -
```

The default `kind get kubeconfig` output uses a host loopback endpoint such as `https://127.0.0.1:59749`.
That endpoint works on the host, but not from the `provider-kubernetes` Pod inside the management cluster, so the API server endpoint must be rewritten to the child Kind control-plane container IP.

## 3. Install the Crossplane Kubernetes provider

```sh
kubectl --context kind-goodnotes-k8s-demo apply -k \
  kind-goodnotes-k8s-demo/crossplane-managed-kind/provider

kubectl --context kind-goodnotes-k8s-demo wait \
  --for=condition=Healthy provider.pkg/provider-kubernetes \
  --timeout=180s
```

## 4. Register the workload cluster and push demo resources

```sh
kubectl --context kind-goodnotes-k8s-demo apply -k \
  kind-goodnotes-k8s-demo/crossplane-managed-kind/workload-cluster
```

## 5. Verify from the child cluster

```sh
kubectl --context kind-crossplane-workload get ns platform-demo
kubectl --context kind-crossplane-workload -n platform-demo get configmap platform-demo-settings -o yaml
```

## 6. Install the Crossplane Helm provider and a demo release

```sh
kubectl --context kind-goodnotes-k8s-demo apply -k \
  kind-goodnotes-k8s-demo/crossplane-managed-kind/provider

kubectl --context kind-goodnotes-k8s-demo wait \
  --for=condition=Healthy provider.pkg/provider-helm \
  --timeout=180s

kubectl --context kind-goodnotes-k8s-demo apply -k \
  kind-goodnotes-k8s-demo/crossplane-managed-kind/helm-workload
```

## 7. Verify the Helm release from the child cluster

```sh
kubectl --context kind-crossplane-workload get ns helm-demo
kubectl --context kind-crossplane-workload -n helm-demo get deploy,pods,svc
```

## Notes

- `provider-kubernetes` is pinned to `v1.2.1`.
- `provider-helm` is pinned to `v1.0.4`.
- The manifests in `workload-cluster/` prove that Crossplane can reconcile Kubernetes objects into the child Kind cluster.
- The manifests in `helm-workload/` prove that Crossplane can install and manage a Helm release in the child Kind cluster.
- The demo Helm release uses `bitnami/nginx` chart `22.4.2` with `replicaCount: 0`. This keeps the reconciliation path green even when the child Kind nodes cannot pull external images because of the local proxy configuration.

## Useful CLI commands

The installed CLI is `crossplane` and the current major commands are `resource` and `cluster`.
This CLI version does not use the older `crossplane beta ...` entrypoint.

```sh
crossplane version

crossplane resource trace \
  provider.pkg.crossplane.io/provider-kubernetes \
  --context kind-goodnotes-k8s-demo \
  -o wide

crossplane resource trace \
  object.kubernetes.crossplane.io/crossplane-workload-platform-demo-namespace \
  --context kind-goodnotes-k8s-demo \
  -o wide

crossplane resource trace \
  release.helm.crossplane.io/crossplane-workload-nginx \
  --context kind-goodnotes-k8s-demo \
  -o wide

crossplane cluster top
```

Expected current results:

- `crossplane version` reports `Client Version: v2.3.0` and `Server Version: v2.2.1`
- tracing `provider-kubernetes` shows the active `ProviderRevision`
- tracing `crossplane-workload-platform-demo-namespace` shows `SYNCED=True` and `READY=True`
- tracing `crossplane-workload-nginx` shows `SYNCED=True` and `READY=True`
- `crossplane cluster top` returns CPU and memory for the `crossplane`, `crossplane-rbac-manager`, and `provider-kubernetes` pods
