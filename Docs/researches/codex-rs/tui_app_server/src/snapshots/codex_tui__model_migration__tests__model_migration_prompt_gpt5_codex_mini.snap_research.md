# 研究文档：model_migration_prompt_gpt5_codex_mini.snap

## 场景与职责

此快照测试验证从 gpt-5-codex-mini 迁移到 gpt-5.1-codex-mini 的特定提示显示。这是针对轻量级模型的迁移场景。

## 功能点目的

1. **轻量级模型迁移**：针对 codex-mini 用户的迁移提示
2. **成本/性能平衡**：强调 mini 模型的成本效益
3. **直接升级**：此场景下用户只能按回车继续

## 具体技术实现

### 快照输出分析

```

> Codex just got an upgrade. Introducing gpt-5.1-codex-mini.

  We recommend switching from gpt-5-codex-mini to
  gpt-5.1-codex-mini.

  Optimized for codex. Cheaper, faster, but less capable.
  Learn more about gpt-5.1-codex-mini at
  https://www.codex.com/models/gpt-5.1-codex-mini

  Press enter to continue
```

关键信息：
- 模型名称：gpt-5.1-codex-mini
- 特点：Cheaper, faster, but less capable
- 升级方式：Press enter to continue

### 模型描述生成

```rust
// 根据目标模型生成描述
let description = match target_model {
    "gpt-5.1-codex-mini" => Some("Optimized for codex. Cheaper, faster, but less capable."),
    "gpt-5.1-codex-max" => Some("Codex-optimized flagship for deep and fast reasoning."),
    _ => target_description,
};
```

## 关键代码路径与文件引用

1. **迁移实现**：
   - `codex-rs/tui/src/model_migration.rs`
   - `codex-rs/tui_app_server/src/model_migration.rs`

## 依赖与外部交互

### 模型配置
- `codex_protocol::openai_models::ReasoningEffort`
- `codex_protocol::config_types::ServiceTier`

## 风险、边界与改进建议

### 潜在风险
1. **能力降级提示**："less capable" 可能让用户犹豫升级
2. **成本误解**：用户可能担心升级后成本增加

### 改进建议
1. 添加具体的成本对比
2. 说明适用场景（快速原型 vs 深度开发）
3. 提供性能基准数据
