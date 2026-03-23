# output_parser.rs 深入研究

## 场景与职责

`output_parser.rs` 是 Codex Hooks 系统的核心输出解析模块，负责将外部 Hook 命令的 JSON 输出解析为结构化的 Rust 类型。该模块在 Hook 执行流程中扮演"翻译官"角色，将 Claude 风格的 Hook 输出协议转换为内部可处理的数据结构。

**核心职责：**
1. 解析三种 Hook 事件的输出：`SessionStart`、`UserPromptSubmit`、`Stop`
2. 处理 Hook 的阻断决策（Block Decision）逻辑
3. 验证阻断决策的合法性（必须提供非空 reason）
4. 提取通用输出字段（continue、stopReason、suppressOutput、systemMessage）

## 功能点目的

### 1. 结构化输出类型

定义了三种事件特定的输出结构，都包含 `UniversalOutput` 通用部分：

```rust
pub(crate) struct UniversalOutput {
    pub continue_processing: bool,  // 是否继续处理后续 Hook
    pub stop_reason: Option<String>, // 停止原因
    pub suppress_output: bool,       // 是否抑制输出
    pub system_message: Option<String>, // 系统消息（警告级别）
}
```

### 2. 阻断决策验证

`UserPromptSubmit` 和 `Stop` 事件支持阻断决策（`decision: "block"`），但 Claude 协议要求必须提供 `reason`。本模块强制执行此语义规则：

- 如果 `decision` 为 `block` 但 `reason` 为空/空白，则设置 `invalid_block_reason`
- 阻断仅在 `invalid_block_reason` 为 `None` 时才真正生效

### 3. 降级兼容处理

支持纯文本输出作为 `additional_context` 的降级模式（在事件处理器中实现，不在本模块）。

## 具体技术实现

### 关键数据结构

**Wire 类型（JSON 反序列化目标）：**

| Wire 类型 | 来源 | 说明 |
|-----------|------|------|
| `SessionStartCommandOutputWire` | `schema.rs` | SessionStart 输出 |
| `UserPromptSubmitCommandOutputWire` | `schema.rs` | UserPromptSubmit 输出 |
| `StopCommandOutputWire` | `schema.rs` | Stop 输出 |
| `HookUniversalOutputWire` | `schema.rs` | 通用输出字段 |
| `BlockDecisionWire` | `schema.rs` | 阻断决策枚举 |

**内部输出类型：**

```rust
pub(crate) struct SessionStartOutput {
    pub universal: UniversalOutput,
    pub additional_context: Option<String>,
}

pub(crate) struct UserPromptSubmitOutput {
    pub universal: UniversalOutput,
    pub should_block: bool,              // 是否阻断
    pub reason: Option<String>,          // 阻断原因
    pub invalid_block_reason: Option<String>, // 非法阻断原因（用于错误报告）
    pub additional_context: Option<String>,
}

pub(crate) struct StopOutput {
    pub universal: UniversalOutput,
    pub should_block: bool,
    pub reason: Option<String>,
    pub invalid_block_reason: Option<String>,
}
```

### 关键流程

**解析流程（以 `parse_user_prompt_submit` 为例）：**

```
stdout (JSON string)
    ↓
parse_json::<UserPromptSubmitCommandOutputWire>()
    ↓
提取通用字段 → UniversalOutput::from(wire.universal)
    ↓
处理阻断决策：
  - should_block = (wire.decision == Some(Block))
  - 验证 reason 非空
    - 如果为空 → invalid_block_reason = Some(...)
    - 否则 → should_block = true
    ↓
返回 UserPromptSubmitOutput
```

### 核心函数实现

**`parse_json<T>()` - 通用 JSON 解析器：**

```rust
fn parse_json<T>(stdout: &str) -> Option<T>
where
    T: for<'de> serde::Deserialize<'de>,
{
    let trimmed = stdout.trim();
    if trimmed.is_empty() {
        return None;
    }
    let value: serde_json::Value = serde_json::from_str(trimmed).ok()?;
    if !value.is_object() {
        return None;
    }
    serde_json::from_value(value).ok()
}
```

**关键特性：**
- 空字符串返回 `None`（降级到纯文本处理）
- 非对象 JSON 返回 `None`（数组、标量等）
- 使用 `ok()` 转换错误为 `Option`，实现容错解析

**阻断验证逻辑：**

```rust
let should_block = matches!(wire.decision, Some(BlockDecisionWire::Block));
let invalid_block_reason = if should_block
    && match wire.reason.as_deref() {
        Some(reason) => reason.trim().is_empty(),
        None => true,
    } {
    Some(invalid_block_message("UserPromptSubmit"))
} else {
    None
};
```

**最终阻断状态计算：**

```rust
should_block: should_block && invalid_block_reason.is_none()
```

这意味着：即使 Hook 返回 `decision: block`，如果没有提供有效 reason，实际不会阻断，而是标记为失败状态。

### 协议字段映射

**Claude JSON Schema → Rust Wire 类型：**

| JSON 字段 | Wire 字段 | 说明 |
|-----------|-----------|------|
| `continue` | `r#continue: bool` | 关键字转义 |
| `stopReason` | `stop_reason: Option<String>` | camelCase → snake_case |
| `suppressOutput` | `suppress_output: bool` | |
| `systemMessage` | `system_message: Option<String>` | |
| `decision` | `decision: Option<BlockDecisionWire>` | `"block"` 或 null |
| `reason` | `reason: Option<String>` | 阻断原因 |
| `hookSpecificOutput.additionalContext` | `additional_context: Option<String>` | |

## 关键代码路径与文件引用

### 调用关系

```
events/session_start.rs:parse_completed()
    ↓ 调用
    output_parser::parse_session_start()
        ↓ 使用
        schema::SessionStartCommandOutputWire

events/user_prompt_submit.rs:parse_completed()
    ↓ 调用
    output_parser::parse_user_prompt_submit()
        ↓ 使用
        schema::UserPromptSubmitCommandOutputWire

events/stop.rs:parse_completed()
    ↓ 调用
    output_parser::parse_stop()
        ↓ 使用
        schema::StopCommandOutputWire
```

### 文件引用

| 文件 | 引用方式 | 用途 |
|------|----------|------|
| `schema.rs` | `use crate::schema::*` | Wire 类型定义 |
| `schema/generated/*.schema.json` | 通过 `schema.rs` 生成 | JSON Schema 定义 |

### 代码路径

**正常解析路径：**
```
Hook 命令执行 → CommandRunResult
    → events/xxx.rs:parse_completed()
        → output_parser::parse_xxx()
            → parse_json() → 反序列化为 Wire 类型
                → 转换为内部输出类型
                    → 返回给事件处理器
```

**失败降级路径：**
```
JSON 解析失败
    → parse_xxx() 返回 None
        → 事件处理器检查 stdout 是否以 { 或 [ 开头
            - 是 → 标记为 Failed（无效 JSON）
            - 否 → 视为纯文本 additional_context
```

## 依赖与外部交互

### 内部依赖

| 模块 | 依赖内容 | 交互方式 |
|------|----------|----------|
| `schema.rs` | Wire 类型定义 | 直接 use |
| `serde_json` | JSON 反序列化 | parse_json 函数 |

### 外部协议依赖

**Claude Hook 协议：**
- 输入/输出 JSON Schema 定义在 `schema/generated/*.schema.json`
- 协议版本：draft-07
- 字段命名：camelCase
- 阻断决策语义：decision="block" 时必须提供 reason

### 编译时依赖

```toml
[dependencies]
serde = { workspace = true, features = ["derive"] }
serde_json = { workspace = true }
```

## 风险、边界与改进建议

### 已知风险

1. **宽松的解析策略**
   - `parse_json` 使用 `.ok()` 忽略所有错误细节
   - 无法区分：语法错误 vs 类型不匹配 vs 缺少必需字段
   - **影响**：调试困难，无法向用户提供具体错误信息

2. **阻断验证的语义耦合**
   - 阻断 reason 验证硬编码在解析层，而非 Schema 层
   - 如果协议变更（如支持更多决策类型），需要修改解析代码

3. **空字符串处理不一致**
   - `trim().is_empty()` 检查空白字符
   - 但 `"   "` 这样的 reason 仍被视为无效
   - 与 JSON Schema 的 `minLength: 1` 语义不完全对齐

### 边界情况

| 场景 | 行为 | 测试覆盖 |
|------|------|----------|
| 空 stdout | 返回 None | 是（事件处理器中） |
| 纯文本 stdout | 返回 None | 是 |
| 无效 JSON（以 `{` 开头） | 返回 None | 是 |
| decision=block, reason=null | invalid_block_reason 设置 | 是 |
| decision=block, reason="" | invalid_block_reason 设置 | 是 |
| decision=block, reason="   " | invalid_block_reason 设置 | 是 |
| decision=null | should_block=false | 隐含 |

### 改进建议

1. **增强错误报告**
   ```rust
   // 建议：返回 Result<T, ParseError> 而非 Option<T>
   pub enum ParseError {
       EmptyInput,
       InvalidJson(String),
       SchemaMismatch(String),
   }
   ```

2. **将阻断验证移至 Schema 层**
   - 使用 JSON Schema 的 `required` 和 `dependentRequired` 特性
   - 或者使用 `schemars` 的验证注解

3. **统一空值处理**
   - 明确区分 `null`、`""`、空白字符串的处理策略
   - 在 Schema 中使用 `minLength` 和 `pattern` 约束

4. **添加日志记录**
   - 记录解析失败的原始输出（用于调试）
   - 记录阻断决策的详细原因

5. **性能优化**
   - 当前每次解析都进行两次 JSON 解析（Value + 目标类型）
   - 可考虑使用 `serde_json::from_str` 直接解析为目标类型，并在错误时检查是否为对象
