---
name: harness-schema-v0
description: "Create, review, and troubleshoot Harness NextGen YAML v0 for Pipelines, Templates, Services, Environments, Infrastructure Definitions, Connectors, Input Sets, Overlays, and Triggers. Use for v0 authoring, schema guidance, static validation, or reviews; do not use for Pipeline YAML v1 except to identify and prevent syntax mixing."
compatibility: opencode
metadata:
  harness-yaml-version: "v0"
  schema-commit: "7d7cbc844e99eba7149315af57fda34b19e7efee"
  reference-language: "zh-CN"
---

# Harness Schema v0

为 Harness NextGen YAML v0 生成可落地的配置，并明确区分结构校验、租户接受度和真实执行结果。

## 先确认任务边界

- 从现有文件、用户说明或 Harness Studio 判断目标确实是 v0。v0 常见特征包括 `pipeline:`、`stages: - stage:`、`templateRef` 和 `<+input>`。
- 不要把 v1 的 `version: 1`、`uses`、`with` 或 `${{ inputs.* }}` 混入 v0。
- 先检查仓库已有的目录、命名、Scope、Connector 和 Template 引用约定；保留用户已有结构，不为套用示例而重写无关内容。
- 若用户要求的是实现，直接生成或修改 YAML；若用户只要求解释或审查，不要擅自导入 Harness、运行 Pipeline 或修改外部租户。

## 按需读取参考

详细字段、示例和固定 Schema 版本在 [references/harness-schema-v0-quick-reference.zh-CN.md](references/harness-schema-v0-quick-reference.zh-CN.md)。只读取与当前任务有关的部分：

| 当前任务 | 读取章节或搜索词 |
|---|---|
| Pipeline、Stage、Step、Step Group、Parallel | `## 5. Pipeline`，并结合 `## 3`、`## 4` |
| Service、Environment、Infrastructure、CD Stage | `## 6` 至 `## 9` |
| Template 定义、引用、输入、Override | `## 10. Template` |
| Input Set、Overlay | `## 11. Input Set 与 Overlay` |
| Connector | `## 12. Connector` |
| Trigger | `## 13. Trigger` |
| 校验、排错或评审 | `## 14` 至 `## 16` |

如果任务依赖当前 Harness 行为、账户 Feature Flag 或最新字段，查阅 Harness 官方文档和当前官方 Schema；固定参考快照只是可复现基线，不代表每个租户此刻使用的服务端 Schema。

## 编写与审查规则

1. 先选定根实体和 `type`，再编写与该 `type` 匹配的 `spec`。不要跨类型复制 `spec`。
2. 项目级实体明确写出 `orgIdentifier` 和 `projectIdentifier`；跨 Scope 引用使用裸 ID、`org.` 或 `account.`，并检查上层实体没有依赖下层资源。
3. 使用稳定的 `identifier`，优先遵循 `^[A-Za-z_][A-Za-z0-9_]{0,127}$`。显示名放在 `name`。
4. 未知环境值使用显式 `REPLACE_*` 占位符，并在交付清单中列出；不要虚构 Connector、Secret、Service 或 Environment Identifier。
5. Secret 只写 Harness Secret 引用。不要把 Token、Password、Kubeconfig 或其他密钥以内联明文写入 YAML。
6. Runtime Input、Template Input 和 Input Set 必须保留原 YAML 路径及必要的 `identifier`、`type`、`spec` 包装层；不要把 `templateInputs` 当成任意参数 map。
7. Deployment Stage 同时核对：
   - `stage.spec.deploymentType`
   - `service.serviceDefinition.type`
   - `infrastructureDefinition.deploymentType`
   - Infrastructure 输入中的具体 `type`
8. 新的 CD v0 内容使用独立 Service、Environment 和 Infrastructure Definition 的 v2 实体引用，不拼接旧 `serviceConfig` 或内联 Infrastructure 结构。
9. Template 固定引用包含 `templateRef` 和 `versionLabel`；输入契约变化时考虑新版本，并提醒调用方 Reconcile。

## 验证顺序

按任务风险执行足够的验证，并分别报告结果：

1. 解析每个 YAML/JSON 文件，证明语法和缩进有效。
2. 对完整的 `pipeline:`、`template:`、`trigger:` 根文档使用对应的官方 v0 JSON Schema。可复现 CI 应固定审核过的 commit；需要精确匹配租户时使用该租户 Studio 的 `yaml-schema` 或 Harness Dry Run。
3. Service、Environment、Infrastructure Definition、Connector、Input Set 和 Overlay 在官方 v0 仓库中没有同级独立根 Schema。对这些实体做 YAML 解析、官方文档/现有租户样例核对，并清楚标记验证边界。
4. Harness Save/Import 或 Dry Run 只能证明当前服务端接受、Template 可展开及相关策略通过，不能证明表达式最终值、Delegate、网络、凭据、Artifact 或 Manifest 可用。
5. 只有真实 Pipeline Execution/UAT 才能证明目标环境中的连接、权限和部署步骤可运行。不要把 Schema 通过或资源 Ready 写成业务成功。

需要外部 Harness 租户写入或真实执行时，仅在用户已请求且权限明确的范围内操作。

## 交付要求

- 单个实体交付完整 YAML；多个相关实体按依赖顺序组织，并提供简短的导入顺序和占位符清单。
- 说明使用的 Harness YAML 版本、Schema 来源或 commit、已执行的检查，以及未执行的 Harness 租户/UAT 验证。
- 审查时给出具体 YAML 路径和修复建议，区分 Schema 错误、引用/Scope 错误和运行时依赖错误。
- 不把公共 Schema 中保留的旧结构自动视为推荐结构；优先采用当前官方文档和现有项目约定一致的 v0 形态。
