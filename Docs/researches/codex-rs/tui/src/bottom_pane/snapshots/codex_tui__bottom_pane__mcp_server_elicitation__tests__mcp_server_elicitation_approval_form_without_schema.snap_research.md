# MCP Server Elicitation Approval Form Without Schema

## 1. 场景与职责 (Scene and Responsibility)

### 测试场景
Tests the MCP server elicitation approval form when no schema is provided (null or empty object schema). This represents a simple binary approval/deny/cancel flow for tool calls without additional parameters.

### 组件职责
该快照测试针对 Codex TUI 的 **McpServerElicitationOverlay** 组件，负责验证：
- 简化版审批表单的 UI 渲染（仅 Allow/Deny/Cancel）
- 无持久化选项时的默认选项集
- 工具调用的基本审批流程

## 2. 功能点目的 (Feature Purpose)

### 测试目标
Validates approval form fallback when no schema is provided. When `requested_schema` is null or an empty object and no persist modes are specified, the UI presents three options: Allow, Deny, and Cancel.

### 验证要点
1. 三个选项正确渲染：Allow, Deny, Cancel
2. 每个选项的描述文本正确显示
3. 默认选中第一项（Allow）
4. 选项编号（1-3）正确显示
5. 页脚提示 "enter to submit | esc to cancel" 正确渲染
6. 字段进度指示器 "Field 1/1" 正确显示

## 3. 具体技术实现 (Technical Implementation)

### 核心数据结构
```rust
// From mcp_server_elicitation.rs

// Response mode indicates how answers should be submitted
enum McpServerElicitationResponseMode {
    FormContent,      // Submit as JSON content
    ApprovalAction,   // Submit as Accept/Decline/Cancel action
}

// Field input types
enum McpServerElicitationFieldInput {
    Select {
        options: Vec<McpServerElicitationOption>,
        default_idx: Option<usize>,
    },
    Text {
        secret: bool,
    },
}

struct McpServerElicitationOption {
    label: String,
    description: Option<String>,
    value: Value,
}
```

### 渲染逻辑
- Uses `ApprovalAction` response mode when schema is null/empty
- Creates a single field with `APPROVAL_FIELD_ID` ("__approval")
- Options built with descriptions explaining each action:
  - "Allow" -> "Run the tool and continue."
  - "Deny" -> "Decline this tool call and continue."
  - "Cancel" -> "Cancel this tool call"
- Default selection index set to 0 (Allow)
- Rendered using `render_menu_surface()` for consistent popup styling

### 关键算法
1. **Schema Detection**: `is_empty_object_schema` checks if schema is `{"type": "object", "properties": {}}`
2. **Approval Mode**: `is_tool_approval_action` true when approval kind is "mcp_tool_call" and schema is empty
3. **Option Building**: Static options array built based on approval type and persist support
4. **Action Mapping**: Selected value mapped to `ElicitationAction::Accept/Decline/Cancel`

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 源文件
- **主文件**: `codex-rs/tui/src/bottom_pane/mcp_server_elicitation.rs`

### 关键函数/方法
| 函数/方法 | 描述 |
|-----------|------|
| `McpServerElicitationFormRequest::from_event()` | Detects empty schema and sets ApprovalAction mode (lines 203-324) |
| `parse_fields_from_schema()` | Returns None for empty schemas, triggering fallback (lines 502-527) |
| `render_snapshot()` | Test helper that renders overlay to string (lines 1735-1739) |
| `render()` | Main render implementation (lines 1336-1408) |
| `render_input()` | Renders select options with selection state (lines 1247-1269) |
| `option_rows()` | Builds display rows with prefix indicators (lines 873-895) |

### 测试代码位置
- Test: `approval_form_tool_approval_snapshot()` (lines 2342-2360)
- Creates form with `empty_object_schema()` and empty meta
- Snapshot name: `mcp_server_elicitation_approval_form_without_schema`

### 常量定义
```rust
const APPROVAL_FIELD_ID: &str = "__approval";
const APPROVAL_ACCEPT_ONCE_VALUE: &str = "accept";
const APPROVAL_DECLINE_VALUE: &str = "decline";
const APPROVAL_CANCEL_VALUE: &str = "cancel";
const APPROVAL_META_KIND_KEY: &str = "codex_approval_kind";
const APPROVAL_META_KIND_MCP_TOOL_CALL: &str = "mcp_tool_call";
```

## 5. 依赖与外部交互 (Dependencies)

### 外部 Crates
| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染框架，提供 Buffer、Rect、Widget、Paragraph 等 |
| `crossterm` | 跨平台终端控制，处理键盘事件 |
| `insta` | 快照测试框架 |
| `serde_json` | JSON Value 类型和序列化 |
| `unicode-width` | Unicode 字符串宽度计算 |

### 内部模块依赖
- `crate::render::renderable::Renderable` - 可渲染组件 trait
- `crate::app_event::AppEvent` - 应用事件类型
- `crate::bottom_pane::selection_popup_common` - 通用选项列表渲染
- `crate::bottom_pane::bottom_pane_view::BottomPaneView` - 底部面板视图 trait

### 协议依赖
- `codex_protocol::approvals::ElicitationRequest::Form` - 表单请求类型
- `codex_protocol::approvals::ElicitationAction` - 审批动作枚举
- `codex_protocol::protocol::Op::ResolveElicitation` - 解析操作

## 6. 风险、边界与改进建议 (Risks, Edge Cases, Improvements)

### 潜在风险
1. **Schema 误判**: 非空但无效的 schema 可能被误判为 empty，导致表单字段丢失
2. **选项值硬编码**: 选项值字符串硬编码，变更时需要同步修改多处
3. **缺少持久化**: 无持久化选项时用户每次都需要手动批准

### 边界情况
- 当 meta 不包含 `codex_approval_kind` 时，即使 schema 为空也使用普通表单模式
- 非工具调用的空 schema 表单会显示 Deny 选项而非 Cancel
- 终端宽度小于 30 字符时选项描述会被截断

### 改进建议
1. **动态选项**: 支持通过 meta 自定义选项标签和描述
2. **默认行为配置**: 允许配置默认选中项（如默认 Deny）
3. **批量审批**: 支持类似请求的批量审批 UI
4. **历史记录**: 显示最近类似请求的审批决策
5. **快捷键优化**: 添加 'y'/'n'/'c' 单键快捷键

### 相关文档
- `codex-rs/tui/styles.md` - TUI 样式规范
- `AGENTS.md` - 项目级代理指南
- `codex-rs/tui/src/bottom_pane/selection_popup_common.rs` - 选项列表渲染通用模块
