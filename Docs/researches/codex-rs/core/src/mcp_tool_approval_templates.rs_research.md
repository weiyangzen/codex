# MCP Tool Approval Templates 研究文档

## 文件信息
- **文件路径**: `codex-rs/core/src/mcp_tool_approval_templates.rs`
- **代码行数**: 371 行
- **主要功能**: MCP 工具审批模板的渲染与管理

---

## 一、场景与职责

### 1.1 核心定位
`mcp_tool_approval_templates.rs` 负责管理 MCP 工具的用户审批提示模板系统。当 Codex 需要调用某些敏感操作（如发送邮件、创建日历事件、修改 GitHub PR）时，系统会展示用户友好的确认对话框，而不是暴露原始的技术参数。

### 1.2 使用场景

1. **敏感操作确认**: 用户调用可能产生副作用的工具时（如 `send_email`, `create_event`）
2. **参数友好展示**: 将技术参数名（如 `pr_number`, `repo_full_name`）转换为用户可读的标签（如 "Pull request", "Repository"）
3. **连接器品牌化**: 使用连接器名称（如 "Google Calendar"）替换模板占位符

### 1.3 职责边界
- **不负责**: 实际的审批决策逻辑（由 `AskForApproval` 策略控制）
- **不负责**: UI 渲染（仅提供数据：`RenderedMcpToolApprovalTemplate`）
- **负责**: 模板匹配、参数映射、占位符替换

---

## 二、功能点目的

### 2.1 模板匹配系统

**目的**: 根据工具标识（server + connector + tool_title）找到对应的审批模板

**匹配规则**:
- `server_name`: 必须匹配（如 `"codex_apps"`）
- `connector_id`: 必须匹配（如 `"connector_947e0d954944416db111db556030eea6"`）
- `tool_title`: 必须匹配（如 `"create_event"`）

**设计理由**: 精确匹配确保每个敏感工具都有定制化的确认消息

### 2.2 参数友好展示

**目的**: 将技术参数转换为用户可读的格式

**实现策略**:
- 模板定义 `template_params` 列表，每个参数有 `name`（技术名）和 `label`（展示名）
- 未在模板中定义的参数按原样显示（参数名作为 label）
- 参数按模板定义顺序 + 字母顺序排列

### 2.3 连接器名称替换

**目的**: 在模板中使用 `{connector_name}` 占位符，运行时替换为实际的连接器显示名称

**示例**:
- 模板: `"Allow {connector_name} to create an event?"`
- 渲染后: `"Allow Google Calendar to create an event?"`

---

## 三、具体技术实现

### 3.1 数据结构

```rust
// 渲染结果
pub(crate) struct RenderedMcpToolApprovalTemplate {
    pub(crate) question: String,           // 主要问题（用于对话框标题）
    pub(crate) elicitation_message: String, // 详细消息（与 question 相同）
    pub(crate) tool_params: Option<Value>,  // 完整的工具参数（JSON）
    pub(crate) tool_params_display: Vec<RenderedMcpToolApprovalParam>, // 展示的参数列表
}

// 展示的参数项
pub(crate) struct RenderedMcpToolApprovalParam {
    pub(crate) name: String,        // 技术参数名
    pub(crate) value: Value,        // 参数值
    pub(crate) display_name: String, // 用户友好的标签
}

// 模板定义（从 JSON 加载）
struct ConsequentialToolMessageTemplate {
    connector_id: String,           // 连接器 ID
    server_name: String,            // 服务器名称
    tool_title: String,             // 工具标题
    template: String,               // 模板字符串（可含 {connector_name}）
    template_params: Vec<ConsequentialToolTemplateParam>, // 参数映射
}

// 参数映射
struct ConsequentialToolTemplateParam {
    name: String,   // 技术参数名（匹配 tool params 中的 key）
    label: String,  // 用户友好的标签
}
```

### 3.2 模板加载机制

```rust
// 全局静态缓存，延迟初始化
static CONSEQUENTIAL_TOOL_MESSAGE_TEMPLATES: LazyLock<
    Option<Vec<ConsequentialToolMessageTemplate>>,
> = LazyLock::new(load_consequential_tool_message_templates);

fn load_consequential_tool_message_templates() -> Option<Vec<ConsequentialToolMessageTemplate>> {
    // 从编译时嵌入的 JSON 加载
    let templates = serde_json::from_str::<ConsequentialToolMessageTemplatesFile>(
        include_str!("consequential_tool_message_templates.json")
    )?;
    
    // Schema 版本检查
    if templates.schema_version != CONSEQUENTIAL_TOOL_MESSAGE_TEMPLATES_SCHEMA_VERSION {
        warn!("unexpected schema version");
        return None;
    }
    
    Some(templates.templates)
}
```

### 3.3 渲染流程

```rust
pub(crate) fn render_mcp_tool_approval_template(
    server_name: &str,
    connector_id: Option<&str>,
    connector_name: Option<&str>,
    tool_title: Option<&str>,
    tool_params: Option<&Value>,
) -> Option<RenderedMcpToolApprovalTemplate> {
    // 1. 获取全局模板列表
    let templates = CONSEQUENTIAL_TOOL_MESSAGE_TEMPLATES.as_ref()?;
    
    // 2. 精确匹配模板
    let template = templates.iter().find(|t| {
        t.server_name == server_name
            && t.connector_id == connector_id?
            && t.tool_title == tool_title?
    })?;
    
    // 3. 渲染模板（替换 {connector_name}）
    let elicitation_message = render_question_template(&template.template, connector_name)?;
    
    // 4. 渲染参数
    let (tool_params, tool_params_display) = render_tool_params(
        tool_params.as_object()?, 
        &template.template_params
    )?;
    
    Some(RenderedMcpToolApprovalTemplate { ... })
}
```

### 3.4 参数渲染逻辑

```rust
fn render_tool_params(
    tool_params: &Map<String, Value>,
    template_params: &[ConsequentialToolTemplateParam],
) -> Option<(Option<Value>, Vec<RenderedMcpToolApprovalParam>)> {
    let mut display_params = Vec::new();
    let mut display_names = HashSet::new();  // 检测 label 冲突
    let mut handled_names = HashSet::new();  // 跟踪已处理的参数
    
    // 1. 首先处理模板中定义的参数（保持模板定义顺序）
    for template_param in template_params {
        let label = template_param.label.trim();
        if label.is_empty() { return None; }  // 空 label 视为错误
        
        let value = tool_params.get(&template_param.name)?;
        
        // 检测 label 冲突（如两个参数都映射到 "Title"）
        if !display_names.insert(label.to_string()) { return None; }
        
        display_params.push(RenderedMcpToolApprovalParam { ... });
        handled_names.insert(template_param.name.as_str());
    }
    
    // 2. 处理剩余参数（按字母顺序排序）
    let mut remaining_params: Vec<_> = tool_params
        .iter()
        .filter(|(name, _)| !handled_names.contains(name.as_str()))
        .collect();
    remaining_params.sort_by(|(a, _), (b, _)| a.cmp(b));
    
    for (name, value) in remaining_params {
        // 使用参数名作为 display_name
        display_params.push(RenderedMcpToolApprovalParam {
            name: name.clone(),
            value: value.clone(),
            display_name: name.clone(),
        });
    }
    
    Some((Some(Value::Object(tool_params.clone())), display_params))
}
```

---

## 四、关键代码路径与文件引用

### 4.1 内部依赖

| 文件 | 用途 |
|------|------|
| `consequential_tool_message_templates.json` | 编译时嵌入的模板数据 |

### 4.2 模板数据文件

**路径**: `codex-rs/core/src/consequential_tool_message_templates.json`

**结构**:
```json
{
  "schema_version": 4,
  "templates": [
    {
      "source_tool_index": 0,
      "connector_id": "connector_76869538009648d5b282a4bb21c3d157",
      "server_name": "codex_apps",
      "tool_title": "add_comment_to_issue",
      "template_params": [
        {"name": "pr_number", "label": "Pull request"},
        {"name": "repo_full_name", "label": "Repository"},
        {"name": "comment", "label": "Comment"}
      ],
      "template": "Allow {connector_name} to add a comment to a pull request?"
    },
    ...
  ]
}
```

### 4.3 当前模板覆盖

| Connector ID | 连接器 | 工具数 | 示例工具 |
|-------------|--------|--------|---------|
| connector_76869538009648d5b282a4bb21c3d157 | GitHub | 19 | create_pull_request, add_comment_to_issue |
| connector_947e0d954944416db111db556030eea6 | Google Calendar | 4 | create_event, delete_event, update_event |
| connector_9d7cfa34e6654a5f98d3387af34b2e1c | Google Sheets | 3 | batch_update, create_spreadsheet |
| connector_6f1ec045b8fa4ced8738e32c7f74514b | Google Slides | 2 | batch_update, create_presentation |
| connector_4964e3b22e3e427e9b4ae1acf2c1fa34 | Google Docs | 2 | batch_update, create_document |
| connector_5f3c8c41a1e54ad7a76272c89e2554fa | Google Drive | 2 | copy_document, share_document |
| asdk_app_69a1d78e929881919bba0dbda1f6436d | Slack | 4 | slack_send_message, slack_schedule_message |
| connector_686fad9b54914a35b75be6d06a0f6f31 | Linear | 12 | create_issue, assign_issue, add_comment_to_issue |
| connector_2128aebfecb84f64a069897515042a44 | Gmail | 6 | send_email, create_draft, apply_labels_to_emails |

### 4.4 函数调用链

```
render_mcp_tool_approval_template()
  ├─> load_consequential_tool_message_templates() [LazyLock 初始化]
  ├─> render_mcp_tool_approval_template_from_templates()
  │   ├─> render_question_template()  // 处理 {connector_name}
  │   └─> render_tool_params()        // 处理参数映射
  └─> RenderedMcpToolApprovalTemplate
```

---

## 五、依赖与外部交互

### 5.1 外部调用方

通过 Grep 搜索，主要调用方在：
- `codex-rs/core/src/mcp_tool_call.rs` - 工具调用时的审批提示
- `codex-rs/core/src/apps/render.rs` - 应用相关的渲染逻辑

### 5.2 输入数据来源

| 字段 | 来源 |
|------|------|
| `server_name` | `ToolInfo.server_name` |
| `connector_id` | `ToolInfo.connector_id` |
| `connector_name` | `ToolInfo.connector_name` |
| `tool_title` | `ToolInfo.tool.title` |
| `tool_params` | 工具调用时的实际参数 |

### 5.3 输出数据消费

`RenderedMcpToolApprovalTemplate` 被用于：
- 构建审批对话框的标题和消息
- 展示工具调用的参数详情
- 发送给前端 UI 进行渲染

---

## 六、风险、边界与改进建议

### 6.1 已知风险

1. **模板缺失风险**
   - 风险: 新添加的连接器工具没有对应模板，导致审批提示不友好
   - 缓解: 返回 `None`，使用默认的通用提示
   - 建议: 建立模板覆盖率监控

2. **Label 冲突风险**
   - 风险: 模板中两个参数映射到相同的 label，导致渲染失败
   - 缓解: 检测到冲突时返回 `None`
   - 建议: 在 CI 中验证模板 JSON 的合法性

3. **Schema 版本不匹配**
   - 风险: 代码更新后旧缓存的模板数据不兼容
   - 缓解: 版本检查，不匹配时忽略模板
   - 建议: 向后兼容的 schema 设计

4. **空 connector_name 风险**
   - 风险: 模板包含 `{connector_name}` 但实际值为空
   - 缓解: 检测到空值时返回 `None`
   - 建议: 使用默认占位符而非失败

### 6.2 边界条件

| 边界 | 处理 |
|------|------|
| 无匹配模板 | 返回 `None` |
| 空 tool_title | 返回 `None` |
| 空 connector_id | 返回 `None` |
| 空 connector_name（含占位符模板） | 返回 `None` |
| 空 label | 返回 `None` |
| Label 冲突 | 返回 `None` |
| tool_params 非对象 | 返回 `None` |
| JSON 解析失败 | 返回 `None`（记录 warning） |
| Schema 版本不匹配 | 返回 `None`（记录 warning） |

### 6.3 改进建议

1. **模板热更新**
   - 当前: 模板编译时嵌入，无法运行时更新
   - 建议: 支持从远程或本地文件动态加载

2. **国际化 (i18n)**
   - 当前: 仅支持英文模板
   - 建议: 添加多语言模板支持

3. **模板验证工具**
   ```bash
   # 建议添加 CLI 工具
   cargo run --bin validate-templates -- --check-duplicates --check-labels
   ```

4. **更智能的 fallback**
   - 当前: 无精确匹配时返回 `None`
   - 建议: 支持通配符匹配（如 `server_name = "*"`）

5. **参数类型格式化**
   - 当前: 所有参数按原样显示
   - 建议: 根据参数类型格式化（如日期、URL、列表）

6. **模板覆盖率报告**
   ```rust
   // 建议添加诊断 API
   pub fn get_template_coverage_stats() -> TemplateCoverageStats {
       // 返回已覆盖的 connector/tool 比例
   }
   ```

7. **运行时模板注册**
   ```rust
   // 允许插件注册自定义模板
   pub fn register_template(template: ConsequentialToolMessageTemplate) -> Result<(), Error>;
   ```

---

## 七、测试覆盖

测试文件: 内联测试模块 `#[cfg(test)] mod tests`

### 7.1 测试用例

| 测试 | 目的 |
|------|------|
| `renders_exact_match_with_readable_param_labels` | 验证完整渲染流程 |
| `returns_none_when_no_exact_match_exists` | 验证无匹配时返回 None |
| `returns_none_when_relabeling_would_collide` | 验证 label 冲突检测 |
| `bundled_templates_load` | 验证 JSON 文件可解析 |
| `renders_literal_template_without_connector_substitution` | 验证无占位符模板 |
| `returns_none_when_connector_placeholder_has_no_value` | 验证空 connector_name 处理 |

### 7.2 测试技巧

```rust
// 直接构造模板列表进行测试，避免依赖全局静态变量
fn render_mcp_tool_approval_template_from_templates(
    templates: &[ConsequentialToolMessageTemplate],  // 注入测试数据
    server_name: &str,
    connector_id: Option<&str>,
    connector_name: Option<&str>,
    tool_title: Option<&str>,
    tool_params: Option<&Value>,
) -> Option<RenderedMcpToolApprovalTemplate>
```

---

## 八、相关文件

| 文件 | 关系 |
|------|------|
| `consequential_tool_message_templates.json` | 模板数据源 |
| `mcp_connection_manager.rs` | 提供 `ToolInfo` 数据 |
| `mcp_tool_call.rs` | 主要调用方 |
| `apps/render.rs` | 调用方 |

---

*文档生成时间: 2026-03-23*
*基于代码版本: codex-rs/core/src/mcp_tool_approval_templates.rs (371 lines)*
