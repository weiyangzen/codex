# MCP Server Elicitation Approval Form without Schema 研究文档

## 场景与职责

该 Snapshot 展示了 **MCP Server Elicitation** 组件在处理无 Schema 的简单工具调用审批表单时的 UI 表现。这是最基本的审批模式，当 MCP 服务器请求用户批准但不需要收集任何额外参数时使用。

**核心职责：**
- 提供最简单的二元决策界面（Allow/Cancel）
- 作为工具调用的最后一道安全防线
- 无需复杂表单，快速响应

**典型应用场景：**
- 简单的工具调用确认（无参数或参数已在上下文中）
- 快速操作前的最后确认
- 安全敏感操作的强制人工确认

---

## 功能点目的

### 1. 简化审批流程
- 仅提供两个核心选项：
  - **Allow**：执行工具调用
  - **Cancel**：取消操作

### 2. 无 Schema 回退机制
当请求的 `requested_schema` 为 `null` 或空对象时，自动回退到此简单审批模式：

```rust
let is_empty_object_schema = requested_schema.as_object().is_some_and(|schema| {
    schema.get("type").and_then(Value::as_str) == Some("object")
        && schema
            .get("properties")
            .and_then(Value::as_object)
            .is_some_and(serde_json::Map::is_empty)
});
let is_tool_approval_action =
    is_tool_approval && (requested_schema.is_null() || is_empty_object_schema);
```

### 3. 快速交互
- 单字段表单（`Field 1/1`）
- 支持数字键 `1` 或 `2` 快速选择
- 默认选中 "Allow"（`default_idx: Some(0)`）

---

## 具体技术实现

### Schema 检测逻辑

```rust
fn from_parts(...) -> Option<Self> {
    // ...
    let is_empty_object_schema = requested_schema.as_object().is_some_and(|schema| {
        schema.get("type").and_then(Value::as_str) == Some("object")
            && schema
                .get("properties")
                .and_then(Value::as_object)
                .is_some_and(serde_json::Map::is_empty)
    });
    let is_tool_approval_action =
        is_tool_approval && (requested_schema.is_null() || is_empty_object_schema);
    // ...
}
```

### 简单审批选项构建

```rust
if requested_schema.is_null() || (is_tool_approval && is_empty_object_schema) {
    let mut options = vec![McpServerElicitationOption {
        label: "Allow".to_string(),
        description: Some("Run the tool and continue.".to_string()),
        value: Value::String(APPROVAL_ACCEPT_ONCE_VALUE.to_string()),
    }];
    
    // 对于纯工具审批（非普通表单），仅提供 Allow/Cancel
    if is_tool_approval_action {
        options.push(McpServerElicitationOption {
            label: "Cancel".to_string(),
            description: Some("Cancel this tool call".to_string()),
            value: Value::String(APPROVAL_CANCEL_VALUE.to_string()),
        });
    } else {
        // 普通表单回退提供 Deny 选项
        options.extend([
            McpServerElicitationOption {
                label: "Deny".to_string(),
                description: Some("Decline this tool call and continue.".to_string()),
                value: Value::String(APPROVAL_DECLINE_VALUE.to_string()),
            },
            McpServerElicitationOption {
                label: "Cancel".to_string(),
                description: Some("Cancel this tool call".to_string()),
                value: Value::String(APPROVAL_CANCEL_VALUE.to_string()),
            },
        ]);
    }
    
    (
        McpServerElicitationResponseMode::ApprovalAction,
        vec![McpServerElicitationField {
            id: APPROVAL_FIELD_ID.to_string(),
            label: String::new(),
            prompt: String::new(),
            required: true,
            input: McpServerElicitationFieldInput::Select {
                options,
                default_idx: Some(0),
            },
        }],
    )
}
```

### 响应处理

```rust
fn submit_answers(&mut self) {
    if self.request.response_mode == McpServerElicitationResponseMode::ApprovalAction {
        let (decision, meta) = match self.field_value(0).as_ref().and_then(Value::as_str) {
            Some(APPROVAL_ACCEPT_ONCE_VALUE) => (ElicitationAction::Accept, None),
            Some(APPROVAL_DECLINE_VALUE) => (ElicitationAction::Decline, None),
            Some(APPROVAL_CANCEL_VALUE) => (ElicitationAction::Cancel, None),
            _ => (ElicitationAction::Cancel, None),
        };
        
        self.app_event_tx.resolve_elicitation(
            self.request.thread_id,
            self.request.server_name.clone(),
            self.request.request_id.clone(),
            decision,
            None,  // 无 content
            meta,
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

### 关键测试

```rust
#[test]
fn missing_schema_uses_approval_actions() {
    // 测试 null schema 回退到审批动作模式
    // 验证返回 ElicitationAction::Accept/Decline/Cancel
}

#[test]
fn empty_tool_approval_schema_uses_approval_actions() {
    // 测试空对象 schema 回退到审批动作模式
    // 验证仅提供 Allow/Cancel 选项（无 Deny）
}
```

### 关键常量

```rust
const APPROVAL_FIELD_ID: &str = "__approval";
const APPROVAL_ACCEPT_ONCE_VALUE: &str = "accept";
const APPROVAL_DECLINE_VALUE: &str = "decline";
const APPROVAL_CANCEL_VALUE: &str = "cancel";
const APPROVAL_META_KIND_KEY: &str = "codex_approval_kind";
const APPROVAL_META_KIND_MCP_TOOL_CALL: &str = "mcp_tool_call";
```

---

## 依赖与外部交互

### 协议依赖

| 依赖 | 用途 |
|-----|------|
| `codex_protocol::approvals::ElicitationAction` | 审批动作枚举 |
| `codex_protocol::approvals::ElicitationRequest` | 审批请求结构 |
| `serde_json::Value` | Schema 和元数据处理 |

### 与普通表单的区别

| 特性 | 无 Schema 模式 | 有 Schema 模式 |
|-----|--------------|--------------|
| 响应模式 | `ApprovalAction` | `FormContent` |
| 返回内容 | `ElicitationAction` | JSON 对象 |
| 字段数量 | 1 个（固定） | 根据 Schema 动态 |
| 选项 | Allow/Cancel | 根据 Schema 类型 |

### 事件流

```
MCP Server Request (schema: null)
    ↓
McpServerElicitationFormRequest::from_event()
    ↓
检测到 null schema → ApprovalAction 模式
    ↓
构建简单选项 [Allow, Cancel]
    ↓
用户选择 → submit_answers()
    ↓
resolve_elicitation(ElicitationAction::Accept/Cancel)
    ↓
后端执行或取消工具调用
```

---

## 风险、边界与改进建议

### 当前限制

1. **信息不足**
   - 仅显示 "Allow this request?"，用户可能不清楚具体要执行什么
   - 对比：带 param summary 的版本提供了更多上下文

2. **无持久化选项**
   - 每次都需要确认，对于频繁操作可能繁琐
   - 对比：带 session persist 的版本提供了记忆功能

3. **Deny vs Cancel 混淆**
   - 在非工具审批场景下，Deny 和 Cancel 的区别可能不明显
   - Deny：拒绝但继续会话
   - Cancel：完全取消操作

### 边界情况

| 场景 | 当前行为 |
|-----|---------|
| Schema 为 `null` | 使用 ApprovalAction 模式，提供 Allow/Deny/Cancel |
| Schema 为 `{}` | 同上 |
| Schema 为 `{"type": "object", "properties": {}}` | 如果是工具审批，仅 Allow/Cancel |
| 同时是工具审批且无 Schema | 仅 Allow/Cancel（无 Deny）|

### 改进建议

1. **上下文信息增强**
   ```rust
   // 建议：即使无 Schema，也显示工具名称和服务器
   message: format!("Allow {} from {} to execute?", tool_name, server_name)
   ```

2. **快捷操作**
   ```rust
   // 建议：添加 "记住我的选择" 复选框
   // 或在此模式下也支持简单的持久化选项
   ```

3. **视觉区分**
   ```rust
   // 建议：对 Allow 使用绿色，Cancel 使用红色
   let allow_line = Line::from(vec![
       "› 1. ".into(),
       "Allow".green(),
       "   Run the tool and continue.".dim(),
   ]);
   ```

4. **批量审批**
   - 当有多个待审批请求时，提供 "Allow all" 选项
   - 减少重复交互

5. **时间戳显示**
   - 显示请求发起时间，帮助用户判断是否为当前上下文的操作
