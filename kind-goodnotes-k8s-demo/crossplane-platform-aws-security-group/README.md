# Crossplane AWS Shared Security Group

This root defines an owner-style Crossplane platform API for an AWS Security Group.

## Design boundary

This API intentionally models a shared security boundary, not a raw AWS EC2 primitive.

- Owner XR: `XSharedSecurityGroup`
- Managed resource: `SecurityGroup.ec2.aws.m.upbound.io`
- Ownership rule: this XR owns the Security Group lifecycle
- Non-goal: consumer teams editing the same shared Security Group or passing raw `vpcId`
- Managed resource namespace: `crossplane-system`

The API follows the platform design rule from the Crossplane skill:

- expose intent: `boundaryClass`, `networkRef`, `region`
- hide implementation: no `vpcId`, no `securityGroupId`, no ingress or egress rule fields

If application teams need access rules, model them in a separate consumer XR that creates
`SecurityGroupIngressRule` or `SecurityGroupEgressRule` resources against this owner-managed
group. Do not let multiple teams co-own the same Security Group object.

## Network dependency

`spec.parameters.networkRef.name` is mapped into a selector:

```yaml
spec:
  forProvider:
    vpcIdSelector:
      matchLabels:
        platform.aws.goodnotes.io/network: <networkRef.name>
```

That means the owner-managed VPC resource must carry the same label, for example:

```yaml
metadata:
  labels:
    platform.aws.goodnotes.io/network: shared-dev-network
```

This keeps the XR API reference-based and avoids leaking raw AWS IDs into the platform API.

## Apply API

```sh
kubectl apply -k kind-goodnotes-k8s-demo/crossplane-platform-aws-security-group
```

## Apply instances

For day-2 usage, manage SG instances under [`instances/`](./instances).

```sh
kubectl apply -k kind-goodnotes-k8s-demo/crossplane-platform-aws-security-group/instances
```

To add a new SG:

1. Copy one file from [`instances/`](./instances).
2. Change `metadata.name` and the values under `spec.parameters`.
3. Add the file to [`instances/kustomization.yaml`](./instances/kustomization.yaml).
4. Re-apply the instances root.

If you only want to create one SG ad hoc, you can still apply a single manifest directly:

```sh
kubectl apply -f kind-goodnotes-k8s-demo/crossplane-platform-aws-security-group/examples/shared-services-security-group.yaml
```
