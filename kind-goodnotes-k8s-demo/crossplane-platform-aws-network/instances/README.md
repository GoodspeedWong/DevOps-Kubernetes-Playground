# Network Instances

Put each owner-managed network instance in its own file in this directory.

## Add a new network

1. Copy an existing instance file.
2. Change `metadata.name`.
3. Adjust `networkClass`, `region`, `cidrBlock`, `publicSubnets`, and `privateSubnets`.
4. Add the new file to [kustomization.yaml](./kustomization.yaml).
5. Apply the instances root.

Field guide:

- `metadata.name`: logical network name; downstream consumer XRs should reference this through `networkRef.name`.
- `networkClass`: intent-level category for governance and policy.
- `cidrBlock`: VPC CIDR for the owner-managed network boundary.
- `publicSubnets`: public subnet topology patched into AWS Subnet resources.
- `privateSubnets`: private subnet topology patched into AWS Subnet resources.
- `region`: AWS region for the full network topology.
- `providerConfigRef.name`: optional AWS provider config override; omit it to use the Composition default.

Example:

```sh
kubectl apply -k kind-goodnotes-k8s-demo/crossplane-platform-aws-network/instances
```

## Notes

- `metadata.name` is exported as the stable `platform.aws.goodnotes.io/network` label.
- Consumers should reference this logical name instead of passing raw AWS IDs.
- NAT is intentionally not part of this API. If you need managed outbound egress for private subnets, add a separate owner API or extend this one with a deliberate topology review.
