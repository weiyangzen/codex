# consequential_tool_message_templates.json 研究文档

## 场景与职责

`consequential_tool_message_templates.json` 是 Codex 核心模块中的**静态配置文件**，用于定义 MCP 工具调用时的用户确认提示模板。当用户尝试执行具有潜在影响的操作（如发送邮件、创建 GitHub PR、修改日历事件等）时，系统使用这些模板生成人性化的确认消息。

### 核心职责
1. **提供人性化的确认提示**：将技术性的工具调用转换为自然语言问题
2. **参数标签映射**：将技术参数名（如 `repo_full_name`）映射为用户友好的标签（如 `Repository`）
3. **连接器感知**：根据 connector_id 和 tool_title 匹配特定模板
4. **支持多连接器**：覆盖 GitHub、Google Calendar、Gmail、Slack、Linear 等多个流行服务

---

## 功能点目的

### 1. 确认提示模板化
将机器可读的工具调用转换为人类可读的确认问题：
```json
{
  "template": "Allow {connector_name} to create an event?",
  "template_params": [
    {"name": "title", "label": "Title"},
    {"name": "start_time", "label": "Start"},
    {"name": "attendees", "label": "Attendees"}
  ]
}
```
转换为：
> Allow Google Calendar to create an event?
> - Title: "Team Meeting"
> - Start: "2024-01-15 10:00"
> - Attendees: ["user@example.com"]

### 2. 参数显示优化
- **技术参数名** → **用户友好标签**：`pr_number` → `Pull request`
- **参数排序**：按照 template_params 定义的顺序显示
- **剩余参数处理**：未在模板中定义的参数按字母顺序追加

### 3. 连接器特定定制
每个连接器（GitHub、Gmail 等）有自己特定的工具模板，确保提示语符合该服务的业务语义。

---

## 具体技术实现

### 数据结构

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
    }
  ]
}
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `schema_version` | integer | 架构版本，当前为 4 |
| `source_tool_index` | integer | 工具索引（内部使用） |
| `connector_id` | string | 连接器唯一标识 |
| `server_name` | string | MCP 服务器名称（通常为 "codex_apps"） |
| `tool_title` | string | 工具标题，用于匹配 |
| `template_params` | array | 参数标签映射列表 |
| `template` | string | 提示模板，支持 `{connector_name}` 占位符 |

### 支持的连接器

| connector_id | 服务 | 工具数量 |
|--------------|------|----------|
| `connector_76869538009648d5b282a4bb21c3d157` | GitHub | 19 |
| `connector_947e0d954944416db111db556030eea6` | Google Calendar | 4 |
| `connector_9d7cfa34e6654a5f98d3387af34b2e1c` | Google Sheets | 3 |
| `connector_6f1ec045b8fa4ced8738e32c7f74514b` | Google Slides | 2 |
| `connector_4964e3b22e3e427e9b4ae1acf2c1fa34` | Google Docs | 2 |
| `connector_5f3c8c41a1e54ad7a76272c89e2554fa` | Google Drive | 2 |
| `asdk_app_69a1d78e929881919bba0dbda1f6436d` | Slack | 4 |
| `connector_686fad9b54914a35b75be6d06a0f6f31` | Linear | 13 |
| `connector_2128aebfecb84f64a069897515042a44` | Gmail | 6 |

### 模板渲染流程

在 `mcp_tool_approval_templates.rs` 中实现：

```rust
pub(crate) fn render_mcp_tool_approval_template(
    server_name: &str,
    connector_id: Option<&str>,
    connector_name: Option<&str>,
    tool_title: Option<&str>,
    tool_params: Option<&Value>,
) -> Option<RenderedMcpToolApprovalTemplate> {
    // 1. 加载模板文件（编译时嵌入）
    let templates = CONSEQUENTIAL_TOOL_MESSAGE_TEMPLATES.as_ref()?;
    
    // 2. 匹配模板（server_name + connector_id + tool_title）
    let template = templates.iter().find(|t| {
        t.server_name == server_name
        && t.connector_id == connector_id?
        && t.tool_title == tool_title?
    })?;
    
    // 3. 渲染问题文本（替换 {connector_name}）
    let elicitation_message = render_question_template(&template.template, connector_name)?;
    
    // 4. 渲染参数（应用标签映射）
    let (tool_params, tool_params_display) = render_tool_params(
        tool_params, 
        &template.template_params
    )?;
    
    Some(RenderedMcpToolApprovalTemplate { ... })
}
```

---

## 关键代码路径与文件引用

### 使用此文件的代码
| 文件 | 用途 |
|------|------|
| `codex-rs/core/src/mcp_tool_approval_templates.rs` | 模板加载和渲染逻辑 |
| `codex-rs/core/src/mcp_tool_call.rs` | 工具调用时生成确认提示 |

### 渲染输出结构
```rust
pub(crate) struct RenderedMcpToolApprovalTemplate {
    pub(crate) question: String,           // 主问题文本
    pub(crate) elicitation_message: String, // 详细提示消息
    pub(crate) tool_params: Option<Value>, // 完整参数（JSON）
    pub(crate) tool_params_display: Vec<RenderedMcpToolApprovalParam>, // 显示参数列表
}

pub(crate) struct RenderedMcpToolApprovalParam {
    pub(crate) name: String,        // 原始参数名
    pub(crate) value: Value,        // 参数值
    pub(crate) display_name: String, // 显示标签
}
```

### 模板加载方式
```rust
static CONSEQUENTIAL_TOOL_MESSAGE_TEMPLATES: LazyLock<
    Option<Vec<ConsequentialToolMessageTemplate>>,
> = LazyLock::new(load_consequential_tool_message_templates);

fn load_consequential_tool_message_templates() -> Option<Vec<ConsequentialToolMessageTemplate>> {
    let templates = serde_json::from_str::<ConsequentialToolMessageTemplatesFile>(
        include_str!("consequential_tool_message_templates.json"),
    )?;
    
    // 验证 schema_version
    if templates.schema_version != CONSEQUENTIAL_TOOL_MESSAGE_TEMPLATES_SCHEMA_VERSION {
        warn!("unexpected schema version");
        return None;
    }
    
    Some(templates.templates)
}
```

---

## 依赖与外部交互

### 编译时依赖
- **文件嵌入**：使用 `include_str!` 宏在编译时嵌入 JSON 文件
- **序列化**：使用 `serde_json` 解析 JSON
- **版本检查**：硬编码的 `schema_version` 验证

### 运行时依赖
- **LazyLock**：使用 `std::sync::LazyLock` 实现懒加载和全局缓存
- **日志**：解析失败时通过 `tracing::warn` 记录警告

### 无外部网络依赖
- 纯静态文件，不依赖外部 API
- 模板更新需要重新编译发布

---

## 风险、边界与改进建议

### 已知风险

1. **版本兼容性**
   - 硬编码的 `schema_version = 4`，变更格式需要同步更新代码
   - 旧版本 Codex 无法识别新格式模板

2. **模板匹配失败**
   - 如果 connector_id 或 tool_title 不匹配，将回退到通用提示
   - 新连接器需要手动添加模板

3. **参数标签冲突**
   - 如果 `template_params` 中两个参数映射到相同 label，渲染将失败（返回 `None`）

### 边界情况

1. **缺失 connector_name**
   - 模板包含 `{connector_name}` 但调用时未提供，渲染返回 `None`

2. **空参数列表**
   - 工具无参数时，`tool_params_display` 为空向量

3. **非对象参数**
   - 如果 `tool_params` 不是 JSON 对象，渲染返回 `None`

### 改进建议

1. **动态模板更新**
   - 当前模板是编译时静态嵌入，建议支持从远程配置中心动态加载
   - 便于快速修复模板问题或添加新连接器支持

2. **模板覆盖机制**
   - 允许用户通过配置文件覆盖特定模板
   - 支持本地化（i18n）

3. **自动化模板生成**
   - 从 MCP 工具 schema 自动生成基础模板
   - 减少手动维护工作量

4. **增强错误处理**
   - 当前渲染失败返回 `None`，建议提供更详细的错误信息
   - 添加模板验证工具（CI 检查）

5. **扩展模板语法**
   - 当前仅支持 `{connector_name}`，建议支持条件语句、循环等
   - 例如：根据参数存在与否调整提示文本

6. **版本迁移工具**
   - 提供脚本自动将旧版本模板升级到新 schema
   - 维护模板变更日志

### 维护建议

| 操作 | 频率 | 说明 |
|------|------|------|
| 添加新连接器模板 | 按需 | 新集成服务时需要 |
| 更新 schema_version | 破坏性变更时 | 保持向后兼容 |
| 验证模板完整性 | 每次发布前 | 确保 JSON 格式正确 |
| 审查参数标签 | 工具变更时 | 保持与 UI 一致 |
