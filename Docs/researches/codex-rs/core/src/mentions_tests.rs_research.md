# mentions_tests.rs 研究文档

## 场景与职责

`mentions_tests.rs` 是 `mentions.rs` 的配套测试模块，使用 Rust 的 `#[cfg(test)]` 条件编译属性嵌入到主模块中。该测试文件负责：

1. **单元测试覆盖**：对 `mentions.rs` 中的公共函数进行全面的单元测试
2. **应用 ID 提取验证**：验证从各种输入格式中提取应用 ID 的正确性
3. **插件提及验证**：验证插件提及的识别和匹配逻辑
4. **去重逻辑验证**：验证结构化提及和文本提及的去重处理
5. **边界情况测试**：测试无效路径、非目标路径的过滤

该测试模块是确保提及解析系统正确性和健壮性的关键保障。

## 功能点目的

### 1. 应用 ID 提取测试

#### 1.1 链接文本提及

**测试用例**：`collect_explicit_app_ids_from_linked_text_mentions`

**目的**：验证从 Markdown 链接格式的文本提及中提取应用 ID。

**输入**：`"use [$calendar](app://calendar)"`

**预期输出**：`{"calendar"}`

#### 1.2 结构化和链接提及去重

**测试用例**：`collect_explicit_app_ids_dedupes_structured_and_linked_mentions`

**目的**：验证同一应用的多种提及方式只被计数一次。

**输入**：
- 文本：`"use [$calendar](app://calendar)"`
- 结构化：`UserInput::Mention { name: "calendar", path: "app://calendar" }`

**预期输出**：`{"calendar"}`（去重后）

#### 1.3 非应用路径过滤

**测试用例**：`collect_explicit_app_ids_ignores_non_app_paths`

**目的**：验证非 `app://` 路径被正确过滤。

**输入**：
- `[$docs](mcp://docs)` - MCP 路径
- `[$skill](skill://team/skill)` - Skill 路径
- `[$file](/tmp/file.txt)` - 文件路径

**预期输出**：空集合

### 2. 插件提及收集测试

#### 2.1 结构化路径提及

**测试用例**：`collect_explicit_plugin_mentions_from_structured_paths`

**目的**：验证从结构化 `UserInput::Mention` 中提取插件。

**输入**：`UserInput::Mention { path: "plugin://sample@test" }`

**预期输出**：匹配的 `PluginCapabilitySummary` 列表

#### 2.2 链接文本提及

**测试用例**：`collect_explicit_plugin_mentions_from_linked_text_mentions`

**目的**：验证从 Markdown 链接格式的文本提及中提取插件。

**输入**：`"use [@sample](plugin://sample@test)"`

**预期输出**：匹配的 `PluginCapabilitySummary` 列表

#### 2.3 结构化和链接提及去重

**测试用例**：`collect_explicit_plugin_mentions_dedupes_structured_and_linked_mentions`

**目的**：验证同一插件的多种提及方式只被计数一次。

**输入**：
- 文本：`"use [@sample](plugin://sample@test)"`
- 结构化：`UserInput::Mention { path: "plugin://sample@test" }`

**预期输出**：单个插件（去重后）

#### 2.4 非插件路径过滤

**测试用例**：`collect_explicit_plugin_mentions_ignores_non_plugin_paths`

**目的**：验证非 `plugin://` 路径被正确过滤。

**输入**：
- `[$app](app://calendar)` - 应用路径
- `[$skill](skill://team/skill)` - Skill 路径
- `[$file](/tmp/file.txt)` - 文件路径

**预期输出**：空列表

#### 2.5 错误符号过滤

**测试用例**：`collect_explicit_plugin_mentions_ignores_dollar_linked_plugin_mentions`

**目的**：验证使用错误符号（`$` 而非 `@`）的插件提及被忽略。

**输入**：`"use [$sample](plugin://sample@test)"`（使用 `$` 而非 `@`）

**预期输出**：空列表

**说明**：插件提及必须使用 `@` 符号，`$` 符号用于工具和技能提及。

## 具体技术实现

### 测试辅助函数

```rust
// 创建文本输入
fn text_input(text: &str) -> UserInput {
    UserInput::Text {
        text: text.to_string(),
        text_elements: Vec::new(),
    }
}

// 创建插件摘要
fn plugin(config_name: &str, display_name: &str) -> PluginCapabilitySummary {
    PluginCapabilitySummary {
        config_name: config_name.to_string(),
        display_name: display_name.to_string(),
        description: None,
        has_skills: true,
        mcp_server_names: Vec::new(),
        app_connector_ids: Vec::new(),
    }
}
```

### 测试数据构造

```rust
// 混合输入
let input = vec![
    text_input("use [$calendar](app://calendar)"),
    UserInput::Mention {
        name: "calendar".to_string(),
        path: "app://calendar".to_string(),
    },
];

// 插件列表
let plugins = vec![
    plugin("sample@test", "sample"),
    plugin("other@test", "other"),
];
```

### 断言风格

```rust
use pretty_assertions::assert_eq;

// 集合比较
assert_eq!(app_ids, HashSet::from(["calendar".to_string()]));

// 列表比较
assert_eq!(mentioned, vec![plugin("sample@test", "sample")]);

// 空集合比较
assert_eq!(app_ids, HashSet::<String>::new());
assert_eq!(mentioned, Vec::<PluginCapabilitySummary>::new());
```

## 关键代码路径与文件引用

### 测试框架依赖

| Crate/模块 | 用途 |
|------------|------|
| `pretty_assertions::assert_eq` | 美观的断言输出 |
| `std::collections::HashSet` | 集合类型 |

### 被测试的模块

| 被测试项 | 测试覆盖 |
|----------|----------|
| `collect_explicit_app_ids` | 应用 ID 提取 |
| `collect_explicit_plugin_mentions` | 插件提及收集 |

### 依赖的类型

| 类型 | 来源 |
|------|------|
| `UserInput` | `codex_protocol::user_input` |
| `PluginCapabilitySummary` | `crate::plugins` |

## 依赖与外部交互

### 与 skills/injection.rs 的依赖

测试间接依赖 `skills/injection.rs` 提供的函数：
- `extract_tool_mentions_with_sigil`
- `tool_kind_for_path`
- `app_id_from_path`
- `plugin_config_name_from_path`

这些函数在 `mentions.rs` 中被调用，测试通过测试 `mentions.rs` 的函数间接测试了它们。

### 测试隔离

测试使用纯函数，不依赖外部状态：
- 无文件系统交互
- 无网络交互
- 无异步操作

## 风险、边界与改进建议

### 测试覆盖分析

**覆盖良好的区域**：
- 基本的应用 ID 提取
- 基本的插件提及收集
- 结构化提及和文本提及的去重
- 非目标路径的过滤

**潜在覆盖不足**：
- `build_skill_name_counts` 函数（无直接测试）
- `build_connector_slug_counts` 函数（无直接测试）
- `collect_tool_mentions_from_messages` 函数（无直接测试）
- 大规模输入的性能测试
- 特殊字符和边界情况

### 已知测试限制

1. **依赖实现细节**：测试依赖于 `skills/injection.rs` 的实现，如果该模块行为改变，测试可能失败

2. **无 Mock**：测试使用真实的辅助函数，无法隔离测试 `mentions.rs` 的逻辑

3. **有限的边界测试**：主要测试正常路径，边界情况覆盖不足

### 改进建议

1. **直接测试缺失函数**：添加对以下函数的直接测试：
   - `build_skill_name_counts`
   - `build_connector_slug_counts`
   - `collect_tool_mentions_from_messages`

2. **边界测试扩展**：
   - 空字符串路径
   - 特殊字符路径
   - 超长路径
   - 大量重复提及
   - 空插件列表

3. **错误场景测试**：
   - 无效的路径格式
   - 不存在的插件/应用 ID
   - 格式错误的提及

4. **性能测试**：
   - 大规模输入（1000+ 提及）
   - 大量插件列表的匹配性能

5. **集成测试**：
   - 与 `skills/injection.rs` 的集成测试
   - 端到端的提及解析流程测试

6. **属性测试**：
   - 使用 `proptest` 生成随机输入，验证函数的健壮性

7. **测试数据工厂**：
   - 创建更完善的测试数据工厂，减少重复代码
   - 支持生成各种边界情况的测试数据

8. **文档测试**：
   - 为公共函数添加文档测试示例

9. **测试组织**：
   - 按功能组织测试，使用 `mod` 分组
   - 添加测试描述注释，说明测试意图
