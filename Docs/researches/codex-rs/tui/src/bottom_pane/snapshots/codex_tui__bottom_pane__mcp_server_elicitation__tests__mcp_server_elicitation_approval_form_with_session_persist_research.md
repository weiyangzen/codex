# MCP Server Elicitation Approval Form with Session Persist - 研究文档

## 1. 场景与职责

### 1.1 测试场景

此快照测试验证 **MCP 工具调用审批表单在支持持久化选项时的 UI 渲染效果**。具体场景是：

- **触发条件**: 用户通过 MCP 服务器调用工具，且服务器声明支持持久化偏好设置
- **持久化选项**: 提供三个层级的授权选择：
  1. **Allow** - 仅允许本次调用
  2. **Allow for this session** - 允许本次及当前会话内的后续调用
  3. **Always allow** - 始终允许该工具的调用
- **用户体验**: 减少重复审批，提升工作流效率

### 1.2 组件职责

`McpServerElicitationOverlay` 组件在此场景中的职责：

1. **持久化能力检测**: 从 `meta` 数据中解析 `persist` 字段，确定支持的持久化模式
2. **动态选项生成**: 根据支持的持久化模式动态生成审批选项列表
3. **元数据附加**: 用户选择持久化选项时，在响应中附加相应的 `persist` 元数据
4. **状态管理**: 维护当前选中的选项索引，处理用户导航和选择

---

## 2. 功能点目的

### 2.1 持久化选项的目的

```rust
// 关键常量定义
const APPROVAL_PERSIST_KEY: &str = "persist";
const APPROVAL_PERSIST_SESSION_VALUE: &str = "session";
const APPROVAL_PERSIST_ALWAYS_VALUE: &str = "always";
```

**设计意图**：
- **减少摩擦**: 避免用户在会话中反复批准同一工具
- **用户控制**: 提供细粒度的控制，用户可选择仅本次、当前会话或永久允许
- **安全平衡**: 在便利性和安全性之间取得平衡，默认不持久化

### 2.2 持久化模式检测

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

**支持的模式声明方式**：
- 单模式: `"persist": "session"`
- 多模式: `"persist": ["session", "always"]`

---

## 3. 具体技术实现

### 3.1 选项生成逻辑

```rust
// 基础选项：始终存在
let mut options = vec![McpServerElicitationOption {
    label: "Allow".to_string(),
    description: Some("Run the tool and continue.".to_string()),
    value: Value::String(APPROVAL_ACCEPT_ONCE_VALUE.to_string()),
}];

// 条件选项：仅当支持 session 持久化时添加
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

// 条件选项：仅当支持 always 持久化时添加
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

// 基础选项：始终存在
options.push(McpServerElicitationOption {
    label: "Cancel".to_string(),
    description: Some("Cancel this tool call".to_string()),
    value: Value::String(APPROVAL_CANCEL_VALUE.to_string()),
});
```

### 3.2 响应模式与元数据

```rust
enum McpServerElicitationResponseMode {
    FormContent,     // 表单内容模式（需要收集字段值）
    ApprovalAction,  // 审批动作模式（选择预设选项）
}
```

### 3.3 提交时的元数据构造

```rust
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
        
        // 发送事件...
    }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/bottom_pane/mcp_server_elicitation.rs` | 主要实现文件 |
| `codex-rs/tui/src/bottom_pane/chat_composer.rs` | ChatComposer 集成 |

### 4.2 关键代码路径

**1. 持久化支持检测**（行 381-397）:
```rust
fn tool_approval_supports_persist_mode(meta: Option<&Value>, expected_mode: &str) -> bool
```

**2. 选项生成路径**（行 243-306）:
```rust
// 在 from_event 方法中
let mut options = vec![McpServerElicitationOption { ... }];
if is_tool_approval_action
    && tool_approval_supports_persist_mode(meta.as_ref(), APPROVAL_PERSIST_SESSION_VALUE)
{
    options.push(...);
}
if is_tool_approval_action
    && tool_approval_supports_persist_mode(meta.as_ref(), APPROVAL_PERSIST_ALWAYS_VALUE)
{
    options.push(...);
}
```

**3. 提交处理路径**（行 1098-1143）:
```rust
fn submit_answers(&mut self) {
    if self.request.response_mode == McpServerElicitationResponseMode::ApprovalAction {
        let (decision, meta) = match ...;
        self.app_event_tx.send(AppEvent::SubmitThreadOp { ... });
    }
}
```

**4. 测试代码位置**（行 2362-2387）:
```rust
#[test]
fn approval_form_tool_approval_with_persist_options_snapshot() {
    let request = McpServerElicitationFormRequest::from_event(
        thread_id,
        form_request(
            "Allow this request?",
            empty_object_schema(),
            tool_approval_meta(
                &[
                    APPROVAL_PERSIST_SESSION_VALUE,
                    APPROVAL_PERSIST_ALWAYS_VALUE,
                ],  // 同时支持 session 和 always
                None,
                None,
            ),
        ),
    );
    insta::assert_snapshot!(
        "mcp_server_elicitation_approval_form_with_session_persist",
        render_snapshot(&overlay, Rect::new(0, 0, 120, 16))
    );
}
```

---

## 5. 依赖与外部交互

### 5.1 协议依赖

```rust
use codex_protocol::approvals::ElicitationAction;
use codex_protocol::protocol::Op;
```

### 5.2 事件交互

**输出事件**:
```rust
AppEvent::SubmitThreadOp {
    thread_id: ThreadId,
    op: Op::ResolveElicitation {
        server_name: String,
        request_id: McpRequestId,
        decision: ElicitationAction::Accept,
        content: None,
        meta: Some(serde_json::json!({
            "persist": "session"  // 或 "always"
        })),
    },
}
```

### 5.3 元数据格式

**输入元数据**（来自服务器）:
```json
{
    "codex_approval_kind": "mcp_tool_call",
    "persist": ["session", "always"]
}
```

**输出元数据**（发送到服务器）:
```json
{
    "persist": "session"
}
```

---

## 6. 风险边界与改进建议

### 6.1 当前风险边界

**1. 持久化范围不明确**
- **问题**: "session" 和 "always" 的具体含义可能因服务器实现而异
- **风险**: 用户可能误解持久化的实际效果

**2. 缺乏撤销机制**
- **问题**: 一旦选择 "Always allow"，UI 层面没有提供撤销入口
- **风险**: 用户可能无意中授予了过宽的权限

**3. 选项顺序固定**
- **问题**: 选项顺序为 Allow → Session → Always → Cancel
- **风险**: 用户可能误选 "Always allow" 而本意是仅允许本次

### 6.2 改进建议

**1. 添加持久化说明提示**
```rust
// 建议：在选择持久化选项时显示额外说明
fn render_persist_hint(&self, mode: &str) -> Line {
    match mode {
        "session" => "This choice will be remembered until you close Codex.".dim(),
        "always" => "This choice will be remembered permanently. You can change this in settings.".dim(),
        _ => "".into(),
    }
}
```

**2. 视觉区分持久化选项**
```rust
// 建议：对高风险的 "Always allow" 选项使用警告色
fn option_style(&self, option_idx: usize) -> Style {
    if self.is_always_allow_option(option_idx) {
        Style::default().yellow()  // 警告色
    } else {
        Style::default()
    }
}
```

**3. 添加确认对话框**
```rust
// 建议：选择 "Always allow" 时要求二次确认
fn handle_option_selection(&mut self, idx: usize) {
    if self.is_always_allow_option(idx) && !self.always_allow_confirmed {
        self.show_confirm_dialog = true;
        return;
    }
    self.select_current_option(true);
}
```

**4. 持久化偏好管理**
```rust
// 建议：提供查看和撤销持久化偏好的入口
pub struct PersistedApprovalStore {
    approvals: HashMap<(ServerName, ToolName), PersistMode>,
}

impl PersistedApprovalStore {
    pub fn revoke(&mut self, server: &str, tool: &str) { ... }
    pub fn list(&self) -> Vec<(&str, &str, PersistMode)> { ... }
}
```

### 6.3 测试覆盖建议

**当前测试覆盖**:
- ✅ 持久化选项渲染
- ✅ Session 持久化提交
- ✅ Always 持久化提交

**建议补充**:
- ⬜ 单模式持久化（仅 session 或仅 always）测试
- ⬜ 持久化元数据格式验证测试
- ⬜ 持久化偏好撤销流程测试
- ⬜ 不同持久化模式组合的边界测试

---

## 7. 快照内容分析

### 7.1 快照输出

```
  Field 1/1
  Allow this request?
  › 1. Allow                   Run the tool and continue.
    2. Allow for this session  Run the tool and remember this choice for this session.
    3. Always allow            Run the tool and remember this choice for future tool calls.
    4. Cancel                  Cancel this tool call
  
  
  
  
  
  
  
  enter to submit | esc to cancel
```

### 7.2 UI 结构解析

| 行 | 内容 | 说明 |
|---|------|------|
| 1 | `Field 1/1` | 字段进度指示器 |
| 2 | `Allow this request?` | 主消息 |
| 3 | `› 1. Allow ...` | 选项1：仅允许本次（当前选中） |
| 4 | `2. Allow for this session ...` | 选项2：会话级别持久化 |
| 5 | `3. Always allow ...` | 选项3：永久允许 |
| 6 | `4. Cancel ...` | 选项4：取消操作 |
| 14 | `enter to submit | esc to cancel` | 底部提示 |

### 7.3 关键观察

1. **默认选中**: 第一个选项 "Allow" 默认被选中（`›` 标记）
2. **描述对齐**: 所有选项的描述文本右对齐，形成整齐的视觉列
3. **无参数摘要**: 此场景未提供 `tool_params`，因此不显示参数摘要
4. **完整持久化支持**: 同时支持 session 和 always 两种持久化模式

### 7.4 与无持久化选项的对比

| 特性 | 无持久化 | 有持久化 |
|-----|---------|---------|
| 选项数量 | 2 (Allow, Cancel) | 4 (Allow, Session, Always, Cancel) |
| 默认选项 | Allow | Allow |
| 元数据 | 无 | 包含 `persist` 字段 |
| 使用场景 | 一次性工具调用 | 频繁使用的工具 |
