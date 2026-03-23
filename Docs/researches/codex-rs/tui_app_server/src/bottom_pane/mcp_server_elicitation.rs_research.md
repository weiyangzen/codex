# MCP Server Elicitation 研究文档

## 文件信息

- **文件路径**: `codex-rs/tui_app_server/src/bottom_pane/mcp_server_elicitation.rs`
- **文件行数**: 约 2480 行（含测试）
- **所属 crate**: `codex-tui-app-server`
- **最后更新**: 2026-03-23

---

## 1. 场景与职责

### 1.1 核心定位

`mcp_server_elicitation.rs` 是 Codex TUI 应用中负责 **MCP (Model Context Protocol) 服务器交互式表单收集** 的核心模块。它实现了当 MCP 服务器需要向用户收集额外信息（如工具调用参数、OAuth 授权确认、工具安装建议等）时的 UI 交互层。

### 1.2 主要使用场景

| 场景 | 说明 |
|------|------|
| **工具调用参数收集** | MCP 工具需要用户输入参数时，动态生成表单 |
| **工具调用审批** | 敏感操作需要用户确认（Allow/Deny/Cancel）|
| **持久化权限配置** | 支持 "Allow for this session" / "Always allow" 选项 |
| **工具安装建议** | 当检测到需要特定工具时，提示用户安装或启用 |
| **OAuth 登录确认** | MCP 服务器需要授权时的用户确认流程 |

### 1.3 架构位置

```
┌─────────────────────────────────────────────────────────────┐
│                    TUI App Server                           │
├─────────────────────────────────────────────────────────────┤
│  ChatWidget  →  BottomPane  →  BottomPaneView (trait)       │
│                                    │                        │
│                         ┌──────────▼──────────┐             │
│                         │ McpServerElicitation │             │
│                         │     Overlay          │             │
│                         └──────────┬──────────┘             │
│                                    │                        │
│                         ┌──────────▼──────────┐             │
│                         │   ChatComposer       │             │
│                         │  (文本输入/选择)      │             │
│                         └─────────────────────┘             │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              App Server Protocol (WebSocket)                │
│         McpServerElicitationRequest / Response              │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 功能概览

| 功能模块 | 目的 | 关键类型 |
|---------|------|---------|
| **表单解析** | 将 JSON Schema 解析为可渲染的表单字段 | `McpServerElicitationFormRequest::from_parts` |
| **字段渲染** | 支持文本输入、单选、布尔值等多种输入类型 | `McpServerElicitationField`, `McpServerElicitationFieldInput` |
| **审批流程** | 处理工具调用的用户确认流程 | `McpServerElicitationResponseMode::ApprovalAction` |
| **工具建议** | 处理连接器/插件的安装建议 | `ToolSuggestionRequest` |
| **队列管理** | 支持多个表单请求的顺序处理 | `VecDeque<McpServerElicitationFormRequest>` |
| **响应提交** | 将用户选择转换为协议响应 | `submit_answers()`, `dispatch_cancel()` |

### 2.2 支持的表单字段类型

```rust
enum McpElicitationPrimitiveSchema {
    String(StringSchema),      // 文本输入（支持 secret 模式）
    Boolean(BooleanSchema),    // 布尔选择（True/False）
    Enum(EnumSchema),          // 枚举选择（单选）
    Number(NumberSchema),      // 数字输入（暂不支持）
}
```

### 2.3 审批模式详解

文件实现了两种主要的响应模式：

#### 2.3.1 FormContent 模式
- 用于收集结构化表单数据
- 根据 JSON Schema 动态生成字段
- 支持多字段顺序填写

#### 2.3.2 ApprovalAction 模式
- 用于简单的工具调用审批
- 预定义选项：Allow / Allow for this session / Always allow / Deny / Cancel
- 支持持久化配置（session/always）

---

## 3. 具体技术实现

### 3.1 核心数据结构

```rust
// 主 Overlay 组件
pub(crate) struct McpServerElicitationOverlay {
    app_event_tx: AppEventSender,                    // 事件发送器
    request: McpServerElicitationFormRequest,        // 当前请求
    queue: VecDeque<McpServerElicitationFormRequest>, // 请求队列
    composer: ChatComposer,                          // 文本输入组件
    answers: Vec<McpServerElicitationAnswerState>,   // 答案状态
    current_idx: usize,                              // 当前字段索引
    done: bool,                                      // 完成标记
    validation_error: Option<String>,                // 验证错误
}

// 表单请求
pub(crate) struct McpServerElicitationFormRequest {
    thread_id: ThreadId,
    server_name: String,
    request_id: McpRequestId,
    message: String,
    approval_display_params: Vec<McpToolApprovalDisplayParam>,
    response_mode: McpServerElicitationResponseMode,
    fields: Vec<McpServerElicitationField>,
    tool_suggestion: Option<ToolSuggestionRequest>,
}

// 字段定义
struct McpServerElicitationField {
    id: String,
    label: String,
    prompt: String,
    required: bool,
    input: McpServerElicitationFieldInput,
}

// 输入类型
enum McpServerElicitationFieldInput {
    Select { options: Vec<McpServerElicitationOption>, default_idx: Option<usize> },
    Text { secret: bool },
}
```

### 3.2 关键流程

#### 3.2.1 表单创建流程

```rust
// 从 App Server 请求创建
fn from_app_server_request(
    thread_id: ThreadId,
    request_id: McpRequestId,
    request: McpServerElicitationRequestParams,
) -> Option<Self>

// 从核心协议事件创建  
fn from_event(
    thread_id: ThreadId,
    request: ElicitationRequestEvent,
) -> Option<Self>

// 核心解析逻辑
fn from_parts(
    thread_id: ThreadId,
    server_name: String,
    request_id: McpRequestId,
    meta: Option<Value>,
    message: String,
    requested_schema: Value,
) -> Option<Self> {
    // 1. 解析工具建议元数据
    let tool_suggestion = parse_tool_suggestion_request(meta.as_ref());
    
    // 2. 判断是否为工具审批
    let is_tool_approval = meta.as_ref()
        .and_then(|m| m.get("codex_approval_kind"))
        .and_then(Value::as_str) == Some("mcp_tool_call");
    
    // 3. 判断是否为空对象 schema
    let is_empty_object_schema = requested_schema.as_object()
        .is_some_and(|s| s.get("type") == Some(&Value::String("object".to_string()))
            && s.get("properties").and_then(Value::as_object)
                .is_some_and(serde_json::Map::is_empty));
    
    // 4. 确定响应模式和字段
    let (response_mode, fields) = if tool_suggestion.is_some() && ... {
        (FormContent, Vec::new())
    } else if is_tool_approval && is_empty_object_schema {
        (ApprovalAction, create_approval_options())
    } else {
        (FormContent, parse_fields_from_schema(&requested_schema)?)
    };
}
```

#### 3.2.2 字段解析流程

```rust
fn parse_fields_from_schema(requested_schema: &Value) -> Option<Vec<McpServerElicitationField>> {
    let schema = requested_schema.as_object()?;
    if schema.get("type").and_then(Value::as_str) != Some("object") {
        return None;
    }
    
    // 提取 required 字段集合
    let required: HashSet<String> = schema
        .get("required")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .map(ToString::to_string)
        .collect();
    
    // 解析每个属性
    let properties = schema.get("properties")?.as_object()?;
    for (id, property_schema) in properties {
        let property = serde_json::from_value::<McpElicitationPrimitiveSchema>(
            property_schema.clone()
        ).ok()?;
        fields.push(parse_field(id, property, required.contains(id))?);
    }
}
```

#### 3.2.3 用户提交流程

```rust
fn submit_answers(&mut self) {
    // 1. 保存当前草稿
    self.save_current_draft();
    
    // 2. 验证必填字段
    if let Some(idx) = self.first_required_unanswered_index() {
        self.validation_error = Some("Answer required fields before submitting.".to_string());
        self.jump_to_field(idx);
        return;
    }
    
    // 3. 根据响应模式处理
    if self.request.response_mode == McpServerElicitationResponseMode::ApprovalAction {
        // 审批模式：解析用户选择为 ElicitationAction
        let (decision, meta) = match self.field_value(0).as_ref().and_then(Value::as_str) {
            Some("accept") => (ElicitationAction::Accept, None),
            Some("accept_session") => (ElicitationAction::Accept, Some(json!({"persist": "session"}))),
            Some("accept_always") => (ElicitationAction::Accept, Some(json!({"persist": "always"}))),
            Some("decline") => (ElicitationAction::Decline, None),
            Some("cancel") => (ElicitationAction::Cancel, None),
            _ => (ElicitationAction::Cancel, None),
        };
        
        // 发送解析结果
        self.app_event_tx.resolve_elicitation(
            self.request.thread_id,
            self.request.server_name.clone(),
            self.request.request_id.clone(),
            decision,
            None,
            meta,
        );
    } else {
        // 表单模式：收集所有字段值
        let content = self.request.fields.iter().enumerate()
            .filter_map(|(idx, field)| self.field_value(idx).map(|v| (field.id.clone(), v)))
            .collect::<serde_json::Map<_, _>>();
        
        self.app_event_tx.resolve_elicitation(
            self.request.thread_id,
            self.request.server_name.clone(),
            self.request.request_id.clone(),
            ElicitationAction::Accept,
            Some(Value::Object(content)),
            None,
        );
    }
    
    // 4. 处理队列中的下一个请求
    if let Some(next) = self.queue.pop_front() {
        self.request = next;
        self.reset_for_request();
        self.restore_current_draft();
    } else {
        self.done = true;
    }
}
```

### 3.3 键盘交互处理

```rust
impl BottomPaneView for McpServerElicitationOverlay {
    fn handle_key_event(&mut self, key_event: KeyEvent) {
        // Esc 取消
        if matches!(key_event.code, KeyCode::Esc) {
            self.dispatch_cancel();
            self.done = true;
            return;
        }
        
        // 字段导航（Ctrl+P/N 或 PageUp/PageDown）
        match key_event {
            KeyEvent { code: KeyCode::Char('p'), modifiers: CONTROL, .. } => {
                self.move_field(false);
                return;
            }
            KeyEvent { code: KeyCode::Char('n'), modifiers: CONTROL, .. } => {
                self.move_field(true);
                return;
            }
            // ...
        }
        
        // 选择字段的特殊处理
        if self.current_field_is_select() {
            match key_event.code {
                KeyCode::Up | KeyCode::Char('k') => { /* 上移 */ }
                KeyCode::Down | KeyCode::Char('j') => { /* 下移 */ }
                KeyCode::Enter => { /* 提交并进入下一字段 */ }
                KeyCode::Char(ch) => { /* 数字快捷键选择 */ }
                // ...
            }
        } else {
            // 文本字段：委托给 ChatComposer
            let (result, _) = self.composer.handle_key_event(key_event);
            self.handle_composer_input_result(result);
        }
    }
}
```

### 3.4 渲染实现

```rust
impl Renderable for McpServerElicitationOverlay {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        // 1. 渲染菜单背景
        let content_area = render_menu_surface(area, buf);
        
        // 2. 计算布局
        let progress_height = 1;  // 字段进度指示器
        let footer_height = self.footer_tip_lines(content_area.width).len() as u16;
        let input_height = self.input_height(content_area.width);
        let prompt_height = self.wrapped_prompt_lines(content_area.width).len() as u16;
        
        // 3. 从上到下渲染
        // - 进度指示器（Field 1/3）
        // - 提示文本（问题描述）
        // - 输入区域（选择列表或文本框）
        // - 底部提示（快捷键）
    }
    
    fn desired_height(&self, width: u16) -> u16 {
        // 计算所需高度，考虑文本换行
        let inner_width = menu_surface_inset(Rect::new(0, 0, width, u16::MAX)).width;
        1  // 进度行
            + self.wrapped_prompt_lines(inner_width).len() as u16
            + self.input_height(inner_width)
            + self.footer_tip_lines(inner_width).len() as u16
            + menu_surface_padding_height()
    }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件依赖图

```
mcp_server_elicitation.rs
│
├─ 协议层依赖
│  ├─ codex-app-server-protocol
│  │  ├─ McpServerElicitationRequestParams (v2.rs)
│  │  ├─ McpServerElicitationRequestResponse (v2.rs)
│  │  └─ McpElicitation*Schema (common.rs)
│  │
│  └─ codex-protocol
│     ├─ ElicitationRequestEvent (approvals)
│     ├─ ElicitationAction (approvals)
│     └─ McpRequestId (mcp)
│
├─ UI 层依赖
│  ├─ bottom_pane_view.rs (BottomPaneView trait)
│  ├─ chat_composer.rs (ChatComposer - 文本输入)
│  ├─ selection_popup_common.rs (render_rows, menu_surface)
│  ├─ scroll_state.rs (ScrollState - 选择状态)
│  └─ app_event_sender.rs (AppEventSender - 事件发送)
│
└─ 工具函数
   ├─ text_formatting.rs (format_json_compact, truncate_text)
   └─ wrapping.rs (textwrap 封装)
```

### 4.2 关键代码路径

| 功能 | 路径 | 行号范围 |
|-----|------|---------|
| 表单请求创建 | `McpServerElicitationFormRequest::from_parts` | 259-374 |
| Schema 字段解析 | `parse_fields_from_schema` | 552-577 |
| 字段解析 | `parse_field` | 579-659 |
| 单选字段解析 | `parse_single_select_field` | 662-725 |
| 工具建议解析 | `parse_tool_suggestion_request` | 393-429 |
| 审批参数解析 | `parse_tool_approval_display_params` | 449-484 |
| 提交处理 | `submit_answers` | 1146-1213 |
| 取消处理 | `dispatch_cancel` | 1135-1144 |
| 键盘处理 | `BottomPaneView::handle_key_event` | 1487-1600 |
| 渲染 | `Renderable::render` | 1380-1452 |
| 提示渲染 | `footer_tips` | 984-1011 |

### 4.3 测试覆盖

测试模块位于文件末尾（行 1686-2481），包含：

| 测试用例 | 目的 |
|---------|------|
| `parses_boolean_form_request` | 验证布尔字段解析 |
| `unsupported_numeric_form_falls_back` | 验证不支持的类型返回 None |
| `missing_schema_uses_approval_actions` | 验证无 Schema 时回退到审批模式 |
| `empty_tool_approval_schema_uses_approval_actions` | 验证空对象 Schema 的审批模式 |
| `tool_suggestion_meta_is_parsed` | 验证工具建议元数据解析 |
| `submit_sends_accept_with_typed_content` | 验证表单提交 |
| `empty_tool_approval_schema_session_choice_sets_persist_meta` | 验证持久化选项 |
| `ctrl_c_cancels_elicitation` | 验证取消操作 |
| `queues_requests_fifo` | 验证队列处理 |
| `*_snapshot` | UI 快照测试（使用 insta） |

---

## 5. 依赖与外部交互

### 5.1 外部 crate 依赖

| crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染框架（Buffer, Rect, Widget, Line, Paragraph 等） |
| `crossterm` | 终端事件处理（KeyCode, KeyEvent, KeyModifiers） |
| `serde_json` | JSON Schema 解析和响应序列化 |
| `textwrap` | 文本自动换行 |
| `unicode-width` | Unicode 字符宽度计算 |

### 5.2 内部 crate 依赖

| crate | 类型 | 用途 |
|-------|------|------|
| `codex-app-server-protocol` | 协议 | McpServerElicitationRequestParams 等类型 |
| `codex-protocol` | 协议 | ElicitationAction, McpRequestId, ThreadId |
| `codex-tui-app-server` (内部) | UI | ChatComposer, BottomPaneView, selection_popup_common |

### 5.3 协议交互

#### 5.3.1 输入协议（Server → Client）

```rust
// app-server-protocol/src/protocol/v2.rs
pub struct McpServerElicitationRequestParams {
    pub server_name: String,
    pub request: McpServerElicitationRequest,
}

pub enum McpServerElicitationRequest {
    Form {
        meta: Option<JsonValue>,
        message: String,
        requested_schema: McpElicitationSchema,
    },
}
```

#### 5.3.2 输出协议（Client → Server）

通过 `AppEventSender::resolve_elicitation` 发送：

```rust
// app_event_sender.rs
fn resolve_elicitation(
    &self,
    thread_id: ThreadId,
    server_name: String,
    request_id: McpRequestId,
    decision: ElicitationAction,  // Accept / Decline / Cancel
    content: Option<serde_json::Value>,  // 表单数据
    meta: Option<serde_json::Value>,     // 持久化配置
)
```

### 5.4 元数据约定

文件使用特定的 JSON 元数据键来识别特殊请求类型：

| 键 | 值 | 含义 |
|---|-----|------|
| `codex_approval_kind` | `"mcp_tool_call"` | 标识为工具调用审批 |
| `codex_approval_kind` | `"tool_suggestion"` | 标识为工具安装建议 |
| `persist` | `"session"` / `"always"` | 持久化级别 |
| `tool_params` | JSON Object | 工具参数（回退显示）|
| `tool_params_display` | Array | 格式化的工具参数显示 |
| `tool_type` | `"connector"` / `"plugin"` | 工具类型 |
| `suggest_type` | `"install"` / `"enable"` | 建议类型 |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 类型安全边界

```rust
// 风险：Number 类型字段被显式忽略
McpElicitationPrimitiveSchema::Number(_) | 
McpElicitationPrimitiveSchema::Enum(McpElicitationEnumSchema::MultiSelect(_)) => None,
```
- **影响**：包含数字或多选的 Schema 会导致整个表单被拒绝
- **缓解**：当前通过审批模式回退处理

#### 6.1.2 Schema 解析失败

```rust
fn parse_fields_from_schema(...) -> Option<Vec<McpServerElicitationField>> {
    // 任何步骤失败都返回 None，导致整个表单无法显示
}
```
- **风险**：复杂的 JSON Schema 可能导致无法创建表单
- **缓解**：空 Schema 会回退到审批模式

#### 6.1.3 队列堆积

```rust
fn try_consume_mcp_server_elicitation_request(...) -> Option<...> {
    self.queue.push_back(request);  // 无队列长度限制
    None
}
```
- **风险**：大量未处理的请求可能导致内存增长
- **缓解**：通常用户交互速度限制了请求产生速度

### 6.2 边界情况

| 场景 | 行为 |
|------|------|
| 空 Schema + 无元数据 | 返回 None，不显示表单 |
| 空 Schema + 工具审批元数据 | 显示简化的审批选项 |
| 空 Schema + 工具建议元数据 | 显示工具建议 UI（可能跳转到 AppLinkView）|
| 必填字段未填写 | 验证错误，跳转到第一个未填写的必填字段 |
| 秘密字段 | 使用 `*` 掩码显示输入 |
| 粘贴内容 | 仅支持文本字段，选择字段忽略粘贴 |

### 6.3 改进建议

#### 6.3.1 短期改进

1. **支持 Number 类型字段**
   ```rust
   // 当前：直接返回 None
   // 建议：添加数字输入验证
   McpElicitationPrimitiveSchema::Number(schema) => {
       // 实现数字输入字段
   }
   ```

2. **添加队列长度限制**
   ```rust
   const MAX_QUEUE_SIZE: usize = 10;
   fn try_consume_mcp_server_elicitation_request(...) {
       if self.queue.len() >= MAX_QUEUE_SIZE {
           // 记录警告或丢弃最旧的请求
       }
   }
   ```

3. **改进错误提示**
   - 当前 Schema 解析失败静默返回 None
   - 建议添加日志记录或向用户显示错误信息

#### 6.3.2 中期改进

1. **支持多选字段**
   - `MultiSelect` 枚举变体当前被忽略
   - 需要设计多选 UI（复选框或标签选择器）

2. **字段依赖关系**
   - 支持条件字段（如选择一个选项后显示子选项）
   - 需要扩展 Schema 解析和状态管理

3. **历史记录支持**
   - 类似 ChatComposer 的历史记录功能
   - 允许用户回顾之前填写的表单

#### 6.3.3 长期改进

1. **表单验证增强**
   - 支持正则表达式验证
   - 支持自定义验证错误消息
   - 实时验证（而非仅在提交时）

2. **可访问性改进**
   - 屏幕阅读器支持
   - 高对比度模式适配
   - 键盘导航优化

3. **国际化支持**
   - 字段标签和提示的本地化
   - 从 Schema 中提取 i18n 键

### 6.4 代码质量观察

| 方面 | 评价 | 建议 |
|------|------|------|
| 模块化 | 良好 | 表单解析、渲染、交互分离清晰 |
| 测试覆盖 | 良好 | 单元测试 + 快照测试 |
| 文档 | 中等 | 复杂函数可添加更多示例 |
| 错误处理 | 中等 | 部分失败情况静默处理 |
| 类型安全 | 良好 | 使用强类型枚举区分模式 |

---

## 7. 相关文件索引

### 7.1 同目录相关文件

| 文件 | 关系 |
|------|------|
| `bottom_pane/mod.rs` | 模块入口，导出 McpServerElicitationOverlay |
| `bottom_pane_view.rs` | BottomPaneView trait 定义 |
| `chat_composer.rs` | 文本输入组件 |
| `selection_popup_common.rs` | 通用选择列表渲染 |
| `scroll_state.rs` | 滚动状态管理 |

### 7.2 协议相关文件

| 文件 | 关系 |
|------|------|
| `app-server-protocol/src/protocol/v2.rs` | McpServerElicitationRequestParams 定义 |
| `app-server-protocol/src/protocol/common.rs` | 客户端/服务器请求定义 |
| `codex-protocol/src/approvals.rs` | ElicitationAction, ElicitationRequest |

### 7.3 并行实现

| 文件 | 说明 |
|------|------|
| `codex-rs/tui/src/bottom_pane/mcp_server_elicitation.rs` | tui crate 的并行实现（AGENTS.md 要求保持同步）|

---

## 8. 总结

`mcp_server_elicitation.rs` 是 Codex TUI 中 MCP 服务器交互的关键组件，负责：

1. **协议转换**：将 JSON Schema 转换为交互式表单
2. **用户交互**：提供选择列表和文本输入两种输入模式
3. **审批流程**：支持工具调用的多级审批（单次/会话/永久）
4. **队列管理**：顺序处理多个表单请求

代码结构清晰，测试覆盖良好，但在类型支持（Number、MultiSelect）和错误处理方面存在改进空间。作为 TUI 的核心交互组件，其稳定性对用户体验至关重要。
