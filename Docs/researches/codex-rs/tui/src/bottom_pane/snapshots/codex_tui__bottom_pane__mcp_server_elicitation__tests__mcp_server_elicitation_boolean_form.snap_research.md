# MCP Server Elicitation Boolean Form

## 1. 场景与职责 (Scene and Responsibility)

### 测试场景
Tests the MCP server elicitation form with a boolean schema field. This represents a form where the user must select between True/False options for a confirmation field.

### 组件职责
该快照测试针对 Codex TUI 的 **McpServerElicitationOverlay** 组件，负责验证：
- 布尔类型表单字段的 UI 渲染
- True/False 选项选择界面
- 表单字段标签和描述的显示
- 必填字段未回答状态的视觉指示

## 2. 功能点目的 (Feature Purpose)

### 测试目标
Validates boolean (true/false) form field rendering in MCP elicitation. The test creates a form with a boolean "confirmed" field and verifies the UI correctly displays the label, description, and True/False options.

### 验证要点
1. 字段进度显示 "Field 1/1 (1 required unanswered)" 正确渲染
2. 主消息 "Allow this request?" 正确显示
3. 字段标签 "Confirm" 和描述 "Approve the pending action." 正确显示
4. 两个选项正确渲染：True, False
5. 默认选中第一项（True）
6. 选项编号（1-2）正确显示
7. 页脚提示 "enter to submit | esc to cancel" 正确渲染

## 3. 具体技术实现 (Technical Implementation)

### 核心数据结构
```rust
// From mcp_server_elicitation.rs

// Boolean schema from codex_app_server_protocol
struct McpElicitationBooleanSchema {
    title: Option<String>,
    description: Option<String>,
    default: Option<bool>,
}

// Parsed field structure
struct McpServerElicitationField {
    id: String,           // "confirmed"
    label: String,        // "Confirm"
    prompt: String,       // "Approve the pending action."
    required: bool,       // true
    input: McpServerElicitationFieldInput,
}

// Boolean fields use Select input with true/false options
enum McpServerElicitationFieldInput {
    Select {
        options: Vec<McpServerElicitationOption>,
        default_idx: Option<usize>,
    },
    // ...
}
```

### 渲染逻辑
- Uses `FormContent` response mode (not ApprovalAction)
- Parses boolean schema using `parse_field()` -> `McpElicitationPrimitiveSchema::Boolean`
- Creates two options with labels "True" and "False"
- Sets `default_idx` based on schema's default value (None if not specified)
- Displays field label and prompt above options
- Shows unanswered count in progress line when required field not answered

### 关键算法
1. **Boolean Field Parsing** (lines 546-570):
   ```rust
   McpElicitationPrimitiveSchema::Boolean(schema) => {
       let label = schema.title.unwrap_or_else(|| id.to_string());
       let prompt = schema.description.unwrap_or_else(|| label.clone());
       let default_idx = schema.default.map(|value| if value { 0 } else { 1 });
       // Create True/False options...
   }
   ```

2. **Progress Line Rendering** (lines 1391-1403):
   - Shows "Field {idx}/{total}"
   - Appends "({unanswered} required unanswered)" when applicable

3. **Prompt Text Construction** (lines 904-932):
   - Combines request message with field label/prompt
   - Uses cyan color when field is unanswered

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 源文件
- **主文件**: `codex-rs/tui/src/bottom_pane/mcp_server_elicitation.rs`

### 关键函数/方法
| 函数/方法 | 描述 |
|-----------|------|
| `parse_field()` | Parses primitive schema into field (lines 529-610) |
| `parse_field()::Boolean` | Handles boolean schema specifically (lines 546-570) |
| `boolean_form_snapshot()` | Test function (lines 2312-2340) |
| `current_prompt_text()` | Builds prompt with message, label, description (lines 904-932) |
| `render_prompt()` | Renders prompt lines with cyan styling (lines 1220-1245) |
| `required_unanswered_count()` | Counts unanswered required fields (lines 1039-1046) |

### 测试代码位置
- Test: `boolean_form_snapshot()` (lines 2312-2340)
- Schema used:
  ```json
  {
    "type": "object",
    "properties": {
      "confirmed": {
        "type": "boolean",
        "title": "Confirm",
        "description": "Approve the pending action."
      }
    },
    "required": ["confirmed"]
  }
  ```
- Snapshot name: `mcp_server_elicitation_boolean_form`

### 输入 Schema 示例
```rust
serde_json::json!({
    "type": "object",
    "properties": {
        "confirmed": {
            "type": "boolean",
            "title": "Confirm",
            "description": "Approve the pending action.",
        }
    },
    "required": ["confirmed"],
})
```

## 5. 依赖与外部交互 (Dependencies)

### 外部 Crates
| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染框架 |
| `crossterm` | 跨平台终端控制 |
| `insta` | 快照测试框架 |
| `serde_json` | JSON 处理 |
| `codex_app_server_protocol` | MCP 请求协议类型 |

### 内部模块依赖
- `crate::render::renderable::Renderable` - 可渲染组件 trait
- `crate::app_event::AppEvent` - 应用事件类型
- `crate::bottom_pane::selection_popup_common` - 选项列表渲染

### 协议依赖
- `codex_app_server_protocol::McpElicitationPrimitiveSchema` - 原始类型 schema
- `codex_protocol::approvals::ElicitationRequest::Form` - 表单请求

## 6. 风险、边界与改进建议 (Risks, Edge Cases, Improvements)

### 潜在风险
1. **默认值为 null**: 当 schema 没有 default 值时，default_idx 为 None，用户必须手动选择
2. **布尔字段必填**: 布尔字段通常应该有默认值，否则用户体验不佳
3. **选项标签固定**: "True"/"False" 标签固定，无法自定义为 "Yes"/"No" 等

### 边界情况
- 当 title 为空时，使用字段 id 作为标签
- 当 description 为空时，使用 label 作为 prompt
- 终端高度不足时，prompt 可能被截断
- 多个布尔字段时，使用 ←/→ 或 Ctrl+P/N 导航

### 改进建议
1. **自定义选项标签**: 支持通过 schema 自定义 True/False 的标签
2. **单选按钮样式**: 使用更明显的单选按钮样式而非简单的 › 前缀
3. **默认值提示**: 在选项旁显示哪个是默认值
4. **快速选择**: 支持 't'/'f' 或 'y'/'n' 快捷键
5. **字段分组**: 相关布尔字段可以分组显示

### 相关文档
- `codex-rs/tui/styles.md` - TUI 样式规范
- `AGENTS.md` - 项目级代理指南
- `codex_app_server_protocol` - 协议 schema 定义
