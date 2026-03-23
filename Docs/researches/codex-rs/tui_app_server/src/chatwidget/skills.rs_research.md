# skills.rs 研究文档

## 场景与职责

`skills.rs` 是 Codex TUI App Server 中 `ChatWidget` 模块的子模块，负责**技能（Skills）系统的 UI 层管理**。技能是 Codex 的扩展机制，允许用户通过 `SKILL.md` 文件定义自定义功能，并在对话中通过 `$skill-name` 语法引用。

**核心职责**：
1. **技能列表 UI**：显示可用技能列表，支持启用/禁用
2. **技能提及解析**：从用户输入中提取技能提及（`$skill-name`）
3. **连接器（App）提及解析**：从用户输入中提取连接器提及
4. **技能状态管理**：跟踪技能的启用/禁用状态
5. **协议转换**：在 UI 层协议和核心层协议之间转换技能元数据

## 功能点目的

### 1. 技能列表 UI

**打开技能列表** (`open_skills_list`)：
- 在输入框中插入 `$` 字符，触发技能选择弹窗

**打开技能菜单** (`open_skills_menu`)：
- 显示技能操作菜单（"List skills"、"Enable/Disable Skills"）

**打开技能管理弹窗** (`open_manage_skills_popup`)：
- 显示所有可用技能的开关列表
- 支持批量启用/禁用
- 显示变更统计（"X skills enabled, Y skills disabled"）

### 2. 技能提及解析

**工具提及收集** (`collect_tool_mentions`)：
```rust
pub(crate) fn collect_tool_mentions(
    text: &str,
    mention_paths: &HashMap<String, String>,
) -> ToolMentions
```

从文本中提取 `$skill-name` 格式的提及，支持两种形式：
- 简单提及：`$skill-name`
- 链接提及：`[$skill-name](path/to/skill.md)`

**技能提及查找** (`find_skill_mentions_with_tool_mentions`)：
- 优先匹配显式路径链接
- 其次匹配名称（仅当名称唯一时）
- 避免重复匹配同一技能

**连接器提及查找** (`find_app_mentions`)：
- 从 `app://` 路径中提取连接器 ID
- 处理 slug 冲突（当多个连接器有相同 slug 时）

### 3. 协议转换

**协议技能转核心技能** (`protocol_skill_to_core`)：
将 `codex_protocol::protocol::SkillMetadata` 转换为 `codex_core::skills::model::SkillMetadata`

### 4. 技能状态管理

**更新技能启用状态** (`update_skill_enabled`)：
- 更新指定路径技能的启用状态
- 同步更新底部面板的技能列表

**从响应设置技能** (`set_skills_from_response`)：
- 根据当前工作目录过滤技能
- 初始化技能列表

## 具体技术实现

### 关键数据结构

**工具提及**：
```rust
pub(crate) struct ToolMentions {
    names: HashSet<String>,      // 提及的名称集合
    linked_paths: HashMap<String, String>,  // 名称到路径的映射
}
```

**技能切换项**（用于 UI）：
```rust
// 在 bottom_pane 中定义
pub(crate) struct SkillsToggleItem {
    pub name: String,
    pub skill_name: String,
    pub description: String,
    pub enabled: bool,
    pub path: PathBuf,
}
```

### 提及解析算法

**文本扫描流程** (`extract_tool_mentions_from_text_with_sigil`)：

1. **链接提及解析**：
   ```
   格式: [$name](path)
   示例: [$my-skill](skill://path/to/skill.md)
   ```
   - 检测 `[` 开头
   - 解析 `$name` 和 `path`
   - 跳过常见环境变量（如 `$PATH`、`$HOME`）

2. **简单提及解析**：
   ```
   格式: $name
   示例: $my-skill
   ```
   - 检测 `$` 字符
   - 解析后续的有效名称字符（字母、数字、`_`、`-`）
   - 跳过常见环境变量

**有效名称字符**：
```rust
fn is_mention_name_char(byte: u8) -> bool {
    matches!(byte, b'a'..=b'z' | b'A'..=b'Z' | b'0'..=b'9' | b'_' | b'-')
}
```

**路径类型判断**：
```rust
fn is_skill_path(path: &str) -> bool {
    !path.starts_with("app://") 
        && !path.starts_with("mcp://") 
        && !path.starts_with("plugin://")
}
```

### 技能匹配算法

**优先级**：
1. 显式路径链接（`[$name](skill://path)`）
2. 名称匹配（仅当名称唯一且不与连接器冲突时）

**去重策略**：
- 使用 `HashSet` 跟踪已匹配的路径和名称
- 避免同一技能被多次匹配

### 代码示例：技能管理弹窗关闭处理

```rust
pub(crate) fn handle_manage_skills_closed(&mut self) {
    let Some(initial_state) = self.skills_initial_state.take() else {
        return;
    };
    
    // 计算当前状态
    let mut current_state = HashMap::new();
    for skill in &self.skills_all {
        current_state.insert(normalize_skill_config_path(&skill.path), skill.enabled);
    }
    
    // 统计变更
    let mut enabled_count = 0;
    let mut disabled_count = 0;
    for (path, was_enabled) in initial_state {
        if let Some(is_enabled) = current_state.get(&path) {
            if was_enabled != *is_enabled {
                if *is_enabled { enabled_count += 1; }
                else { disabled_count += 1; }
            }
        }
    }
    
    // 显示变更提示
    if enabled_count > 0 || disabled_count > 0 {
        self.add_info_message(
            format!("{enabled_count} skills enabled, {disabled_count} skills disabled"),
            None,
        );
    }
}
```

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/tui_app_server/src/chatwidget/skills.rs` (454 行)

### 父模块
- `codex-rs/tui_app_server/src/chatwidget.rs`
  - 行 326-329: 模块导入和公开接口
  - 行 732: `skills_all: Vec<ProtocolSkillMetadata>` 字段
  - 行 733: `skills_initial_state: Option<HashMap<PathBuf, bool>>` 字段

### 底部面板（UI 实现）
- `codex-rs/tui_app_server/src/bottom_pane/mod.rs`
  - `SkillsToggleView`: 技能开关列表视图
  - `SkillsToggleItem`: 技能开关项
- `codex-rs/tui_app_server/src/bottom_pane/skill_popup.rs`
  - 技能选择弹窗

### 核心层技能定义
- `codex-rs/core/src/skills/model.rs`
  - `SkillMetadata`: 核心技能元数据
  - `SkillInterface`: 技能界面定义
  - `SkillDependencies`: 技能依赖

### 技能注入逻辑
- `codex-rs/core/src/skills/injection.rs`
  - 类似的提及解析逻辑
  - `ToolMentions` 结构体
  - `extract_tool_mentions_with_sigil` 函数

### 协议定义
- `codex-rs/protocol/src/protocol.rs`
  - `ListSkillsResponseEvent`: 技能列表响应
  - `SkillMetadata`: 协议层技能元数据
  - `SkillsListEntry`: 按目录组织的技能列表

### 提及语法
- `codex-rs/core/src/mention_syntax.rs`
  - `TOOL_MENTION_SIGIL`: 工具提及符号（`$`）

### 连接器（Apps）
- `codex-rs/tui_app_server/src/skills_helpers.rs`
  - `skill_display_name`: 获取技能显示名称
  - `skill_description`: 获取技能描述
- `codex-rs/codex_chatgpt/src/connectors.rs`
  - `AppInfo`: 连接器信息
  - `connector_mention_slug`: 生成连接器提及 slug

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|-----|------|
| `std::collections::{HashMap, HashSet}` | 提及解析和去重 |
| `std::path::{Path, PathBuf}` | 技能路径处理 |
| `codex_core::skills::model::*` | 核心技能模型 |
| `codex_protocol::protocol::*` | 协议类型 |
| `codex_chatgpt::connectors::AppInfo` | 连接器信息 |
| `dunce::canonicalize` | 路径规范化 |

### 与 ChatWidget 的交互
- 通过 `ChatWidget` 方法操作底部面板
- 通过 `app_event_tx` 发送事件
- 访问 `config.cwd` 进行按目录技能过滤

### 与底部面板的交互
- 调用 `bottom_pane.show_selection_view` 显示选择视图
- 调用 `bottom_pane.show_view` 显示技能开关视图
- 调用 `bottom_pane.set_skills` 更新技能列表

### 与后端的交互
- 发送 `AppCommand::list_skills` 请求技能列表
- 接收 `ListSkillsResponseEvent` 响应

## 风险、边界与改进建议

### 当前风险

1. **提及解析与核心层重复**
   - `codex-rs/core/src/skills/injection.rs` 有几乎相同的解析逻辑
   - 维护两份代码容易引入不一致
   - 建议：将解析逻辑提取到共享库

2. **路径规范化依赖 `dunce`**
   - 使用外部 crate 进行路径规范化
   - 如果失败则回退到原始路径，可能导致路径不匹配
   ```rust
   fn normalize_skill_config_path(path: &Path) -> PathBuf {
       dunce::canonicalize(path).unwrap_or_else(|_| path.to_path_buf())
   }
   ```

3. **环境变量过滤硬编码**
   - 常见环境变量列表硬编码在代码中
   - 可能遗漏某些环境变量
   ```rust
   fn is_common_env_var(name: &str) -> bool {
       matches!(upper.as_str(), "PATH" | "HOME" | "USER" | ...)
   }
   ```

4. **技能名称冲突处理**
   - 仅当名称完全唯一时才匹配简单提及
   - 用户可能不清楚为什么某些提及不工作

### 边界情况

1. **空技能列表**
   - `open_manage_skills_popup` 在空列表时显示 "No skills available."

2. **路径规范化失败**
   - 使用原始路径作为回退，可能导致重复技能条目

3. **大小写敏感**
   - 技能名称匹配是大小写敏感的
   - 但连接器 slug 比较时转换为小写

### 改进建议

1. **统一提及解析逻辑**
   ```rust
   // 建议创建共享库
   pub mod mention_parser {
       pub fn extract_mentions(text: &str, sigil: char) -> Mentions;
   }
   ```

2. **添加提及验证**
   - 在用户输入时实时验证提及是否有效
   - 无效提及显示警告或建议

3. **改进冲突提示**
   - 当提及有歧义时，显示可能的选项
   - 引导用户使用显式路径链接

4. **添加技能搜索**
   ```rust
   pub(crate) fn search_skills(&self, query: &str) -> Vec<&SkillMetadata> {
       // 根据名称、描述搜索技能
   }
   ```

5. **技能分组显示**
   - 按作用域（User/Repo/System）分组显示技能
   - 提高技能列表的可读性

6. **添加技能详情预览**
   - 在技能列表中显示技能描述和依赖
   - 帮助用户了解技能功能

### 相关测试
- `codex-rs/tui_app_server/src/chatwidget/tests.rs`
  - 技能提及解析的集成测试
- `codex-rs/core/src/skills/injection_tests.rs`
  - 核心层提及解析的单元测试

### 架构思考

技能系统是 Codex 的重要扩展机制，该模块展示了：
- **分层架构**：UI 层、协议层、核心层分离
- **提及语法**：统一的 `$name` 语法用于引用外部功能
- **路径协议**：使用 `skill://`、`app://`、`mcp://` 等协议区分资源类型

**潜在改进方向**：
1. 技能版本管理
2. 技能依赖自动安装
3. 技能市场/发现机制
4. 技能权限控制
