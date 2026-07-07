#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
STAGE_ROOT_DEFAULT="/private/tmp/kind-pvc-copy-$(date +%Y%m%dT%H%M%S)"
STAGE_ROOT="$STAGE_ROOT_DEFAULT"
DRY_RUN=0
KEEP_STAGE=0
TARGET_CHOWN=""
CHOWN_ONLY=0

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [--stage-root DIR] [--keep-stage] [--target-chown UID:GID] [--chown-only] [--dry-run] \
  <source-context> <target-context> <namespace> <claim> [<claim> ...]

Copy one or more local-path PVC directories between two Kind clusters by
streaming through a host staging directory.

Examples:
  ${SCRIPT_NAME} kind-goodnotes-k8s-demo kind-kube-nebula-a monitoring mimir-minio
  ${SCRIPT_NAME} --target-chown 10001:10001 \\
    kind-goodnotes-k8s-demo kind-kube-nebula-a monitoring storage-mimir-ingester-zone-a-0
  ${SCRIPT_NAME} --keep-stage kind-goodnotes-k8s-demo kind-kube-nebula-a monitoring \\
    data0-loki-minio-tenant-pool-0-0 data1-loki-minio-tenant-pool-0-0
  ${SCRIPT_NAME} --target-chown 1000:1000 --chown-only \\
    kind-goodnotes-k8s-demo kind-kube-nebula-a monitoring data0-loki-minio-tenant-pool-0-0

Notes:
  - Both clusters must use the default local-path-provisioner layout.
  - The target PVCs must already exist and be Bound.
  - The script does not scale workloads for you.
  - Use --target-chown when the target workload runs as a non-root UID/GID and the
    copied files need ownership normalization.
  - Use --chown-only with --target-chown to repair target ownership without
    copying data again.
EOF
}

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "dry-run: $*"
    return 0
  fi
  "$@"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --stage-root)
        STAGE_ROOT="$2"
        shift 2
        ;;
      --keep-stage)
        KEEP_STAGE=1
        shift
        ;;
      --target-chown)
        TARGET_CHOWN="$2"
        shift 2
        ;;
      --chown-only)
        CHOWN_ONLY=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        printf 'unknown option: %s\n' "$1" >&2
        usage >&2
        exit 1
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ $# -lt 4 ]]; then
    usage >&2
    exit 1
  fi

  if [[ "$CHOWN_ONLY" -eq 1 && -z "$TARGET_CHOWN" ]]; then
    printf '--chown-only requires --target-chown UID:GID\n' >&2
    usage >&2
    exit 1
  fi

  SOURCE_CONTEXT="$1"
  TARGET_CONTEXT="$2"
  NAMESPACE="$3"
  shift 3
  CLAIMS=("$@")
}

pv_name_for_claim() {
  local context="$1"
  local namespace="$2"
  local claim="$3"
  kubectl --context "$context" get pvc "$claim" -n "$namespace" \
    -o jsonpath='{.spec.volumeName}'
}

node_name_for_pv() {
  local context="$1"
  local pv="$2"
  kubectl --context "$context" get pv "$pv" \
    -o jsonpath='{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}'
}

local_path_dir() {
  local pv="$1"
  local namespace="$2"
  local claim="$3"
  printf '/var/local-path-provisioner/%s_%s_%s' "$pv" "$namespace" "$claim"
}

stage_dir_for_claim() {
  local claim="$1"
  printf '%s/%s' "$STAGE_ROOT" "$claim"
}

copy_claim() {
  local claim="$1"
  local source_pv source_node source_dir
  local target_pv target_node target_dir
  local stage_dir

  target_pv="$(pv_name_for_claim "$TARGET_CONTEXT" "$NAMESPACE" "$claim")"

  if [[ -z "$target_pv" ]]; then
    printf 'unable to resolve pv for claim %s\n' "$claim" >&2
    exit 1
  fi

  target_node="$(node_name_for_pv "$TARGET_CONTEXT" "$target_pv")"

  target_dir="$(local_path_dir "$target_pv" "$NAMESPACE" "$claim")"
  stage_dir="$(stage_dir_for_claim "$claim")"

  if [[ "$CHOWN_ONLY" -eq 1 ]]; then
    log "chown ${NAMESPACE}/${claim}"
    log "  target: ${TARGET_CONTEXT} ${target_node}:${target_dir}"
    log "  chown : ${TARGET_CHOWN}"
    if [[ "$DRY_RUN" -eq 0 ]]; then
      docker exec "$target_node" sh -lc "test -d '$target_dir'"
    fi
    run docker exec "$target_node" sh -lc \
      "chown -R '$TARGET_CHOWN' '$target_dir'"
    return 0
  fi

  source_pv="$(pv_name_for_claim "$SOURCE_CONTEXT" "$NAMESPACE" "$claim")"

  if [[ -z "$source_pv" ]]; then
    printf 'unable to resolve pv for claim %s\n' "$claim" >&2
    exit 1
  fi

  source_node="$(node_name_for_pv "$SOURCE_CONTEXT" "$source_pv")"
  source_dir="$(local_path_dir "$source_pv" "$NAMESPACE" "$claim")"

  log "copy ${NAMESPACE}/${claim}"
  log "  source: ${SOURCE_CONTEXT} ${source_node}:${source_dir}"
  log "  target: ${TARGET_CONTEXT} ${target_node}:${target_dir}"
  log "  stage : ${stage_dir}"
  if [[ -n "$TARGET_CHOWN" ]]; then
    log "  chown : ${TARGET_CHOWN}"
  fi

  run mkdir -p "$STAGE_ROOT"
  run rm -rf "$stage_dir"
  run mkdir -p "$stage_dir"

  run docker cp "${source_node}:${source_dir}/." "$stage_dir/"

  if [[ "$DRY_RUN" -eq 0 ]]; then
    docker exec "$target_node" sh -lc "test -d '$target_dir'"
  fi

  run docker cp "${stage_dir}/." "${target_node}:${target_dir}/"

  if [[ -n "$TARGET_CHOWN" ]]; then
    run docker exec "$target_node" sh -lc \
      "chown -R '$TARGET_CHOWN' '$target_dir'"
  fi

  if [[ "$KEEP_STAGE" -eq 0 ]]; then
    run rm -rf "$stage_dir"
  fi
}

main() {
  require_cmd kubectl
  require_cmd docker
  require_cmd mkdir
  require_cmd rm

  parse_args "$@"

  local claim
  for claim in "${CLAIMS[@]}"; do
    copy_claim "$claim"
  done

  if [[ "$KEEP_STAGE" -eq 1 ]]; then
    log "staged copy retained at ${STAGE_ROOT}"
  fi
}

main "$@"
