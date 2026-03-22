# model_info_tests.rs 研究文档

## 场景与职责

`model_info_tests.rs` 是 `model_info.rs` 的配套测试模块，专注于验证配置覆盖逻辑的正确性。该测试文件通过 `#[path = "model_info_tests.rs"]` 属性在父模块中条件编译引入。

当前测试覆盖范围相对有限，主要集中在 `model_supports_reasoning_summaries` 配置项的行为验证。

## 功能点目的

### 1. 启用 Reasoning Summaries (`reasoning_summaries_override_true_enables_support`)
- **目的**：验证配置设置为 `true` 时正确启用模型 reasoning summaries 支持
- **测试步骤**：
  1. 创建 fallback 模型（默认 `supports_reasoning_summaries = false`）
  2. 设置配置 `model_supports_reasoning_summaries = Some(true)`
  3. 应用配置覆盖
  4. 验证结果模型的 `supports_reasoning_summaries = true`

### 2. 禁用 Reasoning Summaries 无效 (`reasoning_summaries_override_false_does_not_disable_support`)
- **目的**：验证配置设置为 `false` 时不会禁用已启用的 reasoning summaries
- **测试步骤**：
  1. 创建模型并手动设置 `supports_reasoning_summaries = true`
  2. 设置配置 `model_supports_reasoning_summaries = Some(false)`
  3. 应用配置覆盖
  4. 验证结果模型保持 `supports_reasoning_summaries = true`

### 3. 无变化场景 (`reasoning_summaries_override_false_is_noop_when_model_is_false`)
- **目的**：验证配置为 `false` 且模型已为 `false` 时无变化
- **测试步骤**：
  1. 创建 fallback 模型（默认 `supports_reasoning_summaries = false`）
  2. 设置配置 `model_supports_reasoning_summaries = Some(false)`
  3. 应用配置覆盖
  4. 验证结果模型保持 `supports_reasoning_summaries = false`

## 具体技术实现

### 测试结构

```rust
use super::*;  // 引入父模块所有内容
use crate::config::test_config;  // 测试配置构造器
use pretty_assertions::assert_eq;  // 清晰的差异输出

#[test]
fn test_name() {
    // 测试实现
}
```

### 测试数据构造

#### Fallback 模型创建
```rust
let model = model_info_from_slug("unknown-model");
// fallback 模型默认：
// - supports_reasoning_summaries = false
// - used_fallback_model_metadata = true
```

#### 测试配置创建
```rust
let mut config = test_config();  // 创建默认测试配置
config.model_supports_reasoning_summaries = Some(true);  // 设置目标值
```

### 验证模式

#### 完整对象比较
```rust
let updated = with_config_overrides(model.clone(), &config);
let mut expected = model;
expected.supports_reasoning_summaries = true;
assert_eq!(updated, expected);  // 比较整个 ModelInfo 对象
```

## 关键代码路径与文件引用

### 被测试的函数
| 函数 | 所在文件 | 测试覆盖 |
|------|----------|----------|
| `with_config_overrides` | `model_info.rs:24` | 3 个测试 |
| `model_info_from_slug` | `model_info.rs:61` | 间接使用 |

### 使用的配置项
| 配置项 | 验证场景 |
|--------|----------|
| `model_supports_reasoning_summaries = Some(true)` | 启用支持 |
| `model_supports_reasoning_summaries = Some(false)` | 禁用无效 |

### 外部类型依赖
| 类型 | 来源 | 用途 |
|------|------|------|
| `test_config` | `crate::config` | 创建测试配置 |
| `ModelInfo` | `codex_protocol::openai_models` | 模型元数据结构 |

## 依赖与外部交互

### 测试框架
- **测试运行器**：Rust 内置测试框架 (`#[test]`)
- **断言库**：`pretty_assertions::assert_eq`

### 被测模块接口
```rust
// 父模块中条件引入测试模块
#[cfg(test)]
#[path = "model_info_tests.rs"]
mod tests;
```

### 测试可见性
- 测试使用 `use super::*` 访问父模块的私有函数
- 使用了 `crate::config::test_config` 测试辅助函数

## 风险、边界与改进建议

### 测试覆盖率分析

| 被测功能 | 覆盖状态 | 说明 |
|----------|----------|------|
| `model_supports_reasoning_summaries` 覆盖 | ✅ 完全覆盖 | 启用、禁用、无变化 |
| `model_context_window` 覆盖 | ❌ 未覆盖 | - |
| `model_auto_compact_token_limit` 覆盖 | ❌ 未覆盖 | - |
| `tool_output_token_limit` 覆盖 | ❌ 未覆盖 | - |
| `base_instructions` 覆盖 | ❌ 未覆盖 | - |
| `features.personality` 影响 | ❌ 未覆盖 | - |
| `model_info_from_slug` | ❌ 未直接覆盖 | 仅作为测试数据构造 |
| `local_personality_messages_for_slug` | ❌ 未覆盖 | - |

### 缺失测试场景

#### 高优先级缺失测试

1. **Context Window 覆盖**
   ```rust
   #[test]
   fn context_window_override_replaces_value() {
       let model = model_info_from_slug("test");
       let mut config = test_config();
       config.model_context_window = Some(128000);
       
       let updated = with_config_overrides(model, &config);
       
       assert_eq!(updated.context_window, Some(128000));
   }
   ```

2. **Tool Output Token Limit 覆盖**
   ```rust
   #[test]
   fn tool_output_token_limit_converts_to_bytes() {
       let mut model = model_info_from_slug("test");
       model.truncation_policy = TruncationPolicyConfig::bytes(10000);
       let mut config = test_config();
       config.tool_output_token_limit = Some(1000);
       
       let updated = with_config_overrides(model, &config);
       
       assert_eq!(updated.truncation_policy.mode, TruncationMode::Bytes);
       assert_eq!(updated.truncation_policy.limit, 4000); // 1000 * 4
   }
   
   #[test]
   fn tool_output_token_limit_converts_to_tokens() {
       let mut model = model_info_from_slug("test");
       model.truncation_policy = TruncationPolicyConfig::tokens(10000);
       let mut config = test_config();
       config.tool_output_token_limit = Some(1000);
       
       let updated = with_config_overrides(model, &config);
       
       assert_eq!(updated.truncation_policy.mode, TruncationMode::Tokens);
       assert_eq!(updated.truncation_policy.limit, 1000);
   }
   ```

3. **Base Instructions 覆盖**
   ```rust
   #[test]
   fn base_instructions_override_clears_model_messages() {
       let model = model_info_from_slug("gpt-5.2-codex"); // 有 model_messages
       let mut config = test_config();
       config.base_instructions = Some("Custom instructions".to_string());
       
       let updated = with_config_overrides(model, &config);
       
       assert_eq!(updated.base_instructions, "Custom instructions");
       assert!(updated.model_messages.is_none());
   }
   ```

4. **Personality 特性禁用**
   ```rust
   #[test]
   fn disabled_personality_feature_clears_model_messages() {
       let model = model_info_from_slug("gpt-5.2-codex");
       let mut config = test_config();
       config.features.disable(Feature::Personality);
       
       let updated = with_config_overrides(model, &config);
       
       assert!(updated.model_messages.is_none());
   }
   ```

5. **Fallback 模型生成**
   ```rust
   #[test]
   fn model_info_from_slug_marks_fallback() {
       let model = model_info_from_slug("unknown-model");
       
       assert!(model.used_fallback_model_metadata);
       assert_eq!(model.slug, "unknown-model");
       assert_eq!(model.display_name, "unknown-model");
       assert_eq!(model.priority, 99);
   }
   ```

6. **个性化消息生成**
   ```rust
   #[test]
   fn local_personality_messages_for_supported_model() {
       let messages = local_personality_messages_for_slug("gpt-5.2-codex");
       
       assert!(messages.is_some());
       let messages = messages.unwrap();
       assert!(messages.instructions_template.is_some());
       assert!(messages.instructions_variables.is_some());
   }
   
   #[test]
   fn local_personality_messages_for_unsupported_model() {
       let messages = local_personality_messages_for_slug("gpt-5");
       
       assert!(messages.is_none());
   }
   ```

### 改进建议

1. **测试组织优化**
   ```rust
   mod reasoning_summaries_tests { ... }
   mod context_window_tests { ... }
   mod base_instructions_tests { ... }
   mod fallback_tests { ... }
   ```

2. **参数化测试**
   ```rust
   #[test_case(Some(true), true, true)]
   #[test_case(Some(false), true, true)]  // 禁用无效
   #[test_case(Some(false), false, false)] // 无变化
   #[test_case(None, true, true)]  // 配置未设置
   fn reasoning_summaries_override(
       config_value: Option<bool>,
       initial_value: bool,
       expected_value: bool,
   ) { ... }
   ```

3. **属性测试**
   - 使用 `proptest` 生成随机 token limit 验证转换正确性
   - 验证各种 slug 格式的 fallback 生成

4. **快照测试**
   - 使用 `insta` 对 fallback 模型结构进行快照测试
   - 便于审查默认值变更

5. **边界条件测试**
   ```rust
   #[test]
   fn large_token_limit_does_not_overflow() {
       let mut config = test_config();
       config.tool_output_token_limit = Some(usize::MAX);
       
       // 验证使用 i64::MAX 作为上限
   }
   ```

### 维护注意事项

1. **配置字段同步**
   - 当 `Config` 新增模型相关字段时，需同步添加测试
   - 参考 `config/mod.rs` 中的模型相关配置

2. **协议类型变更**
   - `ModelInfo` 结构变更时，测试可能需要更新
   - 特别是 `used_fallback_model_metadata` 等标记字段

3. **测试数据一致性**
   - `test_config()` 的返回值变更可能影响测试
   - 考虑使用显式构造替代依赖默认值

4. **警告日志验证**
   - `model_info_from_slug` 会记录警告日志
   - 可考虑使用 `tracing_test` 验证日志输出
