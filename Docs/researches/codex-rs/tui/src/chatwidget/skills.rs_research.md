# skills.rs 研究文档

## 场景与职责

`skills.rs` 实现了 Codex TUI 的 **Skills（技能）系统** 的 UI 层功能。Skills 是 Codex 的扩展机制，允许用户通过 `$skill-name` 语法在对话中调用预定义的功能模块。

**核心职责**：
1. **技能列表管理**：显示和管理可用技能列表
2. **技能启用/禁用**：允许用户启用或禁用特定技能
3. **工具提及（Tool Mention）解析**：解析用户输入中的 `$skill` 和 `[$$skill](path)` 语法
4. **技能与连接器（Connector）关联**：处理技能与外部应用的关联

**关键概念**：
- **Skill**：Codex 的功能扩展模块，定义在 `SKILL.md` 文件中
- **Tool Mention**：用户在输入中使用 `$skill-name` 引用技能
- **Linked Mention**：带路径的提及，如 `[$$my-skill](/path/to/skill)`
- **Connector**：外部应用连接器（如 ChatGPT 应用）

## 功能点目的

### 1. 技能列表界面

**`open_skills_list`**：
- 在输入框中插入 `$` 字符，触发技能列表显示
- 快捷方式：用户可以直接按 `$` 键打开技能列表

**`open_skills_menu`**：
- 显示技能操作菜单（列表查看、启用/禁用）
- 通过底部面板的选择视图呈现

**`open_manage_skills_popup`**：
- 显示技能启用/禁用界面
- 允许用户切换技能的启用状态
- 显示技能的显示名称和描述

### 2. 技能状态管理

**`update_skill_enabled`**：
- 更新特定技能的启用状态
- 根据路径匹配技能（支持路径规范化）

**`handle_manage_skills_closed`**：
- 处理技能管理弹窗关闭
- 统计并显示启用/禁用的技能数量

**`set_skills_from_response`**：
- 从服务器的 `ListSkillsResponseEvent` 解析技能列表
- 根据当前工作目录过滤技能

### 3. 工具提及解析

**`collect_tool_mentions`**：
- 从文本中提取工具提及
- 关联提及名称与路径

**`find_skill_mentions_with_tool_mentions`**：
- 根据提及查找匹配的技能元数据
- 支持通过路径或名称匹配

**`find_app_mentions`**：
- 查找与提及关联的应用（Connector）
- 处理 slug 冲突（多个应用具有相同 slug 时）

### 4. 提及语法解析

**`extract_tool_mentions_from_text`**：
- 解析文本中的工具提及
- 支持两种格式：
  - 简单提及：`$skill-name`
  - 链接提及：`[$$skill-name](path)`

**`parse_linked_tool_mention`**：
- 解析链接提及的详细逻辑
- 格式：`[$$name](path)`

## 具体技术实现

### 关键数据结构

#### 1. 工具提及结构

```rust
pub(crate) struct ToolMentions {
    names: HashSet<String>,        // 提及的名称集合
    linked_paths: HashMap<String, String>,  // 名称到路径的映射
}
```

#### 2. 技能元数据转换

```rust
fn protocol_skill_to_core(skill: &ProtocolSkillMetadata) -> SkillMetadata {
    SkillMetadata {
        name: skill.name.clone(),
        description: skill.description.clone(),
        short_description: skill.short_description.clone(),
        interface: skill.interface.clone().map(|interface| SkillInterface { ... }),
        dependencies: skill.dependencies.clone().map(|dependencies| SkillDependencies { ... }),
        policy: None,
        permission_profile: None,
        managed_network_override: None,
        path_to_skills_md: skill.path.clone(),
        scope: skill.scope,
    }
}
```

### 核心算法

#### 1. 技能列表过滤

```rust
fn skills_for_cwd(cwd: &Path, skills_entries: &[SkillsListEntry]) -> Vec<ProtocolSkillMetadata> {
    skills_entries
        .iter()
        .find(|entry| entry.cwd.as_path() == cwd)
        .map(|entry| entry.skills.clone())
        .unwrap_or_default()
}
```

**说明**：根据当前工作目录查找对应的技能列表。

#### 2. 启用技能过滤

```rust
fn enabled_skills_for_mentions(skills: &[ProtocolSkillMetadata]) -> Vec<SkillMetadata> {
    skills
        .iter()
        .filter(|skill| skill.enabled)
        .map(protocol_skill_to_core)
        .collect()
}
```

#### 3. 工具提及解析

```rust
fn extract_tool_mentions_from_text_with_sigil(text: &str, sigil: char) -> ToolMentions {
    let text_bytes = text.as_bytes();
    let mut names: HashSet<String> = HashSet::new();
    let mut linked_paths: HashMap<String, String> = HashMap::new();

    let mut index = 0;
    while index < text_bytes.len() {
        let byte = text_bytes[index];
        
        // 尝试解析链接提及 [$$name](path)
        if byte == b'[' && let Some((name, path, end_index)) = 
            parse_linked_tool_mention(text, text_bytes, index, sigil) {
            if !is_common_env_var(name) {
                if is_skill_path(path) {
                    names.insert(name.to_string());
                }
                linked_paths.entry(name.to_string()).or_insert(path.to_string());
            }
            index = end_index;
            continue;
        }

        // 解析简单提及 $name
        if byte != sigil as u8 { index += 1; continue; }
        
        let name_start = index + 1;
        // ... 解析名称逻辑
        
        let name = &text[name_start..name_end];
        if !is_common_env_var(name) {
            names.insert(name.to_string());
        }
        index = name_end;
    }

    ToolMentions { names, linked_paths }
}
```

#### 4. 链接提及解析

```rust
fn parse_linked_tool_mention<'a>(
    text: &'a str,
    text_bytes: &[u8],
    start: usize,
    sigil: char,
) -> Option<(&'a str, &'a str, usize)> {
    // 格式: [$$name](path)
    // start 指向 '['
    
    let sigil_index = start + 1;
    if text_bytes.get(sigil_index) != Some(&(sigil as u8)) {
        return None;  // 第二个字符必须是 sigil
    }

    let name_start = sigil_index + 1;
    let first_name_byte = text_bytes.get(name_start)?;
    if !is_mention_name_char(*first_name_byte) {
        return None;
    }

    // 解析名称
    let mut name_end = name_start + 1;
    while let Some(next_byte) = text_bytes.get(name_end)
        && is_mention_name_char(*next_byte)
    {
        name_end += 1;
    }

    // 验证 ']' 和 '(' 的位置
    if text_bytes.get(name_end) != Some(&b']') { return None; }
    
    // 解析路径
    let mut path_start = name_end + 1;
    while let Some(next_byte) = text_bytes.get(path_start)
        && next_byte.is_ascii_whitespace()
    {
        path_start += 1;
    }
    if text_bytes.get(path_start) != Some(&b'(') { return None; }

    let mut path_end = path_start + 1;
    while let Some(next_byte) = text_bytes.get(path_end)
        && *next_byte != b')'
    {
        path_end += 1;
    }
    if text_bytes.get(path_end) != Some(&b')') { return None; }

    let path = text[path_start + 1..path_end].trim();
    if path.is_empty() { return None; }

    let name = &text[name_start..name_end];
    Some((name, path, path_end + 1))
}
```

#### 5. 技能匹配算法

```rust
pub(crate) fn find_skill_mentions_with_tool_mentions(
    mentions: &ToolMentions,
    skills: &[SkillMetadata],
) -> Vec<SkillMetadata> {
    let mention_skill_paths: HashSet<&str> = mentions
        .linked_paths
        .values()
        .filter(|path| is_skill_path(path))
        .map(|path| normalize_skill_path(path))
        .collect();

    let mut seen_names = HashSet::new();
    let mut seen_paths = HashSet::new();
    let mut matches: Vec<SkillMetadata> = Vec::new();

    // 第一轮：匹配路径
    for skill in skills {
        if seen_paths.contains(&skill.path_to_skills_md) { continue; }
        let path_str = skill.path_to_skills_md.to_string_lossy();
        if mention_skill_paths.contains(path_str.as_ref()) {
            seen_paths.insert(skill.path_to_skills_md.clone());
            seen_names.insert(skill.name.clone());
            matches.push(skill.clone());
        }
    }

    // 第二轮：匹配名称（排除已匹配的路径）
    for skill in skills {
        if seen_paths.contains(&skill.path_to_skills_md) { continue; }
        if mentions.names.contains(&skill.name) && seen_names.insert(skill.name.clone()) {
            seen_paths.insert(skill.path_to_skills_md.clone());
            matches.push(skill.clone());
        }
    }

    matches
}
```

**优先级**：路径匹配优先于名称匹配。

#### 6. 应用提及查找

```rust
pub(crate) fn find_app_mentions(
    mentions: &ToolMentions,
    apps: &[AppInfo],
    skill_names_lower: &HashSet<String>,
) -> Vec<AppInfo> {
    let mut explicit_names = HashSet::new();
    let mut selected_ids = HashSet::new();
    
    // 第一轮：显式路径匹配
    for (name, path) in &mentions.linked_paths {
        if let Some(connector_id) = app_id_from_path(path) {
            explicit_names.insert(name.clone());
            selected_ids.insert(connector_id.to_string());
        }
    }

    // 统计 slug 出现次数
    let mut slug_counts: HashMap<String, usize> = HashMap::new();
    for app in apps.iter().filter(|app| app.is_enabled) {
        let slug = connector_mention_slug(app);
        *slug_counts.entry(slug).or_insert(0) += 1;
    }

    // 第二轮：slug 匹配（仅当 slug 唯一且不是技能名称时）
    for app in apps.iter().filter(|app| app.is_enabled) {
        let slug = connector_mention_slug(app);
        let slug_count = slug_counts.get(&slug).copied().unwrap_or(0);
        if mentions.names.contains(&slug)
            && !explicit_names.contains(&slug)
            && slug_count == 1
            && !skill_names_lower.contains(&slug)
        {
            selected_ids.insert(app.id.clone());
        }
    }

    apps.iter()
        .filter(|app| app.is_enabled && selected_ids.contains(&app.id))
        .cloned()
        .collect()
}
```

**冲突解决**：当多个应用具有相同 slug 时，需要显式路径指定。

### 辅助函数

#### 1. 路径类型判断

```rust
fn is_skill_path(path: &str) -> bool {
    !path.starts_with("app://") && !path.starts_with("mcp://") && !path.starts_with("plugin://")
}

fn normalize_skill_path(path: &str) -> &str {
    path.strip_prefix("skill://").unwrap_or(path)
}

fn app_id_from_path(path: &str) -> Option<&str> {
    path.strip_prefix("app://").filter(|value| !value.is_empty())
}
```

#### 2. 提及名称字符判断

```rust
fn is_mention_name_char(byte: u8) -> bool {
    matches!(byte, b'a'..=b'z' | b'A'..=b'Z' | b'0'..=b'9' | b'_' | b'-')
}
```

#### 3. 环境变量过滤

```rust
fn is_common_env_var(name: &str) -> bool {
    let upper = name.to_ascii_uppercase();
    matches!(
        upper.as_str(),
        "PATH" | "HOME" | "USER" | "SHELL" | "PWD" | "TMPDIR" | "TEMP" | "TMP" 
        | "LANG" | "TERM" | "XDG_CONFIG_HOME"
    )
}
```

**目的**：避免将常见的环境变量名误判为技能提及。

#### 4. 路径规范化

```rust
fn normalize_skill_config_path(path: &Path) -> PathBuf {
    dunce::canonicalize(path).unwrap_or_else(|_| path.to_path_buf())
}
```

**使用 `dunce` 库**：处理 Windows 路径的 UNC 前缀问题。

## 关键代码路径与文件引用

### 本文件关键定义

| 定义 | 行号 | 说明 |
|------|------|------|
| `collect_tool_mentions` | 205-216 | 收集工具提及 |
| `find_skill_mentions_with_tool_mentions` | 218-256 | 查找技能提及 |
| `find_app_mentions` | 258-294 | 查找应用提及 |
| `ToolMentions` | 296-299 | 工具提及结构体 |
| `extract_tool_mentions_from_text` | 301-362 | 提取工具提及 |
| `parse_linked_tool_mention` | 364-419 | 解析链接提及 |
| `is_common_env_var` | 421-437 | 环境变量过滤 |
| `is_mention_name_char` | 439-441 | 提及名称字符判断 |
| `is_skill_path` | 443-445 | 技能路径判断 |
| `normalize_skill_path` | 447-449 | 路径规范化 |
| `app_id_from_path` | 451-454 | 应用 ID 提取 |

### ChatWidget 方法

| 方法 | 行号 | 说明 |
|------|------|------|
| `open_skills_list` | 27-29 | 打开技能列表 |
| `open_skills_menu` | 31-60 | 打开技能菜单 |
| `open_manage_skills_popup` | 62-95 | 打开技能管理弹窗 |
| `update_skill_enabled` | 97-105 | 更新技能启用状态 |
| `handle_manage_skills_closed` | 107-138 | 处理管理弹窗关闭 |
| `set_skills_from_response` | 140-145 | 从响应设置技能 |

### 调用方（在 chatwidget.rs 中）

| 代码位置 | 调用方式 | 用途 |
|---------|---------|------|
| `chatwidget.rs:281` | `use self::skills::collect_tool_mentions` | 导入函数 |
| `chatwidget.rs:282` | `use self::skills::find_app_mentions` | 导入函数 |
| `chatwidget.rs:283` | `use self::skills::find_skill_mentions_with_tool_mentions` | 导入函数 |
| `chatwidget.rs:677` | `skills_all: Vec<ProtocolSkillMetadata>` | 技能列表存储 |
| `chatwidget.rs:1359` | `self.set_skills(...)` | 设置技能 |
| `chatwidget.rs:1495` | `fn set_skills(...)` | 设置技能到底部面板 |
| `chatwidget.rs:4551` | `self.open_skills_menu()` | 打开技能菜单 |
| `chatwidget.rs:8891` | `self.set_skills_from_response(&ev)` | 从响应设置技能 |

### 依赖模块

| 模块 | 类型 | 用途 |
|------|------|------|
| `crate::skills_helpers` | 模块 | 技能显示名称和描述 |
| `codex_core::skills::model` | 模块 | 技能元数据模型 |
| `codex_core::mention_syntax` | 模块 | 提及语法常量 |
| `codex_chatgpt::connectors` | 模块 | 应用连接器 |
| `dunce` | crate | 路径规范化 |

## 依赖与外部交互

### 核心依赖

1. **`codex_core::skills`**：
   - `SkillMetadata`：技能元数据
   - `SkillInterface`：技能界面定义
   - `SkillDependencies`：技能依赖

2. **`codex_protocol`**：
   - `ListSkillsResponseEvent`：技能列表响应
   - `ProtocolSkillMetadata`：协议层技能元数据
   - `SkillsListEntry`：技能列表条目

3. **`codex_chatgpt::connectors`**：
   - `AppInfo`：应用信息
   - `connector_mention_slug`：生成提及 slug

4. **工具库**：
   - `dunce::canonicalize`：跨平台路径规范化

### 提及语法

**简单提及**：
```
$skill-name
```

**链接提及**：
```
[$$skill-name](path/to/skill)
[$$skill-name](skill://path/to/skill)
[$$app-name](app://connector-id)
```

### 与 ChatWidget 的集成

`skills.rs` 作为 `ChatWidget` 的 `impl` 块的一部分，直接访问：
- `self.skills_all`：所有可用技能
- `self.skills_initial_state`：技能初始状态（用于比较变更）
- `self.bottom_pane`：底部面板控制
- `self.app_event_tx`：应用事件发送器
- `self.config`：配置对象

## 风险、边界与改进建议

### 风险点

1. **路径安全问题**：
   - 使用 `dunce::canonicalize` 可能暴露文件系统信息
   - 路径遍历攻击风险（虽然输入来自用户自己的输入）

2. **性能问题**：
   - `find_skill_mentions_with_tool_mentions` 使用双重循环
   - 技能数量大时可能影响性能

3. **解析歧义**：
   - `$PATH` 等环境变量名可能被误判
   - 虽然有过滤，但可能不完整

4. **字符编码**：
   - 当前解析基于字节操作，可能对多字节字符处理不当
   - 提及名称仅支持 ASCII 字符

### 边界情况

1. **空路径**：
   - `parse_linked_tool_mention` 会拒绝空路径

2. **重复提及**：
   - `ToolMentions.names` 使用 `HashSet` 自动去重
   - `linked_paths` 使用 `entry(...).or_insert()` 保留第一个路径

3. **大小写敏感**：
   - 技能名称匹配是大小写敏感的
   - 但 `is_common_env_var` 转换为大写比较

4. **路径格式**：
   - 支持 `skill://`、`app://`、`mcp://`、`plugin://` 等协议前缀
   - 普通路径默认为技能路径

### 改进建议

1. **性能优化**：
   ```rust
   // 使用索引加速查找
   struct SkillIndex {
       by_name: HashMap<String, usize>,
       by_path: HashMap<PathBuf, usize>,
       skills: Vec<SkillMetadata>,
   }
   ```

2. **增强解析器**：
   - 支持 Unicode 字符的提及名称
   - 使用 `regex` 或 `nom` 实现更健壮的解析

3. **更好的错误报告**：
   - 当用户输入无效提及时提供提示
   - 显示可用的技能建议

4. **缓存机制**：
   - 缓存技能列表，避免重复解析
   - 使用 `Arc<SkillMetadata>` 减少克隆

5. **安全配置**：
   - 限制可访问的技能路径范围
   - 验证技能路径是否在允许的目录内

6. **测试覆盖**：
   - 当前模块缺乏单元测试
   - 建议添加提及解析、技能匹配等测试

7. **文档完善**：
   - 添加提及语法的详细文档
   - 提供示例和最佳实践
