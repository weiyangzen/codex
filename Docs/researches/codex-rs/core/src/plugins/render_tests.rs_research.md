# render_tests.rs 研究文档

## 场景与职责

`render_tests.rs` 是 `render.rs` 模块的单元测试文件，负责验证插件指令渲染功能的正确性。该文件确保生成的系统提示和开发者提示格式符合预期，能够正确指导模型使用插件。

---

## 功能点目的

### 测试覆盖范围

1. **空列表处理**：验证空插件列表时返回 `None`
2. **完整渲染验证**：验证包含描述和技能命名指导的完整渲染输出

---

## 具体技术实现

### 测试用例 1：空列表处理

```rust
#[test]
fn render_plugins_section_returns_none_for_empty_plugins() {
    assert_eq!(render_plugins_section(&[]), None);
}
```

**验证点**：
- 输入空切片时返回 `None`
- 不会生成空的 XML 标签

### 测试用例 2：完整渲染验证

```rust
#[test]
fn render_plugins_section_includes_descriptions_and_skill_naming_guidance() {
    let rendered = render_plugins_section(&[PluginCapabilitySummary {
        config_name: "sample@test".to_string(),
        display_name: "sample".to_string(),
        description: Some("inspect sample data".to_string()),
        has_skills: true,
        ..PluginCapabilitySummary::default()
    }])
    .expect("plugin section should render");

    let expected = "<plugins_instructions>\n## Plugins\nA plugin is a local bundle of skills, MCP servers, and apps. Below is the list of plugins that are enabled and available in this session.\n### Available plugins\n- `sample`: inspect sample data\n### How to use plugins\n- Discovery: The list above is the plugins available in this session.\n- Skill naming: If a plugin contributes skills, those skill entries are prefixed with `plugin_name:` in the Skills list.\n- Trigger rules: If the user explicitly names a plugin, prefer capabilities associated with that plugin for that turn.\n- Relationship to capabilities: Plugins are not invoked directly. Use their underlying skills, MCP tools, and app tools to help solve the task.\n- Preference: When a relevant plugin is available, prefer using capabilities associated with that plugin over standalone capabilities that provide similar functionality.\n- Missing/blocked: If the user requests a plugin that is not listed above, or the plugin does not have relevant callable capabilities for the task, say so briefly and continue with the best fallback.\n</plugins_instructions>";

    assert_eq!(rendered, expected);
}
```

**验证点**：
- XML 标签正确包裹
- 标题和说明文本完整
- 插件名称和描述正确格式化
- 使用指导部分完整

---

## 关键代码路径与文件引用

### 被测试的函数

| 函数 | 所在文件 | 功能 |
|------|----------|------|
| `render_plugins_section` | `render.rs:5` | 渲染插件列表指令 |

### 使用的类型

| 类型 | 来源 | 用途 |
|------|------|------|
| `PluginCapabilitySummary` | `manager.rs` | 测试数据构造 |

### 测试依赖

```rust
use super::*;  // 导入 render.rs 的所有导出项
use pretty_assertions::assert_eq;  // 美化断言输出
```

---

## 依赖与外部交互

### 测试框架

| 依赖 | 用途 |
|------|------|
| `pretty_assertions` | 提供清晰的差异对比 |
| `std` 内置测试框架 | 测试执行 |

### 测试数据

测试使用硬编码的 `PluginCapabilitySummary` 结构体：

```rust
PluginCapabilitySummary {
    config_name: "sample@test".to_string(),  // 完整配置名
    display_name: "sample".to_string(),       // 显示名
    description: Some("inspect sample data".to_string()),  // 描述
    has_skills: true,                         // 有 skills
    ..PluginCapabilitySummary::default()      // 其余字段默认
}
```

---

## 风险、边界与改进建议

### 当前覆盖缺口

| 功能 | 覆盖状态 | 风险 |
|------|----------|------|
| `render_plugins_section` 空列表 | ✅ | 低 |
| `render_plugins_section` 完整渲染 | ✅ | 低 |
| `render_plugins_section` 多插件 | ❌ | 中 |
| `render_plugins_section` 无描述 | ❌ | 低 |
| `render_explicit_plugin_instructions` | ❌ | **高** |
| 特殊字符处理 | ❌ | 中 |
| 超长描述 | ❌ | 低 |

### 未测试的函数

`render_explicit_plugin_instructions` 函数完全没有测试覆盖：

```rust
pub(crate) fn render_explicit_plugin_instructions(
    plugin: &PluginCapabilitySummary,
    available_mcp_servers: &[String],
    available_apps: &[String],
) -> Option<String>
```

### 改进建议

1. **添加 `render_explicit_plugin_instructions` 测试**：

```rust
#[test]
fn render_explicit_plugin_instructions_with_all_capabilities() {
    let plugin = PluginCapabilitySummary {
        config_name: "github@openai-curated".to_string(),
        display_name: "github".to_string(),
        description: Some("GitHub integration".to_string()),
        has_skills: true,
        mcp_server_names: vec!["github-mcp".to_string()],
        app_connector_ids: vec![AppConnectorId("github-connector".to_string())],
    };
    
    let result = render_explicit_plugin_instructions(
        &plugin,
        &["github-mcp".to_string()],
        &["github-connector".to_string()],
    );
    
    assert!(result.is_some());
    let text = result.unwrap();
    assert!(text.contains("github"));
    assert!(text.contains("github-mcp"));
    assert!(text.contains("github-connector"));
}

#[test]
fn render_explicit_plugin_instructions_returns_none_for_no_capabilities() {
    let plugin = PluginCapabilitySummary {
        config_name: "empty@market".to_string(),
        display_name: "empty".to_string(),
        has_skills: false,
        ..Default::default()
    };
    
    let result = render_explicit_plugin_instructions(&plugin, &[], &[]);
    assert_eq!(result, None);
}
```

2. **添加多插件测试**：

```rust
#[test]
fn render_plugins_section_with_multiple_plugins() {
    let plugins = vec![
        PluginCapabilitySummary {
            config_name: "plugin1@test".to_string(),
            display_name: "plugin1".to_string(),
            description: Some("First plugin".to_string()),
            has_skills: true,
            ..Default::default()
        },
        PluginCapabilitySummary {
            config_name: "plugin2@test".to_string(),
            display_name: "plugin2".to_string(),
            description: None,  // 无描述
            has_skills: false,
            ..Default::default()
        },
    ];
    
    let result = render_plugins_section(&plugins);
    assert!(result.is_some());
    let text = result.unwrap();
    assert!(text.contains("- `plugin1`: First plugin"));
    assert!(text.contains("- `plugin2`"));
    assert!(!text.contains("- `plugin2`:"));  // 确保无冒号
}
```

3. **使用快照测试**：

```rust
use insta::assert_snapshot;

#[test]
fn render_plugins_section_snapshot() {
    let plugins = vec![/* ... */];
    let result = render_plugins_section(&plugins).unwrap();
    assert_snapshot!(result);
}
```

4. **参数化测试**：

```rust
use test_case::test_case;

#[test_case(true, Some("desc".to_string()), "- `name`: desc" ; "with description")]
#[test_case(true, None, "- `name`" ; "without description")]
#[test_case(false, Some("desc".to_string()), "- `name`: desc" ; "no skills with description")]
fn test_plugin_rendering(has_skills: bool, desc: Option<String>, expected: &str) {
    // ...
}
```

### 维护风险

1. **硬编码预期字符串**：
   - 风险：当 `render.rs` 中的模板变更时，测试需要同步更新
   - 缓解：使用快照测试（`insta`）简化更新流程

2. **测试数据不完整**：
   - 风险：`PluginCapabilitySummary::default()` 可能在未来版本变更
   - 建议：显式设置所有字段

3. **缺少负面测试**：
   - 风险：未测试错误处理路径
   - 建议：添加异常输入测试
