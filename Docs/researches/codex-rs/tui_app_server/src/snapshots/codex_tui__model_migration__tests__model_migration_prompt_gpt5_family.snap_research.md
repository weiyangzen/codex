# 研究文档：model_migration_prompt_gpt5_family.snap

## 场景与职责

此快照测试验证从 gpt-5 基础模型迁移到 gpt-5.1 的提示显示。这是针对通用 GPT-5 用户的迁移场景。

## 功能点目的

1. **基础模型迁移**：针对 gpt-5 用户的迁移提示
2. **通用能力强调**：强调模型的通用推理能力
3. **直接升级**：此场景下用户只能按回车继续

## 具体技术实现

### 快照输出分析

```

> Codex just got an upgrade. Introducing gpt-5.1.

  We recommend switching from gpt-5 to gpt-5.1.

  Broad world knowledge with strong general reasoning. Learn more
  about gpt-5.1 at https://www.codex.com/models/gpt-5.1

  Press enter to continue
```

关键信息：
- 模型名称：gpt-5.1（非 codex 专用版本）
- 特点：Broad world knowledge with strong general reasoning
- 目标用户：通用 GPT-5 用户

### 与 codex 专用版本的区别

| 特性 | gpt-5.1 | gpt-5.1-codex-max | gpt-5.1-codex-mini |
|------|---------|-------------------|-------------------|
| 定位 | 通用 | 编程专用 | 轻量编程 |
| 特点 | 世界知识 | 深度推理 | 快速便宜 |
| 适用场景 | 通用任务 | 复杂编程 | 快速原型 |

## 关键代码路径与文件引用

1. **迁移提示**：
   - `codex-rs/tui/src/model_migration.rs`
   - `migration_copy_for_models` 函数

## 依赖与外部交互

### 模型信息
- `codex_protocol::openai_models`
- 模型文档 URL 生成

## 风险、边界与改进建议

### 潜在风险
1. **场景不匹配**：通用模型用户可能不需要 codex 专用功能
2. **期望落差**：迁移后体验可能与预期不同

### 改进建议
1. 根据用户使用模式推荐合适的模型
2. 提供模型选择指南
3. 支持 A/B 测试不同模型
