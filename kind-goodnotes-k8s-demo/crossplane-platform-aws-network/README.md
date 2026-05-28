# Crossplane AWS Platform Network

This root defines an owner-style Crossplane platform API for an AWS VPC-backed network boundary.

## Design boundary

This API models a platform network, not a raw AWS VPC primitive.

- Owner XR: `XNetwork`
- Managed resources: `VPC`, `InternetGateway`, `RouteTable`, `Route`, `Subnet`, `RouteTableAssociation`
- Ownership rule: this XR owns the shared network lifecycle end to end
- Non-goal: consumer teams passing raw `vpcId`, `subnetIds`, or `routeTableIds`
- Managed resource namespace: `crossplane-system`

The API follows the Crossplane platform design skill:

- expose owner intent: `networkClass`, `region`, `cidrBlock`, `publicSubnets`, `privateSubnets`
- hide consumer-hostile details: no `vpcId`, no `subnetIds`, no `routeTableIds`, no AWS selector fields
- make ownership explicit: delete the XR and the owned VPC topology is deleted too unless `deletionPolicy: Orphan`

## Owner vs consumer split

This XR is deliberately owner-scoped because network topology is a shared lifecycle boundary.

That means this Composition creates and reconciles:

- one VPC
- one Internet Gateway
- one public route table plus public default route
- one private route table
- two public subnets
- two private subnets
- route table associations for all four subnets

What it does not do:

- expose raw cloud IDs as input
- let application teams mutate shared route tables
- mix network ownership with downstream consumers such as EKS, RDS, or Security Group rules
- create NAT gateways, because that is a separate blast-radius and cost decision

If a downstream platform API needs network access, it should reference this owner XR by logical name,
for example `networkRef.name: shared-dev-network`, and resolve the underlying VPC or subnet through labels
or status produced by this owner Composition.

## Labels exported for consumers

The Composition stamps the following stable labels onto owner-managed resources:

- `platform.aws.goodnotes.io/network: <xr-name>`
- `platform.aws.goodnotes.io/network-class: <networkClass>`
- `platform.aws.goodnotes.io/resource-role: vpc|subnet|route-table|internet-gateway|route-table-association`
- `platform.aws.goodnotes.io/subnet-visibility: public|private`
- `platform.aws.goodnotes.io/subnet-slot: a|b`

This keeps consumer APIs reference-based rather than ID-based.

## Status exported by the owner XR

The XR surfaces:

- `status.vpcId`
- `status.vpcArn`
- `status.internetGatewayId`
- `status.publicRouteTableId`
- `status.privateRouteTableId`
- `status.publicSubnetIds.a`
- `status.publicSubnetIds.b`
- `status.privateSubnetIds.a`
- `status.privateSubnetIds.b`

These are outputs for automation or inspection, not inputs for consumer APIs.

## Apply API

```sh
kubectl apply -k kind-goodnotes-k8s-demo/crossplane-platform-aws-network
```

## Apply instances

For day-2 usage, manage network instances under [`instances/`](./instances).

```sh
kubectl apply -k kind-goodnotes-k8s-demo/crossplane-platform-aws-network/instances
```

You can also apply a single example directly:

```sh
kubectl apply -f kind-goodnotes-k8s-demo/crossplane-platform-aws-network/examples/shared-dev-network.yaml
```
