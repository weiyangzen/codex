# MCP Server Elicitation Approval Form with Param Summary - 研究文档

## 1. 场景与职责

### 1.1 测试场景

此快照测试验证 **MCP 工具调用审批表单在带有参数摘要显示时的 UI 渲染效果**。具体场景是：

- **触发条件**: 用户通过 MCP 服务器调用工具（如 Google Calendar 创建事件）时，系统需要用户确认
- **数据展示**: 审批表单不仅显示基本消息，还展示工具调用的关键参数（如 Calendar ID、Title、Notes）
- **参数限制**: 最多显示 3 个参数（`APPROVAL_TOOL_PARAM_DISPLAY_LIMIT = 3`），超长值会被截断（`APPROVAL_TOOL_PARAM_VALUE_TRUNCATE_GRAPHEMES = 60`）

### 1.2 组件职责

`McpServerElicitationOverlay` 组件在此场景中的职责：

1. **参数解析与格式化**: 从 `meta` 数据中提取 `tool_params_display` 或 `tool_params`，格式化为可读的键值对
2. **消息组装**: 将原始消息与参数摘要合并，形成完整的审批提示
3. **选项渲染**: 提供 "Allow" 和 "Cancel" 两个操作选项
4. **用户交互**: 处理用户选择并通过 `AppEvent::SubmitThreadOp` 发送审批结果

---

## 2. 功能点目的

### 2.1 参数摘要显示的目的

```rust
// 关键常量定义
const APPROVAL_TOOL_PARAM_DISPLAY_LIMIT: usize = 3;
const APPROVAL_TOOL_PARAM_VALUE_TRUNCATE_GRAPHEMES: usize = 60;
```

**设计意图**：
- **信息透明**: 让用户在批准前清楚了解工具将要执行的具体操作
- **防止信息过载**: 限制显示参数数量和长度，避免 UI 被大量文本淹没
- **安全确认**: 通过展示关键参数（如日历 ID、事件标题）帮助用户验证操作正确性

### 2.2 参数来源优先级

```rust
fn parse_tool_approval_display_params(meta: Option<&Value>) -> Vec<McpToolApprovalDisplayParam> {
    // 1. 优先使用显式定义的 display_params（带 display_name）
    let display_params = meta
        .get(APPROVAL_TOOL_PARAMS_DISPLAY_KEY)
        .and_then(Value::as_array)
        ...
    
    // 2. 回退到普通 tool_params（使用原始字段名）
    let mut fallback_params = meta
        .get(APPROVAL_TOOL_PARAMS_KEY)
        .and_then(Value::as_object)
        ...
    fallback_params.sort_by(|left, right| left.name.cmp(&right.name));
    fallback_params
}
```

---

## 3. 具体技术实现

### 3.1 数据结构

```rust
#[derive(Clone, Debug, PartialEq)]
struct McpToolApprovalDisplayParam {
    name: String,        // 原始字段名（如 "calendar_id"）
    value: Value,        // 参数值
    display_name: String, // 显示名称（如 "Calendar"）
}
```

### 3.2 消息格式化流程

```rust
fn format_tool_approval_display_message(
    message: &str,
    approval_display_params: &[McpToolApprovalDisplayParam],
) -> String {
    // 1. 收集消息和参数字符串
    let mut sections = Vec::new();
    if !message.is_empty() {
        sections.push(message.to_string());
    }
    
    // 2. 格式化参数行（最多3个）
    let param_lines = approval_display_params
        .iter()
        .take(APPROVAL_TOOL_PARAM_DISPLAY_LIMIT)
        .map(format_tool_approval_display_param_line)
        .collect::<Vec<_>>();
    
    // 3. 合并所有部分
    sections.join("\n\n")
}
```

### 3.3 参数值格式化

```rust
fn format_tool_approval_display_param_value(value: &Value) -> String {
    let formatted = match value {
        // 字符串：规范化空白字符
        Value::String(text) => text.split_whitespace().collect::<Vec<_>>().join(" "),
        // 其他类型：使用紧凑 JSON 格式
        _ => {
            let compact_json = value.to_string();
            format_json_compact(&compact_json).unwrap_or(compact_json)
        }
    };
    // 截断超长值
    truncate_text(&formatted, APPROVAL_TOOL_PARAM_VALUE_TRUNCATE_GRAPHEMES)
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/bottom_pane/mcp_server_elicitation.rs` | 主要实现文件，包含审批表单逻辑 |
| `codex-rs/tui/src/bottom_pane/chat_composer.rs` | ChatComposer 集成，用于文本输入 |

### 4.2 关键代码路径

**1. 请求解析路径**（行 203-324）:
```rust
impl McpServerElicitationFormRequest {
    pub(crate) fn from_event(...) -> Option<Self> {
        // 1. 检测是否为工具审批请求
        let is_tool_approval = meta
            .and_then(|meta| meta.get(APPROVAL_META_KIND_KEY))
            .and_then(Value::as_str)
            == Some(APPROVAL_META_KIND_MCP_TOOL_CALL);
        
        // 2. 解析显示参数
        let approval_display_params = if is_tool_approval_action {
            parse_tool_approval_display_params(meta.as_ref())
        } else { ... };
    }
}
```

**2. 参数解析路径**（行 399-434）:
```rust
fn parse_tool_approval_display_params(meta: Option<&Value>) -> Vec<McpToolApprovalDisplayParam>
```

**3. 消息格式化路径**（行 457-500）:
```rust
fn format_tool_approval_display_message(...) -> String
fn format_tool_approval_display_param_line(...) -> String
fn format_tool_approval_display_param_value(...) -> String
```

**4. 渲染路径**（行 1220-1244）:
```rust
fn render_prompt(&self, area: Rect, buf: &mut Buffer) {
    let answered = self.is_current_field_answered();
    for (offset, line) in self.wrapped_prompt_lines(area.width).iter().enumerate() {
        // 未回答时显示青色高亮
        let line = if answered { ... } else { ...cyan() };
    }
}
```

### 4.3 测试代码位置

**快照测试定义**（行 2389-2437）:
```rust
#[test]
fn approval_form_tool_approval_with_param_summary_snapshot() {
    let request = McpServerElicitationFormRequest::from_event(
        thread_id,
        form_request(
            "Allow Calendar to create an event",
            empty_object_schema(),
            tool_approval_meta(
                &[],  // 无持久化选项
                Some(serde_json::json!({
                    "calendar_id": "primary",
                    "title": "Roadmap review",
                    "notes": "This is a deliberately long note...",
                    "ignored_after_limit": "fourth param",  // 第4个参数被忽略
                })),
                Some(vec![
                    ("calendar_id", ..., "Calendar"),
                    ("title", ..., "Title"),
                    ("notes", ..., "Notes"),
                    ("ignored_after_limit", ..., "Ignored"),  // 被忽略
                ]),
            ),
        ),
    );
    insta::assert_snapshot!("mcp_server_elicitation_approval_form_with_param_summary", ...);
}
```

---

## 5. 依赖与外部交互

### 5.1 外部依赖

| 依赖 | 用途 |
|-----|------|
| `serde_json::Value` | JSON 参数解析与序列化 |
| `ratatui` | UI 渲染框架 |
| `textwrap` | 文本自动换行 |
| `unicode_width` | Unicode 字符串宽度计算 |

### 5.2 协议依赖

```rust
use codex_protocol::approvals::ElicitationAction;
use codex_protocol::approvals::ElicitationRequest;
use codex_protocol::approvals::ElicitationRequestEvent;
use codex_protocol::mcp::RequestId as McpRequestId;
use codex_protocol::protocol::Op;
```

### 5.3 事件交互

**输出事件** - 审批结果通过 `AppEvent::SubmitThreadOp` 发送：

```rust
fn submit_answers(&mut self) {
    self.app_event_tx.send(AppEvent::SubmitThreadOp {
        thread_id: self.request.thread_id,
        op: Op::ResolveElicitation {
            server_name: self.request.server_name.clone(),
            request_id: self.request.request_id.clone(),
            decision: ElicitationAction::Accept,  // 或 Cancel
            content: None,
            meta: None,
        },
    });
}
```

---

## 6. 风险边界与改进建议

### 6.1 当前风险边界

**1. 参数数量限制**
- **限制**: 最多显示 3 个参数
- **风险**: 重要参数可能被隐藏，用户无法完整了解操作细节
- **代码位置**: `APPROVAL_TOOL_PARAM_DISPLAY_LIMIT = 3`

**2. 参数值截断**
- **限制**: 最多 60 个字符
- **风险**: 长文本（如详细的事件描述）被截断，可能导致信息丢失
- **代码位置**: `APPROVAL_TOOL_PARAM_VALUE_TRUNCATE_GRAPHEMES = 60`

**3. 参数排序**
- **行为**: 使用 `tool_params` 回退时按字母顺序排序
- **风险**: 关键参数可能排在次要参数之后

### 6.2 改进建议

**1. 可展开参数列表**
```rust
// 建议：添加 "Show more" 选项展开完整参数
enum ParamDisplayMode {
    Collapsed(usize),  // 显示前 N 个
    Expanded,          // 显示全部
}
```

**2. 参数重要性标记**
```rust
// 建议：在 meta 中标记参数重要性
struct McpToolApprovalDisplayParam {
    name: String,
    value: Value,
    display_name: String,
    priority: u8,  // 新增：优先级，高优先级优先显示
}
```

**3. 长文本折叠**
```rust
// 建议：支持多行折叠而非简单截断
fn format_tool_approval_display_param_value(value: &Value, max_lines: usize) -> Vec<String>
```

**4. 参数验证**
```rust
// 建议：添加参数值验证，敏感信息脱敏
fn sanitize_sensitive_params(params: &mut Vec<McpToolApprovalDisplayParam>) {
    // 对 API keys、tokens 等敏感字段进行脱敏处理
}
```

### 6.3 测试覆盖建议

**当前测试覆盖**:
- ✅ 基本参数显示
- ✅ 参数截断
- ✅ 参数数量限制

**建议补充**:
- ⬜ 敏感参数脱敏测试
- ⬜ 超长参数列表滚动测试
- ⬜ 不同字符集（中文、阿拉伯文等）显示测试
- ⬜ 高对比度/无障碍模式下的可读性测试

---

## 7. 快照内容分析

### 7.1 快照输出

```
  Field 1/1
  Allow Calendar to create an event
  
  Calendar: primary
  Title: Roadmap review
  Notes: This is a deliberately long note that should truncate bef...
  
  › 1. Allow   Run the tool and continue.
    2. Cancel  Cancel this tool call
  
  enter to submit | esc to cancel
```

### 7.2 UI 结构解析

| 行 | 内容 | 说明 |
|---|------|------|
| 1 | `Field 1/1` | 字段进度指示器 |
| 2 | `Allow Calendar to create an event` | 主消息 |
| 4-6 | `Calendar: primary` ... | 参数摘要（3个参数） |
| 8-9 | `› 1. Allow ...` / `2. Cancel ...` | 操作选项（选中状态用 `›` 标记） |
| 12 | `enter to submit | esc to cancel` | 底部提示 |

### 7.3 关键观察

1. **参数截断**: `Notes` 值在 60 字符处被截断并添加 `...`
2. **选中状态**: 选项 `1. Allow` 前有 `›` 标记，表示当前选中
3. **无持久化选项**: 此场景未启用 session/always 持久化，仅显示 Allow/Cancel
