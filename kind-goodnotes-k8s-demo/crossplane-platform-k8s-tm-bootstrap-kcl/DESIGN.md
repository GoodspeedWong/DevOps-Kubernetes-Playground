# XTMBootstrap KCL Composition Design

This document records the KCL-based alternative Composition for the existing `XTMBootstrap` API.

## Purpose

This variant preserves the existing `XTMBootstrap` ownership boundary while replacing the repeated
`function-patch-and-transform` resource templates with a single `function-kcl` render step.

It still manages the same TM bootstrap shape:

- four namespaces: `tm-system`, `tm-core`, `tm-monitoring`, `tm-webhook`
- one same-name `ServiceAccount` in each namespace
- one `ClusterRoleBinding` for `tm-system/tm-system`

## Why a KCL variant

The original Composition is correct but repetitive. The resource generation logic is highly regular:

- four namespace objects share the same structure
- four service account objects share the same structure
- all nine objects share the same provider config, management policies, and environment labels

KCL is a better fit for this pattern because it can:

- define the namespace list once
- generate namespace and service-account objects with comprehensions
- keep the single RBAC exception explicit
- reduce repeated patch boilerplate

## Ownership and lifecycle

This KCL variant keeps the same owner-style boundary as the original API.

The KCL function generates `Object.kubernetes.crossplane.io` wrappers, not raw Kubernetes resources
directly. Those wrappers reconcile the final `Namespace`, `ServiceAccount`, and `ClusterRoleBinding`
manifests into the target cluster.

Like the current TM bootstrap Composition, the generated `Object` resources use:

- `managementPolicies`: `Observe`, `Create`, `Update`
- no `Delete` in management policies

That means the KCL variant is non-destructive by default and will not ask provider-kubernetes to
delete the underlying TM resources.

## Interface compatibility

This variant reuses the existing `XTMBootstrap` XRD and keeps the same core XR parameters:

- `spec.parameters.environment`
- `spec.parameters.systemClusterRoleName`

The current KCL implementation intentionally fixes these defaults instead of reading optional XR
overrides:

- `providerConfigRef.name = crossplane-local`
- `deletionPolicy = Delete`

The only operational difference is selection: when both the original and KCL Compositions exist,
instances should use `spec.crossplane.compositionRef.name` to pin the KCL version explicitly.

## Current tradeoff

To keep the KCL source concise and low-risk, this alternative focuses on deterministic resource
generation. It intentionally leaves two parity items for a future iteration:

- XR status backfill fields
- optional XR overrides for `providerConfigRef.name` and `deletionPolicy`
