# MCP Server Elicitation Approval Form With Session Persist

## 1. 场景与职责 (Scene and Responsibility)

### 测试场景
Tests the MCP server elicitation approval form when session persistence options are available. This snapshot captures the UI when a tool approval request includes both "Allow for this session" and "Always allow" persistence options.

### 组件职责
该快照测试针对 Codex TUI 的 **McpServerElicitationOverlay** 组件，负责验证：
- MCP 工具调用审批表单的 UI 渲染
- 会话持久化选项（session/always）的正确显示
- 选项选择界面的交互状态
- 表单提交流程的视觉反馈

## 2. 功能点目的 (Feature Purpose)

### 测试目标
Validates approval form with 'Allow for this session' and 'Always allow' persistence options. The test ensures that when a tool approval meta includes `persist: ["session", "always"]`, the UI presents four options: Allow, Allow for this session, Always allow, and Cancel.

### 验证要点
1. 四个选项正确渲染：Allow, Allow for this session, Always allow, Cancel
2. 每个选项的描述文本正确显示
3. 默认选中第一项（Allow）
4. 选项编号（1-4）正确显示
5. 页脚提示 "enter to submit | esc to cancel" 正确渲染
6. 字段进度指示器 "Field 1/1" 正确显示

## 3. 具体技术实现 (Technical Implementation)

### 核心数据结构
```rust
// From mcp_server_elicitation.rs

struct McpServerElicitationFormRequest {
    thread_id: ThreadId,
    server_name: String,
    request_id: McpRequestId,
    message: String,
    approval_display_params: Vec<McpToolApprovalDisplayParam>,
    response_mode: McpServerElicitationResponseMode,
    fields: Vec<McpServerElicitationField>,
    tool_suggestion: Option<ToolSuggestionRequest>,
}

enum McpServerElicitationResponseMode {
    FormContent,
    ApprovalAction,
}

struct McpServerElicitationField {
    id: String,
    label: String,
    prompt: String,
    required: bool,
    input: McpServerElicitationFieldInput,
}

enum McpServerElicitationFieldInput {
    Select {
        options: Vec<McpServerElicitationOption>,
        default_idx: Option<usize>,
    },
    Text {
        secret: bool,
    },
}
```

### 渲染逻辑
- Uses `render_menu_surface()` to create the overlay container
- Progress line shows "Field 1/1" with optional unanswered count
- Prompt message "Allow this request?" displayed in cyan when unanswered
- Options rendered using `render_rows()` from selection_popup_common module
- Selected option marked with '›' prefix, unselected with ' '
- Footer tips wrapped using `wrap_footer_tips()`

### 关键算法
1. **Approval Action Mode Detection**: When `requested_schema` is null or empty object and meta contains `codex_approval_kind: "mcp_tool_call"`, the form uses `ApprovalAction` response mode
2. **Persist Option Generation**: `tool_approval_supports_persist_mode()` checks if meta contains session/always persist values
3. **Option Selection**: Uses `ScrollState` to track selected index; digit keys (1-9) jump to corresponding option
4. **Submission Handling**: `submit_answers()` maps selected value to `ElicitationAction` with optional persist meta

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 源文件
- **主文件**: `codex-rs/tui/src/bottom_pane/mcp_server_elicitation.rs`

### 关键函数/方法
| 函数/方法 | 描述 |
|-----------|------|
| `McpServerElicitationFormRequest::from_event()` | Parses elicitation request into form request, detects approval mode |
| `tool_approval_supports_persist_mode()` | Checks if persist mode is supported in meta |
| `render()` | Main render function, delegates to render_prompt/render_input/render_footer |
| `render_prompt()` | Renders message and field prompt with cyan styling when unanswered |
| `render_input()` | Renders select options or composer based on field type |
| `render_footer()` | Renders footer tips with validation errors and navigation hints |
| `submit_answers()` | Handles form submission, sends ResolveElicitation op |
| `option_rows()` | Builds GenericDisplayRow list for option rendering |

### 测试代码位置
- Test: `approval_form_tool_approval_with_persist_options_snapshot()` (line 2363-2387)
- Creates form with `tool_approval_meta(&["session", "always"], None, None)`
- Renders at 120x16 resolution

### 常量定义
```rust
const APPROVAL_ACCEPT_ONCE_VALUE: &str = "accept";
const APPROVAL_ACCEPT_SESSION_VALUE: &str = "accept_session";
const APPROVAL_ACCEPT_ALWAYS_VALUE: &str = "accept_always";
const APPROVAL_CANCEL_VALUE: &str = "cancel";
const APPROVAL_PERSIST_KEY: &str = "persist";
const APPROVAL_PERSIST_SESSION_VALUE: &str = "session";
const APPROVAL_PERSIST_ALWAYS_VALUE: &str = "always";
```

## 5. 依赖与外部交互 (Dependencies)

### 外部 Crates
| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染框架，提供 Buffer、Rect、Widget 等核心类型 |
| `crossterm` | 跨平台终端控制，处理键盘事件 |
| `insta` | 快照测试框架 |
| `pretty_assertions` | 测试失败时提供美观的差异对比 |
| `serde_json` | JSON 序列化/反序列化 |
| `unicode-width` | Unicode 字符宽度计算 |

### 内部模块依赖
- `crate::render::renderable::Renderable` - 可渲染组件 trait
- `crate::app_event::AppEvent` - 应用事件类型
- `crate::bottom_pane::selection_popup_common` - 选项列表渲染通用逻辑
- `crate::bottom_pane::ChatComposer` - 文本输入组件
- `crate::text_formatting` - 文本格式化工具

### 协议依赖
- `codex_protocol::approvals::ElicitationRequest` - 请求类型定义
- `codex_protocol::approvals::ElicitationAction` - 动作类型（Accept/Decline/Cancel）
- `codex_protocol::protocol::Op::ResolveElicitation` - 解析操作

## 6. 风险、边界与改进建议 (Risks, Edge Cases, Improvements)

### 潜在风险
1. **选项数量限制**: 数字快捷键只支持 1-9，超过 9 个选项无法使用数字选择
2. **描述文本溢出**: 长描述文本可能在窄终端被截断
3. **持久化元数据**: 错误设置 persist meta 可能导致权限持久化行为异常

### 边界情况
- 终端宽度小于 40 字符时，选项描述可能换行异常
- 当 persist 数组为空时，只显示 Allow 和 Cancel 两个选项
- 当只有 session 或 only always 时，显示三个选项
- 快速连续提交可能导致事件重复发送

### 改进建议
1. **滚动支持**: 当选项超过屏幕高度时，添加滚动指示器
2. **搜索过滤**: 大量选项时支持输入过滤
3. **快捷键提示**: 在选项旁显示数字快捷键提示
4. **持久化确认**: 对 "Always allow" 选项添加二次确认，防止误操作
5. **选项分组**: 支持将相关选项分组显示

### 相关文档
- `codex-rs/tui/styles.md` - TUI 样式规范
- `AGENTS.md` - 项目级代理指南
- `codex-rs/tui/src/bottom_pane/selection_popup_common.rs` - 选项列表渲染通用模块
