#!/usr/bin/env python3
"""Sanitize live Kubernetes JSON for replay into another cluster."""

from __future__ import annotations

import argparse
import copy
import json
import sys
from typing import Any


METADATA_DROP = {
    "creationTimestamp",
    "deletionGracePeriodSeconds",
    "deletionTimestamp",
    "finalizers",
    "generation",
    "managedFields",
    "ownerReferences",
    "resourceVersion",
    "selfLink",
    "uid",
}

ANNOTATION_PREFIX_DROP = (
    "deployment.kubernetes.io/",
    "pv.kubernetes.io/",
    "volume.beta.kubernetes.io/",
    "volume.kubernetes.io/",
)

ANNOTATION_DROP = {
    "kubectl.kubernetes.io/last-applied-configuration",
    "kubectl.kubernetes.io/restartedAt",
}

SERVICE_SPEC_DROP = {
    "allocateLoadBalancerNodePorts",
    "clusterIP",
    "clusterIPs",
    "externalTrafficPolicy",
    "healthCheckNodePort",
    "internalTrafficPolicy",
    "ipFamilies",
    "ipFamilyPolicy",
    "loadBalancerClass",
    "loadBalancerIP",
    "loadBalancerSourceRanges",
}


def parse_names(values: list[str]) -> set[str]:
    names: set[str] = set()
    for value in values:
        names.update(part for part in value.split(",") if part)
    return names


def clean_metadata(metadata: dict[str, Any]) -> None:
    for key in METADATA_DROP:
        metadata.pop(key, None)

    annotations = metadata.get("annotations")
    if isinstance(annotations, dict):
        for key in list(annotations):
            if key in ANNOTATION_DROP or key.startswith(ANNOTATION_PREFIX_DROP):
                annotations.pop(key, None)
        if not annotations:
            metadata.pop("annotations", None)


def clean_pod_template(template: dict[str, Any]) -> None:
    metadata = template.get("metadata")
    if isinstance(metadata, dict):
        clean_metadata(metadata)
        metadata.pop("creationTimestamp", None)


def clean_volume_claim_template(template: dict[str, Any]) -> None:
    metadata = template.get("metadata")
    if isinstance(metadata, dict):
        clean_metadata(metadata)
    template.pop("status", None)


def clean_pvc(resource: dict[str, Any]) -> None:
    spec = resource.get("spec")
    if isinstance(spec, dict):
        spec.pop("volumeName", None)
        spec.pop("dataSourceRef", None)
        spec.pop("dataSource", None)


def clean_service(resource: dict[str, Any]) -> None:
    spec = resource.get("spec")
    if not isinstance(spec, dict):
        return
    for key in SERVICE_SPEC_DROP:
        spec.pop(key, None)
    if spec.get("type") == "ExternalName":
        return
    if spec.get("type") is None:
        spec["type"] = "ClusterIP"


def clean_workload(resource: dict[str, Any], zero_names: set[str]) -> None:
    metadata = resource.get("metadata", {})
    name = metadata.get("name")
    spec = resource.get("spec")
    if not isinstance(spec, dict):
        return

    if name in zero_names and resource.get("kind") in {"Deployment", "StatefulSet"}:
        spec["replicas"] = 0

    template = spec.get("template")
    if isinstance(template, dict):
        clean_pod_template(template)

    volume_claim_templates = spec.get("volumeClaimTemplates")
    if isinstance(volume_claim_templates, list):
        for claim_template in volume_claim_templates:
            if isinstance(claim_template, dict):
                clean_volume_claim_template(claim_template)


def clean_cronjob(resource: dict[str, Any]) -> None:
    spec = resource.get("spec")
    if isinstance(spec, dict):
        spec["suspend"] = True
        job_template = spec.get("jobTemplate")
        if isinstance(job_template, dict):
            clean_metadata(job_template.setdefault("metadata", {}))
            pod_template = (
                job_template.get("spec", {})
                .get("template", {})
                if isinstance(job_template.get("spec"), dict)
                else {}
            )
            if isinstance(pod_template, dict):
                clean_pod_template(pod_template)


def clean_resource(resource: dict[str, Any], zero_names: set[str]) -> dict[str, Any]:
    item = copy.deepcopy(resource)
    item.pop("status", None)

    metadata = item.get("metadata")
    if isinstance(metadata, dict):
        clean_metadata(metadata)

    kind = item.get("kind")
    if kind == "Service":
        clean_service(item)
    elif kind == "PersistentVolumeClaim":
        clean_pvc(item)
    elif kind in {"Deployment", "StatefulSet"}:
        clean_workload(item, zero_names)
    elif kind == "CronJob":
        clean_cronjob(item)

    return item


def iter_items(payload: dict[str, Any]) -> list[dict[str, Any]]:
    if payload.get("kind") == "List":
        return payload.get("items", [])
    if "items" in payload and isinstance(payload["items"], list):
        return payload["items"]
    return [payload]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--zero-replicas",
        action="append",
        default=[],
        help="Comma-separated workload names to emit with replicas: 0.",
    )
    args = parser.parse_args()

    payload = json.load(sys.stdin)
    zero_names = parse_names(args.zero_replicas)
    items = [clean_resource(item, zero_names) for item in iter_items(payload)]

    json.dump(
        {
            "apiVersion": "v1",
            "kind": "List",
            "items": items,
        },
        sys.stdout,
        indent=2,
        sort_keys=True,
    )
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
