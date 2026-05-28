## Goal

Install a Crossplane AWS provider into the existing `kind-goodnotes-k8s-demo` management cluster so Crossplane can reconcile AWS managed resources.

This stack follows the Crossplane v2 provider model:

- `provider-aws-ec2` installs VPC, subnet, route table, security group, NAT, and instance style primitives.
- `provider-aws-eks` installs EKS cluster, node group, addon, and identity APIs.
- `provider-aws-iam` installs IAM users, roles, policies, and attachments.
- `provider-aws-rds` installs RDS instance and cluster APIs.
- `provider-aws-s3` installs S3 bucket and bucket-adjacent APIs.
- Crossplane automatically installs `provider-family-aws` as a dependency for shared AWS authentication.
- `provider-config/` creates `ClusterProviderConfig/default`, which points AWS managed resources at a secret named `aws-secret` in `crossplane-system`.

## 1. Prerequisites

Crossplane core must already be installed:

```sh
kubectl apply -k kind-goodnotes-k8s-demo/namespaces
kubectl apply -k kind-goodnotes-k8s-demo/crossplane
```

Prepare an AWS credentials file in standard INI format:

```ini
[default]
aws_access_key_id = REPLACE_ME
aws_secret_access_key = REPLACE_ME
```

## 2. Create the AWS credentials secret

```sh
kubectl -n crossplane-system create secret generic aws-secret \
  --from-file=creds=./aws-credentials.ini \
  --dry-run=client -o yaml | kubectl apply -f -
```

## 3. Install the provider

```sh
kubectl apply -k kind-goodnotes-k8s-demo/crossplane-provider-aws
```

## 4. Wait until the provider is healthy

```sh
kubectl get providers

kubectl wait \
  --for=condition=Healthy \
  provider.pkg.crossplane.io/crossplane-contrib-provider-aws-s3 \
  --timeout=300s

kubectl wait \
  --for=condition=Healthy \
  provider.pkg.crossplane.io/crossplane-contrib-provider-aws-ec2 \
  --timeout=300s

kubectl wait \
  --for=condition=Healthy \
  provider.pkg.crossplane.io/crossplane-contrib-provider-aws-iam \
  --timeout=300s

kubectl wait \
  --for=condition=Healthy \
  provider.pkg.crossplane.io/crossplane-contrib-provider-aws-rds \
  --timeout=300s

kubectl wait \
  --for=condition=Healthy \
  provider.pkg.crossplane.io/crossplane-contrib-provider-aws-eks \
  --timeout=300s
```

Expected outcome after the wait:

- `crossplane-contrib-provider-aws-s3`, `-ec2`, `-iam`, `-rds`, and `-eks` become `HEALTHY=True`
- `crossplane-contrib-provider-family-aws` appears automatically as a dependency

## 5. Apply the cluster-wide AWS provider config

```sh
kubectl apply -k kind-goodnotes-k8s-demo/crossplane-provider-aws/provider-config
kubectl get clusterproviderconfig.aws.m.upbound.io default
```

## 6. Create a demo AWS resource

An example S3 bucket managed resource is provided under `examples/s3-bucket/`:

Before applying it, edit `examples/s3-bucket/bucket.yaml` and replace
`crossplane.io/external-name: replace-with-a-globally-unique-s3-bucket-name`
with a globally unique S3 bucket name.

```sh
kubectl apply -k kind-goodnotes-k8s-demo/crossplane-provider-aws/examples/s3-bucket
kubectl get buckets.s3.aws.m.upbound.io -n default
```

Delete it with:

```sh
kubectl delete -k kind-goodnotes-k8s-demo/crossplane-provider-aws/examples/s3-bucket
```

## Notes

- This root does not create AWS resources by default. It installs the provider and the cluster-wide AWS credential reference only.
- Crossplane v2 packages AWS support by service. This repo now pre-installs the common base set for platform work: `ec2`, `eks`, `iam`, `rds`, and `s3`.
- The Upbound provider packages in this repo use the official `xpkg.upbound.io/upbound/...` registry path.
- The package versions are pinned per service provider. At the time this was updated, the current marketplace versions used here were `v2.5.3` for `ec2`, `eks`, `iam`, `rds`, and `s3`.
- Do not uninstall the provider before deleting managed resources, or AWS resources may be left behind.
