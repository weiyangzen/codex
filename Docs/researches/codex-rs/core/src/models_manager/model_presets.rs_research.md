# model_presets.rs 研究文档

## 场景与职责

`model_presets.rs` 是一个极简的遗留兼容性模块，仅包含两个配置键常量。这些常量用于向后兼容旧版本的迁移提示配置。

该模块的存在反映了 Codex CLI 的演进历史：早期版本使用硬编码的模型预设和迁移提示，后来迁移到动态的模型目录系统（`models.json`）。为了保持配置兼容性，这些配置键被保留但不再使用。

## 功能点目的

### 遗留配置键

| 常量 | 值 | 历史用途 |
|------|-----|----------|
| `HIDE_GPT5_1_MIGRATION_PROMPT_CONFIG` | `"hide_gpt5_1_migration_prompt"` | 控制 GPT-5.1 模型迁移提示的显示 |
| `HIDE_GPT_5_1_CODEX_MAX_MIGRATION_PROMPT_CONFIG` | `"hide_gpt-5.1-codex-max_migration_prompt"` | 控制 GPT-5.1-codex-max 模型迁移提示的显示 |

### 文档说明
模块级文档明确说明了这些常量的性质：
```rust
/// Legacy notice keys kept for config compatibility with older migration prompts.
///
/// Hardcoded model presets were removed; model listings are now derived from the active catalog.
```

## 具体技术实现

### 代码内容
```rust
/// Legacy notice keys kept for config compatibility with older migration prompts.
///
/// Hardcoded model presets were removed; model listings are now derived from the active catalog.
pub const HIDE_GPT5_1_MIGRATION_PROMPT_CONFIG: &str = "hide_gpt5_1_migration_prompt";
pub const HIDE_GPT_5_1_CODEX_MAX_MIGRATION_PROMPT_CONFIG: &str =
    "hide_gpt-5.1-codex-max_migration_prompt";
```

### 架构演进背景

#### 旧架构（硬编码预设）
```rust
// 早期版本
const MODEL_PRESETS: &[ModelPreset] = &[
    ModelPreset { id: "gpt-5.1", ... },
    ModelPreset { id: "gpt-5.1-codex-max", ... },
    // ...
];
```

#### 新架构（动态目录）
```rust
// 当前版本
// 从 models.json 或远程 API 加载模型列表
let models: Vec<ModelInfo> = load_models_from_catalog().await;
```

### 配置兼容性处理

这些常量可能仍在以下场景使用：
1. **配置解析**：识别并忽略这些遗留配置键（避免"未知配置"警告）
2. **配置迁移**：旧配置升级时清理这些键
3. **文档参考**：说明配置变更历史

## 关键代码路径与文件引用

### 潜在使用方
通过代码搜索，这些常量可能在以下位置使用：

| 路径 | 可能用途 |
|------|----------|
| `config/mod.rs` | 遗留配置键识别 |
| `config/migration.rs` | 配置迁移处理 |

### 相关配置键模式
```rust
// 旧配置示例（TOML）
[model]
hide_gpt5_1_migration_prompt = true
hide_gpt-5.1-codex-max_migration_prompt = true
```

## 依赖与外部交互

### 外部依赖
- 无（仅使用 Rust 标准库）

### 编译时特性
- 无特殊编译时依赖

## 风险、边界与改进建议

### 已知风险

1. **代码债务**
   - 风险：遗留代码增加维护负担
   - 现状：仅两个常量，影响有限
   - 建议：评估是否可以安全移除

2. **配置混淆**
   - 风险：用户可能在配置中继续使用这些键，期望有实际效果
   - 现状：文档说明已废弃，但无运行时警告
   - 建议：添加配置解析时的废弃警告

3. **命名不一致**
   - 观察：两个常量命名风格不一致
     - `HIDE_GPT5_1...`（无连字符）
     - `HIDE_GPT_5_1...`（有连字符）
   - 原因：与模型 slug 命名保持一致

### 边界条件

| 场景 | 行为 |
|------|------|
| 配置中包含这些键 | 取决于配置解析逻辑，可能忽略或警告 |
| 新代码引用这些常量 | 编译通过，但功能可能不存在 |

### 改进建议

1. **添加废弃属性**
   ```rust
   #[deprecated(
       since = "0.99.0",
       note = "Hardcoded model presets were removed. Model listings are now derived from the active catalog."
   )]
   pub const HIDE_GPT5_1_MIGRATION_PROMPT_CONFIG: &str = "hide_gpt5_1_migration_prompt";
   ```

2. **配置解析警告**
   ```rust
   // 在配置解析时
   if config.contains_key(HIDE_GPT5_1_MIGRATION_PROMPT_CONFIG) {
       warn!(
           "Config key '{}' is deprecated and no longer has any effect.",
           HIDE_GPT5_1_MIGRATION_PROMPT_CONFIG
       );
   }
   ```

3. **迁移指南**
   - 在 CHANGELOG 中说明这些配置的替代方案
   - 如果用户想要禁用迁移提示，说明新的方式（如果有）

4. **安全移除评估**
   - 检查遥测数据，确认没有活跃用户使用这些配置键
   - 如果安全，在主要版本升级时移除

5. **文档化历史**
   ```rust
   //! ## History
   //! 
   //! Before v0.98.0, Codex CLI used hardcoded model presets. Migration prompts
   //! for model upgrades could be disabled using these configuration keys.
   //! 
   //! Since v0.98.0, model listings are dynamically fetched from the `/models`
   //! endpoint or loaded from the bundled `models.json`. These constants are
   //! kept for backward compatibility but have no effect.
   ```

### 维护建议

1. **定期审查**
   - 每季度审查遗留代码的使用情况
   - 评估移除的可行性

2. **用户沟通**
   - 如果决定移除，提前在 release notes 中通知
   - 提供配置迁移脚本（如果需要）

3. **代码注释**
   - 保持当前的详细文档注释
   - 添加最后审查日期和审查人

### 相关文件

| 文件 | 关系 |
|------|------|
| `models.json` | 替代硬编码预设的动态模型目录 |
| `manager.rs` | 使用动态目录的模型管理器 |
| `config/mod.rs` | 可能引用这些常量的配置解析 |
