# MCP Server Elicitation Approval Form with Param Summary 研究文档

## 场景与职责

该 Snapshot 展示了 **MCP Server Elicitation** 组件在处理带有参数摘要的工具调用审批表单时的 UI 表现。此场景出现在当 MCP (Model Context Protocol) 服务器请求用户批准执行某个工具调用，并且需要向用户展示该工具调用的具体参数详情时。

**核心职责：**
- 向用户展示工具调用的审批请求，包含详细的参数信息
- 提供清晰的 Allow/Cancel 选项供用户选择
- 支持参数值的截断显示（过长内容自动添加省略号）
- 作为安全网关，确保用户了解即将执行的操作细节

**典型应用场景：**
- Calendar 工具创建事件前的确认
- 文件系统操作前的路径确认
- 外部 API 调用前的参数审查

---

## 功能点目的

### 1. 参数摘要展示
- **目的**：让用户在执行前了解工具调用的具体参数
- **展示内容**：
  - `Calendar: primary` - 使用的日历账户
  - `Title: Roadmap review` - 事件标题
  - `Notes: This is a deliberately long note that should truncate bef...` - 长文本自动截断

### 2. 审批选项
- **Allow**：执行工具调用并继续
- **Cancel**：取消该工具调用

### 3. 进度指示
- 显示 `Field 1/1`，表明当前是单字段表单

### 4. 键盘交互提示
- `enter to submit | esc to cancel` - 底部操作提示

---

## 具体技术实现

### 核心数据结构

```rust
// 审批显示参数结构
struct McpToolApprovalDisplayParam {
    name: String,
    value: Value,
    display_name: String,
}

// 表单请求结构
struct McpServerElicitationFormRequest {
    thread_id: ThreadId,
    server_name: String,
    request_id: McpRequestId,
    message: String,
    approval_display_params: Vec<McpToolApprovalDisplayParam>,  // 参数摘要
    response_mode: McpServerElicitationResponseMode,
    fields: Vec<McpServerElicitationField>,
    tool_suggestion: Option<ToolSuggestionRequest>,
}
```

### 参数格式化与截断

```rust
// 参数值截断常量
const APPROVAL_TOOL_PARAM_VALUE_TRUNCATE_GRAPHEMES: usize = 60;
const APPROVAL_TOOL_PARAM_DISPLAY_LIMIT: usize = 3;

// 格式化参数值
fn format_tool_approval_display_param_value(value: &Value) -> String {
    let formatted = match value {
        Value::String(text) => text.split_whitespace().collect::<Vec<_>>().join(" "),
        _ => {
            let compact_json = value.to_string();
            format_json_compact(&compact_json).unwrap_or(compact_json)
        }
    };
    truncate_text(&formatted, APPROVAL_TOOL_PARAM_VALUE_TRUNCATE_GRAPHEMES)
}
```

### 消息格式化

```rust
fn format_tool_approval_display_message(
    message: &str,
    approval_display_params: &[McpToolApprovalDisplayParam],
) -> String {
    let mut sections = Vec::new();
    if !message.is_empty() {
        sections.push(message.to_string());
    }
    let param_lines = approval_display_params
        .iter()
        .take(APPROVAL_TOOL_PARAM_DISPLAY_LIMIT)
        .map(format_tool_approval_display_param_line)
        .collect::<Vec<_>>();
    if !param_lines.is_empty() {
        sections.push(param_lines.join("\n"));
    }
    sections.join("\n\n")
}
```

### 响应模式

```rust
enum McpServerElicitationResponseMode {
    FormContent,      // 普通表单内容模式
    ApprovalAction,   // 审批动作模式（当前场景）
}
```

---

## 关键代码路径与文件引用

### 主要实现文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/bottom_pane/mcp_server_elicitation.rs` | MCP Server Elicitation 核心实现 |

### 关键常量定义

```rust
// 审批字段和值的常量
const APPROVAL_FIELD_ID: &str = "__approval";
const APPROVAL_ACCEPT_ONCE_VALUE: &str = "accept";
const APPROVAL_CANCEL_VALUE: &str = "cancel";

// 元数据键
const APPROVAL_META_KIND_KEY: &str = "codex_approval_kind";
const APPROVAL_META_KIND_MCP_TOOL_CALL: &str = "mcp_tool_call";
const APPROVAL_TOOL_PARAMS_DISPLAY_KEY: &str = "tool_params_display";
```

### 参数解析流程

```rust
fn parse_tool_approval_display_params(meta: Option<&Value>) -> Vec<McpToolApprovalDisplayParam> {
    // 优先使用 tool_params_display（带显示名称）
    let display_params = meta
        .get(APPROVAL_TOOL_PARAMS_DISPLAY_KEY)
        .and_then(Value::as_array)
        .map(|display_params| {
            display_params
                .iter()
                .filter_map(parse_tool_approval_display_param)
                .collect()
        })
        .unwrap_or_default();
    
    if !display_params.is_empty() {
        return display_params;
    }
    
    // 回退到 tool_params（原始参数对象）
    // ...
}
```

### 测试代码位置

```rust
// 测试文件中的 snapshot 测试
#[test]
fn mcp_server_elicitation_approval_form_with_param_summary() {
    // 测试带参数摘要的审批表单渲染
}
```

---

## 依赖与外部交互

### 外部协议依赖

| 依赖 | 用途 |
|-----|------|
| `codex_app_server_protocol::McpServerElicitationRequest` | MCP 请求协议定义 |
| `codex_protocol::approvals::ElicitationAction` | 审批动作枚举 |
| `codex_protocol::mcp::RequestId` | MCP 请求 ID |

### 内部模块依赖

```rust
use crate::bottom_pane::ChatComposer;           // 文本输入组件
use crate::bottom_pane::scroll_state::ScrollState;  // 滚动状态管理
use crate::text_formatting::truncate_text;      // 文本截断工具
use crate::text_formatting::format_json_compact; // JSON 格式化
```

### 事件交互

```rust
// 取消操作发送事件
fn dispatch_cancel(&self) {
    self.app_event_tx.resolve_elicitation(
        self.request.thread_id,
        self.request.server_name.clone(),
        self.request.request_id.clone(),
        ElicitationAction::Cancel,
        /*content*/ None,
        /*meta*/ None,
    );
}
```

---

## 风险、边界与改进建议

### 当前风险

1. **参数截断信息丢失**
   - 长参数值被截断后可能导致用户无法看到完整信息
   - 建议：提供展开/查看完整参数的功能

2. **参数数量限制**
   - 仅显示前 3 个参数 (`APPROVAL_TOOL_PARAM_DISPLAY_LIMIT`)
   - 建议：当参数超过限制时显示 "+N more" 提示

3. **无持久化选项**
   - 此场景下仅提供单次 Allow/Cancel，无 session/always 选项
   - 对比：带 session persist 的版本提供了更多选择

### 边界情况

| 场景 | 处理方式 |
|-----|---------|
| 参数值为空 | 不显示该参数行 |
| 参数值为复杂 JSON | 使用紧凑 JSON 格式 |
| 所有参数都为空 | 仅显示消息，无参数区域 |
| 参数名称为空 | 过滤掉该参数 |

### 改进建议

1. **交互增强**
   ```rust
   // 建议：添加参数展开功能
   fn render_param_with_expand(&self, param: &McpToolApprovalDisplayParam) -> Line {
       if param.value.len() > TRUNCATE_LIMIT {
           // 显示 "... [press 'v' to view full]"
       }
   }
   ```

2. **视觉优化**
   - 参数名使用不同颜色（如 dim）与参数值区分
   - 添加参数类型图标标识（如 📅 表示日历）

3. **可访问性**
   - 为屏幕阅读器提供完整的参数信息（不截断）
   - 添加键盘快捷键直接跳转到参数区域

4. **安全增强**
   - 对于敏感参数（如密码、密钥）提供掩码显示
   - 添加参数变更检测，如果参数在审批过程中被修改则重新提示
