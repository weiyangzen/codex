# mentions.rs 研究文档

## 场景与职责

`mentions.rs` 是 Codex 核心库中处理用户输入中提及（mention）解析和收集的模块。它负责：

1. **工具提及收集**：从用户文本输入中提取工具引用（如 `$calendar`）
2. **应用 ID 提取**：识别并收集用户明确提及的应用（app）ID
3. **插件提及收集**：识别并收集用户明确提及的插件
4. **技能名称统计**：构建技能名称的精确匹配和大小写不敏感匹配计数
5. **连接器别名统计**：构建连接器 slug 的计数，用于消歧

该模块是 Codex 输入处理管道的关键组件，确保系统正确识别用户意图引用的工具、应用、插件和技能。

## 功能点目的

### 1. 工具提及收集 `collect_tool_mentions_from_messages`

**目的**：从多条文本消息中收集工具提及。

**流程**：
1. 遍历所有消息
2. 使用默认工具提及符号（`$`）提取提及
3. 合并所有提及的名称和路径

**返回**：`CollectedToolMentions` 结构，包含：
- `plain_names`：纯文本提及的名称集合
- `paths`：链接格式提及的路径集合

### 2. 应用 ID 提取 `collect_explicit_app_ids`

**目的**：从用户输入中提取明确引用的应用 ID。

**输入来源**：
- 结构化 `UserInput::Mention` 类型的路径
- 文本输入中的链接提及（如 `[$calendar](app://calendar)`）

**过滤逻辑**：
- 只保留 `app://` 路径协议的提及
- 提取 connector ID（如 `app://calendar` → `calendar`）

**使用场景**：
- 确定用户明确请求使用哪些应用
- 用于应用选择和分析跟踪

### 3. 插件提及收集 `collect_explicit_plugin_mentions`

**目的**：从用户输入中提取明确引用的插件。

**输入来源**：
- 结构化 `UserInput::Mention` 类型的路径
- 文本输入中的链接提及（使用 `@` 符号，如 `[@sample](plugin://sample@test)`）

**匹配逻辑**：
- 解析插件配置名称（如 `plugin://sample@test` → `sample@test`）
- 与可用插件列表匹配
- 返回匹配的 `PluginCapabilitySummary` 列表

### 4. 技能名称统计 `build_skill_name_counts`

**目的**：构建技能名称的计数映射，用于消歧。

**输出**：
- `exact_counts`：精确名称计数
- `lower_counts`：小写名称计数

**用途**：
- 当用户通过名称（而非路径）引用技能时，判断引用是否唯一
- 如果名称不唯一，可能需要用户通过路径明确指定

### 5. 连接器别名统计 `build_connector_slug_counts`

**目的**：构建连接器 slug 的计数映射，用于技能提及消歧。

**逻辑**：
- 遍历所有可用连接器
- 使用 `connectors::connector_mention_slug` 生成 slug
- 统计每个 slug 的出现次数

**用途**：
- 防止技能名称与连接器 slug 冲突时的误识别
- 如果技能名称与连接器 slug 相同，可能需要额外验证

## 具体技术实现

### 关键数据结构

```rust
// 收集的工具提及
pub(crate) struct CollectedToolMentions {
    pub(crate) plain_names: HashSet<String>,  // 纯文本提及的名称
    pub(crate) paths: HashSet<String>,        // 链接格式的路径
}

// 技能选择上下文（来自 skills/injection.rs）
struct SkillSelectionContext<'a> {
    skills: &'a [SkillMetadata],
    disabled_paths: &'a HashSet<PathBuf>,
    skill_name_counts: &'a HashMap<String, usize>,
    connector_slug_counts: &'a HashMap<String, usize>,
}
```

### 应用 ID 提取流程

```rust
pub(crate) fn collect_explicit_app_ids(input: &[UserInput]) -> HashSet<String> {
    // 1. 提取所有文本消息
    let messages = input
        .iter()
        .filter_map(|item| match item {
            UserInput::Text { text, .. } => Some(text.clone()),
            _ => None,
        })
        .collect::<Vec<String>>();

    // 2. 合并结构化提及和文本提及的路径
    input
        .iter()
        .filter_map(|item| match item {
            UserInput::Mention { path, .. } => Some(path.clone()),
            _ => None,
        })
        .chain(collect_tool_mentions_from_messages(&messages).paths)
        // 3. 过滤只保留 app:// 路径
        .filter(|path| tool_kind_for_path(path.as_str()) == ToolMentionKind::App)
        // 4. 提取 connector ID
        .filter_map(|path| app_id_from_path(path.as_str()).map(str::to_string))
        .collect()
}
```

### 插件提及收集流程

```rust
pub(crate) fn collect_explicit_plugin_mentions(
    input: &[UserInput],
    plugins: &[PluginCapabilitySummary],
) -> Vec<PluginCapabilitySummary> {
    if plugins.is_empty() {
        return Vec::new();
    }

    // 1. 提取文本消息
    let messages = input
        .iter()
        .filter_map(|item| match item {
            UserInput::Text { text, .. } => Some(text.clone()),
            _ => None,
        })
        .collect::<Vec<String>>();

    // 2. 收集提及的配置名称
    let mentioned_config_names: HashSet<String> = input
        .iter()
        .filter_map(|item| match item {
            UserInput::Mention { path, .. } => Some(path.clone()),
            _ => None,
        })
        .chain(
            // 使用 @ 符号提取插件提及
            collect_tool_mentions_from_messages_with_sigil(&messages, PLUGIN_TEXT_MENTION_SIGIL)
                .paths,
        )
        .filter(|path| tool_kind_for_path(path.as_str()) == ToolMentionKind::Plugin)
        .filter_map(|path| plugin_config_name_from_path(path.as_str()).map(str::to_string))
        .collect();

    if mentioned_config_names.is_empty() {
        return Vec::new();
    }

    // 3. 与可用插件列表匹配
    plugins
        .iter()
        .filter(|plugin| mentioned_config_names.contains(plugin.config_name.as_str()))
        .cloned()
        .collect()
}
```

### 路径协议识别

```rust
pub(crate) enum ToolMentionKind {
    App,      // app://
    Mcp,      // mcp://
    Plugin,   // plugin://
    Skill,    // skill:// 或 SKILL.md
    Other,    // 其他
}

pub(crate) fn tool_kind_for_path(path: &str) -> ToolMentionKind {
    if path.starts_with(APP_PATH_PREFIX) {  // "app://"
        ToolMentionKind::App
    } else if path.starts_with(MCP_PATH_PREFIX) {  // "mcp://"
        ToolMentionKind::Mcp
    } else if path.starts_with(PLUGIN_PATH_PREFIX) {  // "plugin://"
        ToolMentionKind::Plugin
    } else if path.starts_with(SKILL_PATH_PREFIX) || is_skill_filename(path) {
        ToolMentionKind::Skill
    } else {
        ToolMentionKind::Other
    }
}
```

## 关键代码路径与文件引用

### 内部依赖

| 文件 | 用途 |
|------|------|
| `mention_syntax.rs` | `TOOL_MENTION_SIGIL`, `PLUGIN_TEXT_MENTION_SIGIL` |
| `mentions_tests.rs` | 单元测试 |
| `skills/injection.rs` | `extract_tool_mentions_with_sigil`, `tool_kind_for_path` 等 |
| `connectors.rs` | `AppInfo`, `connector_mention_slug` |
| `plugins.rs` | `PluginCapabilitySummary` |

### 外部依赖

| Crate/模块 | 用途 |
|------------|------|
| `codex_protocol::user_input::UserInput` | 用户输入类型 |

### 使用者

| 文件 | 使用方式 |
|------|----------|
| `codex.rs` | 调用 `collect_explicit_app_ids` 获取用户选择的应用 |
| `skills/injection.rs` | 使用 `build_skill_name_counts` 进行技能消歧 |

## 依赖与外部交互

### 与 skills/injection.rs 的交互

`mentions.rs` 依赖 `skills/injection.rs` 提供的函数：

```rust
use crate::skills::injection::extract_tool_mentions_with_sigil;
use crate::skills::injection::tool_kind_for_path;
use crate::skills::injection::app_id_from_path;
use crate::skills::injection::plugin_config_name_from_path;
```

这些函数实际执行提及提取和路径解析的核心逻辑。

### 与 connectors.rs 的交互

```rust
use crate::connectors;

pub(crate) fn build_connector_slug_counts(
    connectors: &[connectors::AppInfo],
) -> HashMap<String, usize> {
    let mut counts: HashMap<String, usize> = HashMap::new();
    for connector in connectors {
        let slug = connectors::connector_mention_slug(connector);
        *counts.entry(slug).or_insert(0) += 1;
    }
    counts
}
```

## 风险、边界与改进建议

### 已知风险

1. **循环依赖风险**：`mentions.rs` 和 `skills/injection.rs` 相互依赖可能导致循环依赖问题

2. **消歧逻辑分散**：技能消歧逻辑部分在 `mentions.rs`（计数构建），部分在 `skills/injection.rs`（选择逻辑），可能导致不一致

3. **路径解析重复**：`app_id_from_path` 等函数在多个地方可能有类似实现

### 边界情况

1. **空输入**：所有函数都能正确处理空输入，返回空集合

2. **重复提及**：使用 `HashSet` 自动去重，不会重复计数

3. **混合提及类型**：正确处理结构化提及和文本提及的混合

4. **大小写敏感**：技能名称计数同时维护精确和小写版本，支持大小写不敏感匹配

### 改进建议

1. **模块重构**：考虑将提及提取的核心逻辑从 `skills/injection.rs` 移到 `mentions.rs`，使 `mentions.rs` 成为完整的提及处理模块

2. **统一消歧**：将技能消歧逻辑集中到一个模块，避免逻辑分散

3. **缓存优化**：对于频繁调用的计数构建函数，考虑缓存结果

4. **错误处理**：当前函数都返回集合，对于解析错误静默忽略，考虑添加错误报告机制

5. **性能优化**：对于大规模输入，考虑使用并行处理

6. **文档完善**：添加更多使用示例和边界情况说明

7. **测试扩展**：添加更多边界情况测试，如：
   - 大量重复提及
   - 特殊字符路径
   - 空路径和无效路径

8. **类型安全**：考虑使用 newtype 模式包装路径字符串，提供更类型安全的 API
