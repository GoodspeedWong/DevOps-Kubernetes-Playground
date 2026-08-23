# kube-nebula-a Migration Runbook

## Goal

Migrate from the old KinD cluster `goodnotes-k8s-demo` to the new KinD cluster
`kube-nebula-a` running Kubernetes `v1.35.x` without in-place upgrade.

Constraints for this migration:

- Do not delete source-cluster resources during migration.
- After a workload is validated on `kube-nebula-a`, scale the source workload to `0`.
- Leave `apps` namespace trading resources for the final migration phase.

Final execution status:

- Target cluster `kube-nebula-a` is running Kubernetes `v1.35.0` with the same
  node count as the source cluster.
- Trading was migrated last. Target `apps` trading Deployments and
  `statefulset/postgres` are `1/1`, target trading CronJobs are resumed, and
  target `backup-data` plus `postgres-data-postgres-0` PVCs are `Bound`.
- Source trading Deployments and `statefulset/postgres` were scaled to `0`, and
  source trading CronJobs were suspended before final deletion.
- The old Kind cluster `goodnotes-k8s-demo` was deleted after target validation.
- Post-migration cleanup removed the temporary target
  `job/backup-job-migration-smoke`; the target backup CronJob remains scheduled.

## Cluster Roles

- Source cluster: `kind-goodnotes-k8s-demo`
- Target cluster: `kind-kube-nebula-a`

## Preflight

1. Create the target cluster with `goodnotes-k8s-demo/cluster-config-kube-nebula-a.yaml`.
2. Apply namespaces, Gateway API CRDs, Gateway controller, Argo CD, and the minimal
   platform layers needed to accept migrated traffic.
3. Confirm the target cluster uses host port `18080` and the `public-gateway`
   route path is reachable before cutting traffic.

## Freeze The Source Cluster

Before scaling any migrated workload to `0`, freeze automatic reconciliation on the
source cluster or GitOps will restore the old replica count.

For the workload ApplicationSet in `argocd`:

```sh
kubectl --context kind-goodnotes-k8s-demo patch applicationset goodnotes-platform \
  -n argocd \
  --type=json \
  -p='[{"op":"remove","path":"/spec/template/spec/syncPolicy/automated"}]'
```

Verify child `Application` objects no longer contain `spec.syncPolicy.automated`
before scaling source workloads.

## Ordered Migration

1. Demo apps:
   `foo`, `bar`, `iris-sklearn-api`
2. Lightweight platform controllers:
   `k6`, `argocd`
3. Stateful non-trading services:
   `vault`, `grafana`, `keycloak-poc`
4. Remaining observability components:
   first `blackbox-exporter`, `kube-state-metrics`, `prometheus-operator`,
   `alertmanager-main`, `prometheus-k8s`, `node-exporter`; then
   Loki/Mimir/Tempo and paused observability DaemonSets in small batches
5. Trading stack in `apps`:
   `postgres`, `trading-core`, `trading-console`, `market-data-adapter`,
   `portfolio-watcher`, `execution-agent`, `agent-coordinator`,
   `notification-gateway`, `openclaw-discord-gateway`, `postgres-exporter`,
   and all trading cronjobs

## Vault Migration

Use raft snapshot and restore, not raw PVC file copying.

1. Port-forward the source Vault service.
2. Unseal the source Vault if health shows `sealed=true`.
3. Export `/v1/sys/storage/raft/snapshot`.
4. Start target Vault, initialize a temporary 1-of-1 Shamir key, restore the
   snapshot with `/v1/sys/storage/raft/snapshot-force`, then unseal with the
   source unseal key.
5. Copy the source `vault-init` secret into the target cluster.
6. Verify `vault.localhost:18080/v1/sys/health` returns `200`.
7. Scale source `vault` deployment to `0`.

## Grafana Migration

Grafana data is stored in `/var/lib/grafana`.

1. Copy `/var/lib/grafana` from the source pod to a local staging path.
2. Mount the target `grafana-pvc` in a temporary pod.
3. Copy the staged data into the target PVC and `chown -R 65534:65534`.
4. Start target Grafana and verify:
   `curl http://grafana.localhost:18080/api/health`
5. Scale source `grafana` deployment to `0`.

## Crossplane And Keycloak

Only start the minimum Crossplane runtime needed for `XKeycloak` on the target:

- `crossplane`
- `crossplane-rbac-manager`
- `provider-kubernetes`
- `function-patch-and-transform`
- `function-auto-ready`

Do not let AWS providers auto-start during migration. The provider manifests under
`kind-goodnotes-k8s-demo/crossplane-provider-aws/` use `revisionActivationPolicy: Manual`
for this reason.

After `xkeycloak.platform.k8s.goodnotes.io/keycloak-poc` is `READY=True` and
`keycloak.localhost:18080` serves the expected realm:

1. Scale source `keycloak` deployment to `0`.
2. Scale source Crossplane runtime deployments to `0`.

## Monitoring Batches

Migrate observability in two phases instead of starting the full stack at once.

Phase A: base monitoring plane

- `blackbox-exporter`
- `kube-state-metrics`
- `prometheus-operator`
- `alertmanager-main`
- `prometheus-k8s`
- `node-exporter`

After Phase A is healthy on `kind-kube-nebula-a`, scale the source Deployments and
StatefulSets to `0`. For `node-exporter`, keep the DaemonSet object but pause it by
adding a synthetic node selector such as:

```sh
kubectl --context kind-goodnotes-k8s-demo patch daemonset node-exporter \
  -n monitoring \
  --type merge \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"migration.goodnotes.io/paused":"true"}}}}}'
```

Phase B: heavy observability storage and collectors

- Loki
- Mimir
- Tempo
- `otel-agent`
- `otel-gateway`
- `loki-canary`
- `minio-operator` and any monitoring-side MinIO tenants they depend on

Bring up Phase B in small batches and validate each dependency chain before scaling
down the source side. Avoid starting all AWS providers and the full monitoring stack
at the same time on the target cluster.

Target validation completed during this migration:

- Loki: `loki-compactor` `1/1`, `loki-canary` `3/3`, and label API returns
  `pod`, `service_name`, and `stream` for tenant `self-monitoring`.
- Mimir: tenant `self-monitoring` accepts OTel remote-write metrics; query
  `system_cpu_time_seconds_total` returns current samples.
- Tempo: `tempo-query-frontend` `/api/search` responds successfully.
- OTel: `otel-gateway` runs `3/3`, `otel-agent` runs `3/3`, and the gateway has
  a metrics pipeline that exports to Mimir.

Observed target-side fixes:

- Tempo object storage credentials must match the Loki MinIO tenant credentials:
  access key `minio`, secret key `minio123`.
- Loki MinIO local-path PVC directories must be owned by `1000:1000` on the
  target node paths before Tempo can use that bucket reliably.
- `otel-gateway` must include a metrics pipeline. Export metrics to
  `http://mimir-distributor.monitoring.svc:8080/api/v1/push` with
  `X-Scope-OrgID: self-monitoring` and
  `resource_to_telemetry_conversion.enabled: true`.

Source downscale notes:

- Source Loki, Tempo, OTel, MinIO operator, and non-zone Mimir components can be
  scaled to `0` after target validation.
- The source `no-downscale-monitoring` webhook has `failurePolicy: Fail` for
  `monitoring` namespace StatefulSet updates. Keep source
  `deployment/mimir-rollout-operator` at `1` while any source Mimir zone
  StatefulSet still needs to be downscaled.
- Mimir zone StatefulSets must respect rollout-operator spacing:
  `mimir-ingester-zone-*` waits `12h` between zone downscales, and
  `mimir-store-gateway-zone-*` waits `30m` between zone downscales. Do not bypass
  these labels unless accepting possible Mimir data-availability risk.

Current source status after Phase B downscale:

- Scaled to `0`: source Loki Deployments/StatefulSets, source Tempo
  Deployments/StatefulSets, source OTel gateway/agent, source MinIO operator,
  source Mimir Deployments, `mimir-alertmanager`, `mimir-compactor`,
  `mimir-ingester-zone-a`, and `mimir-store-gateway-zone-a`.
- Still intentionally running under rollout-operator protection:
  `mimir-ingester-zone-b`, `mimir-ingester-zone-c`,
  `mimir-store-gateway-zone-b`, and `mimir-store-gateway-zone-c`.
- Keep source `mimir-rollout-operator` running until those remaining source Mimir
  zone StatefulSets have been downscaled. After the final zone is `0/0`, scale
  source `mimir-rollout-operator` to `0`.
- This intermediate state was superseded by final old-cluster deletion after the
  trading cutover completed and the target cluster validated healthy.

### PVC Copy Helper

Use [scripts/copy-kind-local-path-pvc.sh](/Users/goodspeedwong/git_root/DevOps-Kubernetes-GoodNotes/scripts/copy-kind-local-path-pvc.sh)
for Kind local-path PVC copies between the source and target clusters.

When a workload runs as a non-root UID/GID, pass `--target-chown` during the copy so
the target local-path directory is normalized immediately after the data lands.

Observed ownership requirements in this migration:

- `mimir-minio`: `--target-chown 1000:1000`
- Mimir stateful PVCs (`alertmanager`, `compactor`, `ingester`, `store-gateway`):
  `--target-chown 10001:10001`
- Tempo manifests run as UID/GID `1000`, so Tempo PVC copies should use
  `--target-chown 1000:1000`
- Loki MinIO tenant PVCs (`data0` through `data3` for
  `loki-minio-tenant-pool-0-*`) must be `--target-chown 1000:1000`.

If data has already been copied and only target ownership is wrong, use
`--chown-only` together with `--target-chown` instead of copying data again.

## Trading Final Phase

The `apps` namespace trading stack stays last because it has both scheduled writers
and a persistent PostgreSQL backend.

Current source-side trading inventory:

- Stateful data:
  - `statefulset/postgres`
  - `pvc/postgres-data-postgres-0`
  - `pvc/backup-data`
- Online services:
  - `trading-core`
  - `trading-console`
  - `market-data-adapter`
  - `portfolio-watcher`
  - `execution-agent`
  - `agent-coordinator`
  - `notification-gateway`
  - `openclaw-discord-gateway`
  - `postgres-exporter`
- Scheduled jobs:
  - `akshare-sampling-morning`
  - `akshare-sampling-afternoon`
  - `akshare-sampling-close`
  - `tushare-sampling-morning`
  - `tushare-sampling-afternoon`
  - `tushare-sampling-close`
  - `trading-day-recap`
  - `trading-day-recap-tushare`
  - `stock-selection-reference-build`
  - `backup-job`

The trading workloads are runtime-only in this repository: the target cluster has
only the demo `foo`, `bar`, and `iris-sklearn-api` workloads in `apps`. Export the
source live specs, sanitize cluster-specific fields, and apply them to the target
with Deployments/StatefulSets at `replicas: 0` and CronJobs suspended before
restoring data.

Observed source workload images:

- `postgres`: `postgres:16-alpine`
- `trading-core`: `trading-openclaw/trading-core:local-20260609-02`
- `agent-coordinator`: `trading-openclaw/agent-coordinator:local-20260609-02`
- `market-data-adapter`: `trading-openclaw/market-data-adapter:local-20260403-03`
- `execution-agent`: `trading-openclaw/execution-agent:local-20260403-03`
- `portfolio-watcher`: `trading-openclaw/portfolio-watcher:local-20260403-03`
- `notification-gateway`: `trading-openclaw/notification-gateway:local-20260403-03`
- `openclaw-discord-gateway`:
  `trading-openclaw/openclaw-discord-gateway:local-20260403-03`
- `trading-console`: `trading-openclaw/trading-console:local-20260403-03`
- `postgres-exporter`: `quay.io/prometheuscommunity/postgres-exporter:v0.15.0`
- Trading CronJobs: `trading-openclaw/ops-stack:local-20260609-02`

Recommended sequence:

1. Export source live specs for trading Deployments, Services, ConfigMaps,
   Secrets, NetworkPolicies, PVCs, StatefulSet `postgres`, and CronJobs.
2. Apply sanitized target specs with trading Deployments and `postgres` at
   `replicas: 0`; keep target CronJobs suspended.
3. Suspend all source-cluster `apps` CronJobs before touching PostgreSQL.
4. Stop source online trading writers for the final cutover window, then export
   and restore PostgreSQL data to the target cluster.
5. Start target `postgres` and verify application credentials, schema, and
   `postgres-exporter` scrape health.
6. Start target control-plane-facing services:
   `market-data-adapter`, `trading-core`, `agent-coordinator`.
7. Start target downstream workers and delivery components:
   `execution-agent`, `portfolio-watcher`, `notification-gateway`,
   `openclaw-discord-gateway`, `trading-console`.
8. Validate internal service-to-service paths from inside the target cluster.
9. Run one controlled manual execution path for each critical job family before
   resuming schedules.
10. Only after target validation, scale source Deployments and `statefulset/postgres`
   to `0`. Keep the source resources and PVCs.
11. Re-enable CronJobs only on the target cluster.

Validation focus for the trading phase:

- `trading-core -> postgres`
- `trading-core -> market-data-adapter`
- `agent-coordinator`, `execution-agent`, `portfolio-watcher`,
  `notification-gateway` readiness
- `postgres-exporter` metrics
- one dry-run or controlled run for sampling, recap, and backup job paths

Validation completed during cutover:

- Source and target PostgreSQL table counts matched exactly across all 17 user
  tables checked by `scripts/postgres_table_counts.sql`.
- `backup-data` PVC copied with 14 files and 7.6 MiB of source data; target files
  were owned by `10007:10007` for the backup CronJob user.
- Target `backup-job-migration-smoke` completed, created
  `trading-openclaw-backup-20260630T112526Z.json.gz`, and passed bundle
  verification.
- `trading-core` `/readyz` returned `{"status":"ready","detail":"postgres"}`.
- `trading-console` `/readyz` returned ready with an upstream `trading-core`
  readiness response.
- `postgres-exporter` exposed `pg_up 1`.

Do not run the same scheduled trading workflow on both clusters at the same time.

## Gateway Ownership

The target Gateway API stack must own host traffic on `18080`.

- `public-gateway` must exist in namespace `gateway`.
- Envoy data plane must bind the host path used by `18080`.
- `ingress-nginx-controller` on the target cluster should stay at `0` while
  Gateway is the active local entrypoint.

Post-migration Gateway observation:

- `gateway/public-gateway` may show top-level `Programmed=False` with
  `AddressNotAssigned` because the generated Service is `LoadBalancer` without an
  external address in Kind.
- The listener can still be programmed. Validate the data path through the
  control-plane node host port: inside `kube-nebula-a-control-plane`,
  `curl -H 'Host: foo.localhost' http://127.0.0.1:80/healthz` returned `foo`.
- Docker still maps host `18080` to the control-plane container port `80`
  (`0.0.0.0:18080->80/tcp`).
- Host traffic is also verified: from the host network,
  `curl -H 'Host: foo.localhost' http://127.0.0.1:18080/healthz` returned
  `foo`. A sandboxed local curl may fail with `Operation not permitted`; rerun
  the check outside that sandbox before treating it as a Gateway failure.

## Validation Rule

For each migrated component:

1. Verify it is healthy on `kind-kube-nebula-a`.
2. Verify the expected internal or external endpoint.
3. Only then scale the source workload to `0`.

Never delete source resources until the full migration, including trading and data,
is complete and validated.
