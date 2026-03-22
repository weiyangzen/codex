# render.rs 研究文档

## 场景与职责

`render.rs` 是 Codex 插件系统中负责 **插件指令渲染** 的模块。它将插件的元数据转换为自然语言指令，注入到模型的系统提示（system prompt）中，帮助模型理解可用插件及其功能。

### 核心场景

1. **插件列表展示**：向模型展示当前会话中可用的插件列表
2. **显式插件指令**：当用户明确提及某个插件时，提供该插件的详细能力说明
3. **使用指导**：告知模型如何正确使用插件（命名约定、触发规则等）

---

## 功能点目的

### 1. `render_plugins_section` - 渲染插件列表

**目的**：生成插件列表的 Markdown 格式指令，插入到系统提示中。

**输出示例**：
```markdown
<plugins_instructions>
## Plugins
A plugin is a local bundle of skills, MCP servers, and apps. Below is the list of plugins that are enabled and available in this session.
### Available plugins
- `sample`: inspect sample data
- `another-plugin`
### How to use plugins
- Discovery: The list above is the plugins available in this session.
- Skill naming: If a plugin contributes skills, those skill entries are prefixed with `plugin_name:` in the Skills list.
- Trigger rules: If the user explicitly names a plugin, prefer capabilities associated with that plugin for that turn.
- Relationship to capabilities: Plugins are not invoked directly. Use their underlying skills, MCP tools, and app tools to help solve the task.
- Preference: When a relevant plugin is available, prefer using capabilities associated with that plugin over standalone capabilities that provide similar functionality.
- Missing/blocked: If the user requests a plugin that is not listed above, or the plugin does not have relevant callable capabilities for the task, say so briefly and continue with the best fallback.
</plugins_instructions>
```

### 2. `render_explicit_plugin_instructions` - 渲染显式插件指令

**目的**：当用户明确提及某个插件时，生成该插件的具体能力说明。

**输出示例**：
```markdown
Capabilities from the `github` plugin:
- Skills from this plugin are prefixed with `github:`.
- MCP servers from this plugin available in this session: `github-mcp`.
- Apps from this plugin available in this session: `github-connector`.
Use these plugin-associated capabilities to help solve the task.
```

---

## 具体技术实现

### 数据结构

```rust
/// 插件能力摘要（输入数据）
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PluginCapabilitySummary {
    pub config_name: String,        // 配置中的名称（如 "github@openai-curated"）
    pub display_name: String,       // 显示名称（如 "github"）
    pub description: Option<String>, // 描述
    pub has_skills: bool,           // 是否有 skills
    pub mcp_server_names: Vec<String>,  // MCP 服务器名称列表
    pub app_connector_ids: Vec<AppConnectorId>,  // App 连接器 ID 列表
}
```

### 核心算法

#### `render_plugins_section`

```rust
pub(crate) fn render_plugins_section(plugins: &[PluginCapabilitySummary]) -> Option<String> {
    // 空列表返回 None
    if plugins.is_empty() {
        return None;
    }

    let mut lines = vec![
        "## Plugins".to_string(),
        "A plugin is a local bundle of skills, MCP servers, and apps...".to_string(),
        "### Available plugins".to_string(),
    ];

    // 渲染每个插件的简要信息
    lines.extend(plugins.iter().map(|plugin| {
        match plugin.description.as_deref() {
            Some(description) => format!("- `{}`: {description}", plugin.display_name),
            None => format!("- `{}`", plugin.display_name),
        }
    }));

    // 添加使用指导
    lines.push("### How to use plugins".to_string());
    lines.push(r###"- Discovery: ...
- Skill naming: ...
- Trigger rules: ...
- Relationship to capabilities: ...
- Preference: ...
- Missing/blocked: ..."###.to_string());

    // 包装在 XML 标签中
    let body = lines.join("\n");
    Some(format!("{PLUGINS_INSTRUCTIONS_OPEN_TAG}\n{body}\n{PLUGINS_INSTRUCTIONS_CLOSE_TAG}"))
}
```

#### `render_explicit_plugin_instructions`

```rust
pub(crate) fn render_explicit_plugin_instructions(
    plugin: &PluginCapabilitySummary,
    available_mcp_servers: &[String],
    available_apps: &[String],
) -> Option<String> {
    let mut lines = vec![format!("Capabilities from the `{}` plugin:", plugin.display_name)];

    // 添加 skills 前缀说明
    if plugin.has_skills {
        lines.push(format!("- Skills from this plugin are prefixed with `{}:`.", plugin.display_name));
    }

    // 添加 MCP 服务器列表
    if !available_mcp_servers.is_empty() {
        lines.push(format!("- MCP servers from this plugin available in this session: {}.",
            available_mcp_servers.iter()
                .map(|s| format!("`{s}`"))
                .collect::<Vec<_>>()
                .join(", ")));
    }

    // 添加 Apps 列表
    if !available_apps.is_empty() {
        lines.push(format!("- Apps from this plugin available in this session: {}.",
            available_apps.iter()
                .map(|a| format!("`{a}`"))
                .collect::<Vec<_>>()
                .join(", ")));
    }

    // 如果没有有效内容，返回 None
    if lines.len() == 1 {
        return None;
    }

    lines.push("Use these plugin-associated capabilities to help solve the task.".to_string());
    Some(lines.join("\n"))
}
```

### XML 标签常量

```rust
// 来自 codex_protocol::protocol
const PLUGINS_INSTRUCTIONS_OPEN_TAG: &str = "<plugins_instructions>";
const PLUGINS_INSTRUCTIONS_CLOSE_TAG: &str = "</plugins_instructions>";
```

---

## 关键代码路径与文件引用

### 调用关系图

```
render.rs
    ├── injection.rs 调用:
    │   └── render_explicit_plugin_instructions
    │       （将插件提及转换为开发者提示）
    │
    └── manager.rs 提供数据:
        └── PluginCapabilitySummary
            （从 LoadedPlugin 构建）
```

### 完整调用链

```
用户输入 -> TUI/CLI
    -> 检测插件提及
        -> injection::build_plugin_injections
            -> render::render_explicit_plugin_instructions
                -> 生成 DeveloperInstructions
                    -> 添加到 ResponseItem 列表
                        -> 发送到模型
```

### 系统提示组装流程

```
Config 加载
    -> manager::plugins_for_config
        -> 生成 Vec<PluginCapabilitySummary>
            -> render::render_plugins_section
                -> 添加到系统提示
```

---

## 依赖与外部交互

### 输入依赖

| 数据 | 来源 | 说明 |
|------|------|------|
| `PluginCapabilitySummary` | `manager.rs` | 插件能力摘要 |
| `available_mcp_servers` | `injection.rs` | 过滤后的 MCP 服务器列表 |
| `available_apps` | `injection.rs` | 过滤后的 App 列表 |

### 输出格式

| 函数 | 输出 | 用途 |
|------|------|------|
| `render_plugins_section` | `Option<String>` | 系统提示中的插件列表 |
| `render_explicit_plugin_instructions` | `Option<String>` | 开发者提示（DeveloperInstructions） |

### 外部 crate 依赖

```rust
use codex_protocol::protocol::PLUGINS_INSTRUCTIONS_CLOSE_TAG;
use codex_protocol::protocol::PLUGINS_INSTRUCTIONS_OPEN_TAG;
```

---

## 风险、边界与改进建议

### 当前风险

1. **提示注入风险**：
   - 风险：插件描述可能包含恶意内容，影响模型行为
   - 现状：描述来自受信任的 marketplace.json，风险较低
   - 建议：添加内容过滤或转义

2. **提示长度限制**：
   - 风险：大量插件时，生成的指令可能超出模型上下文限制
   - 现状：没有截断机制
   - 建议：添加长度限制和优先级排序

3. **格式一致性**：
   - 风险：Markdown 格式可能与模型期望不一致
   - 现状：使用标准 Markdown

### 边界情况

| 情况 | 当前行为 | 评估 |
|------|----------|------|
| 空插件列表 | 返回 `None` | ✅ 合理 |
| 插件无描述 | 仅显示名称 | ✅ 合理 |
| 无 MCP 服务器 | 不显示 MCP 行 | ✅ 合理 |
| 无 Apps | 不显示 Apps 行 | ✅ 合理 |
| 无 skills/MCP/Apps | 返回 `None` | ✅ 合理 |

### 改进建议

1. **添加长度限制**：
   ```rust
   const MAX_PLUGINS_SECTION_LEN: usize = 2000;
   
   fn render_plugins_section(plugins: &[PluginCapabilitySummary]) -> Option<String> {
       // ... 现有逻辑 ...
       let body = lines.join("\n");
       if body.len() > MAX_PLUGINS_SECTION_LEN {
           // 截断或返回错误
       }
       Some(format!("...", body))
   }
   ```

2. **支持国际化**：
   ```rust
   pub(crate) fn render_plugins_section(
       plugins: &[PluginCapabilitySummary],
       locale: &str,  // 新增参数
   ) -> Option<String> {
       // 根据 locale 选择不同模板
   }
   ```

3. **添加插件优先级**：
   ```rust
   pub struct PluginCapabilitySummary {
       // ... 现有字段 ...
       pub priority: Option<u32>,  // 用于排序
   }
   ```

4. **模板化渲染**：
   ```rust
   // 使用模板引擎（如 handlebars）替代字符串拼接
   use handlebars::Handlebars;
   
   lazy_static! {
       static ref TEMPLATE: Handlebars = {
           let mut h = Handlebars::new();
           h.register_template_string("plugins_section", include_str!("plugins_section.hbs")).unwrap();
           h
       };
   }
   ```

### 测试覆盖

当前测试在 `render_tests.rs` 中：

| 测试 | 覆盖 |
|------|------|
| `render_plugins_section_returns_none_for_empty_plugins` | ✅ 空列表 |
| `render_plugins_section_includes_descriptions_and_skill_naming_guidance` | ✅ 基本渲染 |

**建议添加的测试**：

1. 多个插件的渲染顺序
2. 特殊字符的转义
3. 超长描述的截断
4. `render_explicit_plugin_instructions` 的各种组合
