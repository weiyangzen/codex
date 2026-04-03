# MCP Server Elicitation Approval Form with Session Persist 研究文档

## 场景与职责

该 Snapshot 展示了 **MCP Server Elicitation** 组件在处理带有会话持久化选项的工具调用审批表单时的 UI 表现。此场景是工具审批的高级模式，允许用户不仅决定当前操作，还能设置该决定是否在未来自动应用。

**核心职责：**
- 提供多层次的审批选项，平衡安全性与便利性
- 支持用户记忆审批选择，减少重复确认
- 作为智能助手与外部工具之间的安全网关

**典型应用场景：**
- 频繁使用的工具（如文件读取、Git 操作）
- 可信的 MCP 服务器连接
- 用户希望减少中断的工作流程

---

## 功能点目的

### 1. 四级审批选项

| 选项 | 描述 | 使用场景 |
|-----|------|---------|
| **Allow** | 仅执行当前工具调用 | 一次性操作，不确定是否信任 |
| **Allow for this session** | 执行并记住本次会话的选择 | 当前工作会话中频繁使用 |
| **Always allow** | 执行并永久记住选择 | 完全信任的工具/服务器 |
| **Cancel** | 取消当前工具调用 | 不确定或不想执行 |

### 2. 选项描述说明
每个选项都配有详细的说明文字，帮助用户理解选择的后果：
- "Run the tool and continue."
- "Run the tool and remember this choice for this session."
- "Run the tool and remember this choice for future tool calls."
- "Cancel this tool call"

### 3. 进度指示
- `Field 1/1` - 单字段表单

### 4. 键盘交互
- 支持数字快捷键（1-4）快速选择
- `enter to submit | esc to cancel`

---

## 具体技术实现

### 持久化模式常量

```rust
// 持久化模式常量
const APPROVAL_PERSIST_KEY: &str = "persist";
const APPROVAL_PERSIST_SESSION_VALUE: &str = "session";
const APPROVAL_PERSIST_ALWAYS_VALUE: &str = "always";

// 审批值常量
const APPROVAL_ACCEPT_ONCE_VALUE: &str = "accept";
const APPROVAL_ACCEPT_SESSION_VALUE: &str = "accept_session";
const APPROVAL_ACCEPT_ALWAYS_VALUE: &str = "accept_always";
const APPROVAL_CANCEL_VALUE: &str = "cancel";
```

### 持久化支持检测

```rust
fn tool_approval_supports_persist_mode(meta: Option<&Value>, expected_mode: &str) -> bool {
    let Some(persist) = meta
        .and_then(Value::as_object)
        .and_then(|meta| meta.get(APPROVAL_PERSIST_KEY))
    else {
        return false;
    };

    match persist {
        Value::String(value) => value == expected_mode,
        Value::Array(values) => values
            .iter()
            .filter_map(Value::as_str)
            .any(|value| value == expected_mode),
        _ => false,
    }
}
```

### 动态选项构建

```rust
let mut options = vec![McpServerElicitationOption {
    label: "Allow".to_string(),
    description: Some("Run the tool and continue.".to_string()),
    value: Value::String(APPROVAL_ACCEPT_ONCE_VALUE.to_string()),
}];

// 条件添加 session 持久化选项
if is_tool_approval_action
    && tool_approval_supports_persist_mode(meta.as_ref(), APPROVAL_PERSIST_SESSION_VALUE)
{
    options.push(McpServerElicitationOption {
        label: "Allow for this session".to_string(),
        description: Some(
            "Run the tool and remember this choice for this session.".to_string(),
        ),
        value: Value::String(APPROVAL_ACCEPT_SESSION_VALUE.to_string()),
    });
}

// 条件添加 always 持久化选项
if is_tool_approval_action
    && tool_approval_supports_persist_mode(meta.as_ref(), APPROVAL_PERSIST_ALWAYS_VALUE)
{
    options.push(McpServerElicitationOption {
        label: "Always allow".to_string(),
        description: Some(
            "Run the tool and remember this choice for future tool calls.".to_string(),
        ),
        value: Value::String(APPROVAL_ACCEPT_ALWAYS_VALUE.to_string()),
    });
}

options.push(McpServerElicitationOption {
    label: "Cancel".to_string(),
    description: Some("Cancel this tool call".to_string()),
    value: Value::String(APPROVAL_CANCEL_VALUE.to_string()),
});
```

### 响应模式与元数据

```rust
enum McpServerElicitationResponseMode {
    FormContent,
    ApprovalAction,  // 当前场景使用此模式
}

// 提交时根据选择构建元数据
fn submit_answers(&mut self) {
    if self.request.response_mode == McpServerElicitationResponseMode::ApprovalAction {
        let (decision, meta) = match self.field_value(0).as_ref().and_then(Value::as_str) {
            Some(APPROVAL_ACCEPT_ONCE_VALUE) => (ElicitationAction::Accept, None),
            Some(APPROVAL_ACCEPT_SESSION_VALUE) => (
                ElicitationAction::Accept,
                Some(serde_json::json!({
                    APPROVAL_PERSIST_KEY: APPROVAL_PERSIST_SESSION_VALUE,
                })),
            ),
            Some(APPROVAL_ACCEPT_ALWAYS_VALUE) => (
                ElicitationAction::Accept,
                Some(serde_json::json!({
                    APPROVAL_PERSIST_KEY: APPROVAL_PERSIST_ALWAYS_VALUE,
                })),
            ),
            Some(APPROVAL_CANCEL_VALUE) => (ElicitationAction::Cancel, None),
            _ => (ElicitationAction::Cancel, None),
        };
        
        self.app_event_tx.resolve_elicitation(
            self.request.thread_id,
            self.request.server_name.clone(),
            self.request.request_id.clone(),
            decision,
            /*content*/ None,
            meta,  // 包含持久化信息
        );
    }
}
```

---

## 关键代码路径与文件引用

### 主要实现文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/bottom_pane/mcp_server_elicitation.rs` | MCP Server Elicitation 核心实现 |

### 关键函数

```rust
// 行号参考（基于代码分析）
fn tool_approval_supports_persist_mode(meta: Option<&Value>, expected_mode: &str) -> bool
// 位于 ~431-447 行

fn from_parts(...) -> Option<Self>
// 动态构建选项逻辑位于 ~289-362 行

fn submit_answers(&mut self)
// 提交处理逻辑位于 ~1146-1213 行
```

### 元数据格式

服务器在请求中通过 meta 字段指示支持的持久化模式：

```json
{
  "codex_approval_kind": "mcp_tool_call",
  "persist": ["session", "always"]
}
```

或单模式：

```json
{
  "codex_approval_kind": "mcp_tool_call",
  "persist": "session"
}
```

---

## 依赖与外部交互

### 协议依赖

| 依赖 | 用途 |
|-----|------|
| `codex_protocol::approvals::ElicitationAction` | 审批动作（Accept/Decline/Cancel） |
| `codex_protocol::approvals::ElicitationRequest` | 审批请求结构 |
| `serde_json::Value` | 元数据传递 |

### 事件系统交互

```rust
// 解析 elicitation 时发送事件
self.app_event_tx.resolve_elicitation(
    thread_id,
    server_name,
    request_id,
    ElicitationAction::Accept,  // 或 Cancel
    None,  // content
    Some(serde_json::json!({
        "persist": "session"  // 或 "always"
    })),  // meta
);
```

### 与后端持久化存储的关系

- TUI 仅负责传递持久化意图（通过 meta 字段）
- 实际的持久化存储和后续自动审批逻辑由后端（app-server 或 core）处理
- 持久化键通常按 `(server_name, tool_name)` 组合存储

---

## 风险、边界与改进建议

### 安全风险

1. **Always allow 的误用风险**
   - 用户可能不小心选择了 "Always allow" 而忘记撤销
   - **建议**：
     - 添加视觉警告（如 🔓 图标）
     - 定期提醒用户审查已授权的持久化设置
     - 提供快速撤销入口

2. **Session 定义不明确**
   - 用户可能不清楚 "session" 具体指什么（进程生命周期？）
   - **建议**：在 UI 中添加 session 的说明或悬停提示

### 边界情况

| 场景 | 当前行为 | 建议 |
|-----|---------|------|
| 服务器不支持任何持久化 | 仅显示 Allow/Cancel | 符合预期 |
| 服务器仅支持 session | 显示 Allow/Allow for this session/Cancel | 符合预期 |
| 服务器仅支持 always | 显示 Allow/Always allow/Cancel | 符合预期 |
| 用户快速按数字键 | 直接选择对应选项并提交 | 符合预期 |

### 改进建议

1. **视觉层级优化**
   ```rust
   // 建议：对 Always allow 添加警告样式
   let always_option = McpServerElicitationOption {
       label: "Always allow".yellow().to_string(),  // 警告色
       description: Some("⚠️ This will skip future confirmations for this tool".to_string()),
       value: Value::String(APPROVAL_ACCEPT_ALWAYS_VALUE.to_string()),
   };
   ```

2. **撤销机制**
   ```rust
   // 建议：在状态栏或设置中添加管理入口
   AppEvent::ShowApprovalSettings  // 查看和撤销持久化授权
   ```

3. **时间限制**
   ```rust
   // 建议：支持带过期时间的授权
   meta: {
     "persist": "session",
     "expires_at": "2024-12-31T23:59:59Z"
   }
   ```

4. **粒度控制**
   - 当前：按工具类型授权
   - 建议：支持按具体参数模式授权（如仅允许特定目录的文件操作）

5. **审计日志**
   - 记录所有审批决策，特别是持久化授权
   - 方便用户回顾和安全审查
