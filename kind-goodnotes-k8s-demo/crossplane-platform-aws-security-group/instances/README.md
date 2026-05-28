# Shared Security Group Instances

Put each shared security group instance in its own file in this directory.

## Add a new security group

1. Copy an existing instance file.
2. Change `metadata.name`.
3. Adjust `boundaryClass`, `description`, `networkRef.name`, and `region`.
4. Add the new file to [kustomization.yaml](./kustomization.yaml).
5. Apply the instances root.

Field guide:

- `metadata.name`: unique SG name; the Composition patches this into the AWS Security Group name.
- `boundaryClass`: intent-level category for the shared boundary.
- `description`: operator-facing description in AWS.
- `networkRef.name`: logical network reference; this must match the label on the owner-managed VPC.
- `region`: AWS region for the SG.

Example:

```sh
kubectl apply -k kind-goodnotes-k8s-demo/crossplane-platform-aws-security-group/instances
```

## Notes

- `metadata.name` becomes the AWS Security Group name through the Composition patch.
- `networkRef.name` must match the label on the owner-managed VPC resource.
- Keep access rules in a separate consumer API. Do not extend this owner instance with ingress or egress rule details.
