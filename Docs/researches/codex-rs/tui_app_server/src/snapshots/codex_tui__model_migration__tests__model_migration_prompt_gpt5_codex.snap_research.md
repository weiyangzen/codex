# 研究文档：model_migration_prompt_gpt5_codex.snap

## 场景与职责

此快照测试验证特定模型迁移场景：从 gpt-5-codex 迁移到 gpt-5.1-codex-max 的提示显示。

## 功能点目的

1. **特定模型迁移**：针对 gpt-5-codex 用户的迁移提示
2. **模型信息展示**：展示 gpt-5.1-codex-max 的特点
3. **直接升级**：此场景下用户只能按回车继续（不能选择）

## 具体技术实现

### 快照输出分析

```

> Codex just got an upgrade. Introducing gpt-5.1-codex-max.

  We recommend switching from gpt-5-codex to
  gpt-5.1-codex-max.

  Codex-optimized flagship for deep and fast reasoning.
  Learn more about gpt-5.1-codex-max at
  https://www.codex.com/models/gpt-5.1-codex-max

  Press enter to continue
```

与通用迁移提示的区别：
- 没有选项菜单
- 只能按回车继续
- 显示特定模型描述

### 迁移逻辑

```rust
pub(crate) fn migration_copy_for_models(
    current_model: &str,
    target_model: &str,
    model_link: Option<String>,
    migration_copy: Option<String>,
    migration_markdown: Option<String>,
    target_display_name: String,
    target_description: Option<String>,
    can_opt_out: bool,  // 此场景下为 false
) -> ModelMigrationCopy {
    // 如果 can_opt_out 为 false，显示 "Press enter to continue"
    // 否则显示选择菜单
}
```

## 关键代码路径与文件引用

1. **迁移提示**：
   - `codex-rs/tui/src/model_migration.rs` 第 60-135 行

2. **模型配置**：
   - `codex_protocol::openai_models`

## 依赖与外部交互

### 模型信息
- 模型显示名称
- 模型描述
- 模型文档链接

## 风险、边界与改进建议

### 潜在风险
1. **强制升级**：用户无法选择可能引发不满
2. **信息不足**：简短描述可能不足以让用户了解变化

### 改进建议
1. 即使是强制升级，也提供更多信息链接
2. 添加升级后的回滚说明
3. 显示升级的预期影响（如速度、成本变化）
