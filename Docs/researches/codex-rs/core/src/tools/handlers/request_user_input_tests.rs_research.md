# request_user_input_tests.rs 研究文档

## 场景与职责

`request_user_input_tests.rs` 是 `request_user_input.rs` 的配套测试文件，负责验证用户输入请求工具的模式可用性逻辑。测试聚焦于协作模式与工具可用性的映射关系，以及特性开关 `default_mode_request_user_input` 的行为。

## 功能点目的

### 1. 模式可用性默认行为测试
- **Plan 模式**: 验证默认可用
- **Default 模式**: 验证默认禁用
- **Execute 模式**: 验证禁用
- **PairProgramming 模式**: 验证禁用

### 2. 特性开关测试
- **关闭状态**: Default 模式下工具不可用
- **开启状态**: Default 模式下工具可用
- **其他模式**: 特性开关不影响其他模式

### 3. 工具描述生成测试
- **关闭状态**: 描述只提及 Plan 模式
- **开启状态**: 描述提及 Default 和 Plan 模式

## 具体技术实现

### 测试基础设施

```rust
use super::*;
use pretty_assertions::assert_eq;
```

### 测试用例详解

#### 1. 模式默认可用性测试

```rust
#[test]
fn request_user_input_mode_availability_defaults_to_plan_only() {
    assert!(ModeKind::Plan.allows_request_user_input());
    assert!(!ModeKind::Default.allows_request_user_input());
    assert!(!ModeKind::Execute.allows_request_user_input());
    assert!(!ModeKind::PairProgramming.allows_request_user_input());
}
```

**验证点**:
- `ModeKind::Plan.allows_request_user_input()` 返回 `true`
- 其他模式返回 `false`

**依赖**:
- `codex_protocol::config_types::ModeKind::allows_request_user_input()`

#### 2. 特性开关测试

```rust
#[test]
fn request_user_input_unavailable_messages_respect_default_mode_feature_flag() {
    // Plan 模式总是可用
    assert_eq!(
        request_user_input_unavailable_message(ModeKind::Plan, false),
        None
    );
    
    // Default 模式，特性关闭时不可用
    assert_eq!(
        request_user_input_unavailable_message(ModeKind::Default, false),
        Some("request_user_input is unavailable in Default mode".to_string())
    );
    
    // Default 模式，特性开启时可用
    assert_eq!(
        request_user_input_unavailable_message(ModeKind::Default, true),
        None
    );
    
    // Execute 模式总是不可用（不受特性开关影响）
    assert_eq!(
        request_user_input_unavailable_message(ModeKind::Execute, false),
        Some("request_user_input is unavailable in Execute mode".to_string())
    );
    
    // PairProgramming 模式总是不可用
    assert_eq!(
        request_user_input_unavailable_message(ModeKind::PairProgramming, false),
        Some("request_user_input is unavailable in Pair Programming mode".to_string())
    );
}
```

**验证点**:
| 模式 | 特性关闭 | 特性开启 |
|-----|---------|---------|
| Plan | 可用 (None) | 可用 (None) |
| Default | 不可用 (Some) | 可用 (None) |
| Execute | 不可用 (Some) | 不可用 (Some) |
| PairProgramming | 不可用 (Some) | 不可用 (Some) |

#### 3. 工具描述生成测试

```rust
#[test]
fn request_user_input_tool_description_mentions_available_modes() {
    // 特性关闭时，只提及 Plan 模式
    assert_eq!(
        request_user_input_tool_description(false),
        "Request user input for one to three short questions and wait for the response. This tool is only available in Plan mode."
    );
    
    // 特性开启时，提及 Default 和 Plan 模式
    assert_eq!(
        request_user_input_tool_description(true),
        "Request user input for one to three short questions and wait for the response. This tool is only available in Default or Plan mode."
    );
}
```

**验证点**:
- 描述准确反映可用模式
- 语法正确（单数/复数、连接词）

## 关键代码路径与文件引用

### 被测试的主要文件
- `codex-rs/core/src/tools/handlers/request_user_input.rs` - 主实现

### 测试的函数
```rust
use super::request_user_input_unavailable_message;
use super::request_user_input_tool_description;
use super::ModeKind;
```

### 依赖类型
```rust
use codex_protocol::config_types::ModeKind;
```

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|-----|------|
| `pretty_assertions::assert_eq` | 更好的 diff 输出 |
| `codex_protocol::config_types::ModeKind` | 协作模式枚举 |

### 测试数据
- 使用硬编码的期望值字符串
- 测试所有四种协作模式

## 风险、边界与改进建议

### 潜在风险
1. **模式扩展**: 如果添加新的协作模式，测试可能需要更新
2. **描述变更**: 工具描述文本变更会导致测试失败
3. **本地化**: 当前测试假设英文描述，本地化后需要调整

### 边界情况

| 边界情况 | 覆盖状态 | 说明 |
|---------|---------|------|
| 特性开关边界值 | ❌ 未覆盖 | 只测试 true/false，未测试其他值 |
| 空模式列表 | ❌ 未覆盖 | `format_allowed_modes` 返回 "no modes" |
| 所有模式可用 | ❌ 未覆盖 | 理论上可能所有模式都允许 |
| 三模式可用 | ❌ 未覆盖 | "modes: A,B,C" 格式 |

### 改进建议

1. **添加边界测试**:
   ```rust
   #[test]
   fn format_allowed_modes_handles_empty() {
       // 模拟所有模式都不可用的情况
       // 验证返回 "no modes"
   }
   
   #[test]
   fn format_allowed_modes_handles_three_modes() {
       // 模拟三个模式都可用的情况
       // 验证返回 "modes: A,B,C" 格式
   }
   ```

2. **添加参数解析测试**:
   ```rust
   #[test]
   fn rejects_empty_questions() {
       // 验证空 questions 数组被拒绝
   }
   
   #[test]
   fn rejects_questions_without_options() {
       // 验证缺少 options 的问题被拒绝
   }
   
   #[test]
   fn rejects_empty_options() {
       // 验证空 options 数组被拒绝
   }
   ```

3. **添加序列化测试**:
   ```rust
   #[test]
   fn response_serialization() {
       // 验证响应正确序列化为 JSON
   }
   ```

4. **添加集成测试**:
   ```rust
   #[tokio::test]
   async fn handler_rejects_in_unavailable_mode() {
       // 验证 handler 在不可用模式下返回错误
   }
   ```

5. **改进测试组织**:
   ```rust
   mod mode_availability { ... }
   mod feature_flag { ... }
   mod description { ... }
   mod validation { ... }
   ```

### 代码质量观察
- 测试简洁，聚焦核心逻辑
- 使用 `pretty_assertions` 提供更好的失败输出
- 测试命名清晰，描述性强
- 建议添加更多负面测试（错误路径）

### 测试覆盖率
当前测试覆盖：
- ✅ 模式默认可用性
- ✅ 特性开关行为
- ✅ 工具描述生成

未覆盖：
- ❌ Handler 实际调用
- ❌ 参数解析
- ❌ 验证逻辑
- ❌ 错误处理
- ❌ 序列化/反序列化
- ❌ 会话交互

建议添加更多集成测试，覆盖完整的 handler 调用流程。
