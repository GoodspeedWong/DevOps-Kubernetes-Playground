# Crossplane TM Bootstrap KCL Variant

This root provides a KCL-based alternative Composition for the existing `XTMBootstrap` API.

## What it reuses

- the same XRD: `XTMBootstrap`
- the same ownership boundary
- the same target cluster provider default: `crossplane-local`
- the same non-destructive `managementPolicies`: `Observe`, `Create`, `Update`

## What changes

Instead of defining nine repeated `base + patches` blocks, this version uses `function-kcl` to
generate:

- four namespace `Object` resources
- four service-account `Object` resources
- one `ClusterRoleBinding` `Object`

## Apply prerequisites

Install the provider and function packages first:

```sh
kubectl apply -k kind-goodnotes-k8s-demo/crossplane-managed-kind/provider
kubectl apply -k kind-goodnotes-k8s-demo/crossplane-managed-kind/local-cluster
kubectl apply -k kind-goodnotes-k8s-demo/crossplane-functions
```

Then apply this KCL variant:

```sh
kubectl apply -k kind-goodnotes-k8s-demo/crossplane-platform-k8s-tm-bootstrap-kcl
```

## Composition selection

This root intentionally reuses the existing `XTMBootstrap` XRD. If the original patch-and-transform
Composition is also installed, pin the KCL variant explicitly:

```yaml
spec:
  crossplane:
    compositionRef:
      name: xtmbootstraps-kcl.platform.k8s.goodnotes.io
```

The example and instance in this root already do that.

## Current note

This KCL variant focuses on resource generation parity. It currently:

- reads `environment` and `systemClusterRoleName`
- fixes `providerConfigRef.name` to `crossplane-local`
- fixes `deletionPolicy` to `Delete`
- does not yet replicate the original Composition's XR status backfill fields
