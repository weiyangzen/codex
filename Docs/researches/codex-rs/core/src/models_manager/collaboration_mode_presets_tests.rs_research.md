# collaboration_mode_presets_tests.rs 研究文档

## 场景与职责

`collaboration_mode_presets_tests.rs` 是 `collaboration_mode_presets.rs` 的配套测试模块，通过 `#[path = "collaboration_mode_presets_tests.rs"]` 属性在父模块中条件编译引入（`#[cfg(test)]`）。

该测试文件的核心职责：
1. 验证协作模式预设的名称与模式定义一致
2. 确保模板占位符被正确替换
3. 验证功能开关（feature flags）对生成内容的影响
4. 作为回归测试防止模板修改引入错误

## 功能点目的

### 1. 预设名称一致性测试 (`preset_names_use_mode_display_names`)
- **目的**：确保预设名称与 `ModeKind::display_name()` 返回值一致
- **验证点**：
  - Plan 预设名称等于 `ModeKind::Plan.display_name()`
  - Default 预设名称等于 `ModeKind::Default.display_name()`
  - Plan 预设的推理力度正确设置为 `ReasoningEffort::Medium`

### 2. 模板占位符替换测试 (`default_mode_instructions_replace_mode_names_placeholder`)
- **目的**：验证 Default 模式指令生成时所有占位符被正确替换
- **验证点**：
  - `{{KNOWN_MODE_NAMES}}` 被替换为实际模式名称列表
  - `{{REQUEST_USER_INPUT_AVAILABILITY}}` 被替换为可用性说明
  - `{{ASKING_QUESTIONS_GUIDANCE}}` 被替换为指导文本
  - 生成的指令包含预期的已知模式名称片段
  - 当功能启用时，指令包含 `request_user_input` 工具引用

### 3. 功能开关影响测试 (`default_mode_instructions_use_plain_text_questions_when_feature_disabled`)
- **目的**：验证 `default_mode_request_user_input` 配置为 `false` 时的回退行为
- **验证点**：
  - 不包含 `request_user_input` 工具引用
  - 包含纯文本提问指导

## 具体技术实现

### 测试结构

```rust
use super::*;  // 引入父模块所有内容
use pretty_assertions::assert_eq;  // 提供清晰的差异输出

#[test]
fn test_name() {
    // 测试实现
}
```

### 测试数据构造

#### 功能启用配置
```rust
CollaborationModesConfig {
    default_mode_request_user_input: true,
}
```

#### 默认配置（功能禁用）
```rust
CollaborationModesConfig::default()  // default_mode_request_user_input: false
```

### 验证技术

#### 字符串包含验证
```rust
assert!(!default_instructions.contains(KNOWN_MODE_NAMES_PLACEHOLDER));
assert!(default_instructions.contains(&expected_snippet));
```

#### 预期片段构造
```rust
let known_mode_names = format_mode_names(&TUI_VISIBLE_COLLABORATION_MODES);
let expected_snippet = format!("Known mode names are {known_mode_names}.");
```

## 关键代码路径与文件引用

### 被测试的函数
| 函数 | 所在文件 | 测试覆盖 |
|------|----------|----------|
| `plan_preset()` | `collaboration_mode_presets.rs:30` | 名称、推理力度 |
| `default_preset()` | `collaboration_mode_presets.rs:40` | 名称、指令生成 |
| `default_mode_instructions()` | `collaboration_mode_presets.rs:50` | 占位符替换、功能开关 |
| `format_mode_names()` | `collaboration_mode_presets.rs:71` | 名称格式化 |
| `request_user_input_availability_message()` | `collaboration_mode_presets.rs:81` | 可用性消息 |

### 测试的常量
| 常量 | 验证点 |
|------|--------|
| `KNOWN_MODE_NAMES_PLACEHOLDER` | 验证不存在于最终指令 |
| `REQUEST_USER_INPUT_AVAILABILITY_PLACEHOLDER` | 验证不存在于最终指令 |
| `ASKING_QUESTIONS_GUIDANCE_PLACEHOLDER` | 验证不存在于最终指令 |

### 外部类型依赖
| 类型 | 来源 | 用途 |
|------|------|------|
| `ModeKind` | `codex_protocol::config_types` | 模式类型枚举 |
| `ReasoningEffort` | `codex_protocol::openai_models` | 推理力度枚举 |
| `TUI_VISIBLE_COLLABORATION_MODES` | `codex_protocol::config_types` | 可见模式常量 |

## 依赖与外部交互

### 测试框架
- **测试运行器**：Rust 内置测试框架 (`#[test]`)
- **断言库**：`pretty_assertions`（提供更清晰的测试失败输出）

### 被测模块接口
```rust
// 父模块中条件引入测试模块
#[cfg(test)]
#[path = "collaboration_mode_presets_tests.rs"]
mod tests;
```

### 测试可见性
- 测试使用 `use super::*` 访问父模块的私有函数和常量
- 这是 Rust 单元测试的标准模式，允许测试内部实现细节

## 风险、边界与改进建议

### 测试覆盖率分析

| 被测功能 | 覆盖状态 | 说明 |
|----------|----------|------|
| `plan_preset()` | ✅ 完全覆盖 | 名称、推理力度验证 |
| `default_preset()` | ⚠️ 部分覆盖 | 未验证 `model` 和 `reasoning_effort` 字段 |
| `default_mode_instructions()` | ✅ 完全覆盖 | 占位符替换、功能开关 |
| `format_mode_names()` | ⚠️ 间接覆盖 | 通过指令生成间接测试 |
| `request_user_input_availability_message()` | ⚠️ 间接覆盖 | 通过指令内容间接测试 |
| `asking_questions_guidance_message()` | ⚠️ 间接覆盖 | 通过指令内容间接测试 |

### 缺失测试场景

1. **边界条件测试**
   - `format_mode_names` 的空列表场景
   - `format_mode_names` 的单元素场景
   - `format_mode_names` 的双元素场景

2. **异常场景测试**
   - 模板文件缺失（编译时错误，难以测试）
   - 未知模式类型的处理

3. **更多功能组合**
   - 不同 `ModeKind` 组合的 `allows_request_user_input` 行为
   - 多语言模板支持（如果实现）

### 改进建议

1. **参数化测试**
   ```rust
   #[test_case(ModeKind::Plan, "Plan")]
   #[test_case(ModeKind::Default, "Default")]
   fn preset_name_matches_display_name(mode: ModeKind, expected: &str) {
       // 减少重复代码
   }
   ```

2. **快照测试**
   - 使用 `insta` crate 对生成的指令进行快照测试
   - 便于审查模板修改的影响

3. **模糊测试**
   - 对 `format_mode_names` 进行模糊测试
   - 验证各种输入组合的输出正确性

4. **文档测试**
   - 为公共函数添加文档测试示例
   ```rust
   /// ```
   /// let names = format_mode_names(&[ModeKind::Plan, ModeKind::Default]);
   /// assert_eq!(names, "Plan and Default");
   /// ```
   ```

### 维护注意事项

1. **模板修改同步**
   - 当修改 `plan.md` 或 `default.md` 模板时，需同步更新测试断言
   - 建议将关键文本片段提取为常量，便于统一修改

2. **新功能测试**
   - 新增 `CollaborationModesConfig` 字段时，需添加对应的测试用例
   - 新增模式类型时，需扩展预设名称测试

3. **测试隔离性**
   - 当前测试依赖 `TUI_VISIBLE_COLLABORATION_MODES` 常量
   - 如果该常量值变化，测试可能需要调整
