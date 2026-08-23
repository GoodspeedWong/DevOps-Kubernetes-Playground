# Crossplane TM Bootstrap

This root defines an owner-style Crossplane platform API for bootstrapping the fixed TM namespace
and identity boundary.

## Design boundary

This API models one TM control-plane bootstrap lifecycle:

- owner XR: `XTMBootstrap`
- managed resources:
  - `Namespace/tm-system`
  - `Namespace/tm-core`
  - `Namespace/tm-monitoring`
  - `Namespace/tm-webhook`
  - one ServiceAccount in each namespace
  - one `ClusterRoleBinding` for `tm-system/tm-system`
- referenced resource: an existing `ClusterRole` named by `spec.parameters.systemClusterRoleName`
- default target cluster provider config: `crossplane-local`
- management policy: `Observe`, `Create`, `Update`

This boundary is valid because the TM namespaces and their bootstrap identities are tightly coupled
and should be created and deleted as one unit.

`tm-system` gets cluster-scope access by binding its namespaced ServiceAccount to an existing
cluster role through a `ClusterRoleBinding`.

The Composition intentionally omits `Delete` from `managementPolicies`. That means Crossplane
reconciles and updates the TM bootstrap resources, but deleting the XR will not instruct
provider-kubernetes to delete the underlying namespaces, service accounts, or cluster role binding.

## Apply API

If you want the rendered objects to reconcile into the same cluster that runs Crossplane, apply the
provider and function packages first:

```sh
kubectl apply -k kind-goodnotes-k8s-demo/crossplane-managed-kind/provider
kubectl apply -k kind-goodnotes-k8s-demo/crossplane-managed-kind/local-cluster
kubectl apply -k kind-goodnotes-k8s-demo/crossplane-functions
```

Then apply the platform API:

```sh
kubectl apply -k kind-goodnotes-k8s-demo/crossplane-platform-k8s-tm-bootstrap
```

## Apply instances

For day-2 usage, manage owner instances under [`instances/`](./instances).

```sh
kubectl apply -k kind-goodnotes-k8s-demo/crossplane-platform-k8s-tm-bootstrap/instances
```

You can also apply a single example directly:

```sh
kubectl apply -f kind-goodnotes-k8s-demo/crossplane-platform-k8s-tm-bootstrap/examples/tm-bootstrap.yaml
```

## RBAC note

This Composition does not create the target `ClusterRole`. It only binds `tm-system/tm-system` to
an existing role such as `cluster-admin` or a custom least-privilege cluster role that you manage
separately.
