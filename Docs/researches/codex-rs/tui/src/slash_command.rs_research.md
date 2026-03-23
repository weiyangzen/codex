# slash_command.rs 研究文档

## 场景与职责

`slash_command.rs` 是 Codex TUI 的斜杠命令定义模块，负责定义所有内置的 `/` 命令及其元数据。该模块是 TUI 命令系统的核心，提供了命令枚举、描述、可用性控制等功能。

斜杠命令是用户与 Codex 交互的重要方式，用户可以通过输入 `/` 开头的命令来执行各种操作，如切换模型、管理权限、查看状态等。

## 功能点目的

### 1. 命令枚举定义
- 使用 `strum` 宏定义所有内置命令
- 支持 kebab-case 序列化（如 `setup-default-sandbox`）
- 支持自定义序列化名称（如 `clean` 映射到 `Stop`）

### 2. 命令元数据
- 每个命令提供用户可见的描述
- 支持内联参数（如 `/review <query>`）
- 区分任务期间可用性

### 3. 可见性控制
- 平台特定命令（如 Windows 沙盒命令）
- 调试命令（仅在 debug 构建显示）
- 功能开关控制

### 4. 命令遍历
- 支持迭代所有命令
- 支持从字符串解析命令
- 支持命令名到枚举的转换

## 具体技术实现

### 命令枚举定义

```rust
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, Hash, 
    EnumString, EnumIter, AsRefStr, IntoStaticStr
)]
#[strum(serialize_all = "kebab-case")]
pub enum SlashCommand {
    // 注意：枚举顺序即弹窗中的展示顺序，常用命令放前面
    Model,
    Fast,
    Approvals,
    Permissions,
    #[strum(serialize = "setup-default-sandbox")]
    ElevateSandbox,
    #[strum(serialize = "sandbox-add-read-dir")]
    SandboxReadRoot,
    Experimental,
    Skills,
    Review,
    Rename,
    New,
    Resume,
    Fork,
    Init,
    Compact,
    Plan,
    Collab,
    Agent,
    // Undo,  // 已注释掉的命令
    Diff,
    Copy,
    Mention,
    Status,
    DebugConfig,
    Statusline,
    Theme,
    Mcp,
    Apps,
    Logout,
    Quit,
    Exit,
    Feedback,
    Rollout,
    Ps,
    #[strum(to_string = "stop", serialize = "clean")]
    Stop,  // 显示为 "stop"，但序列化为 "clean"
    Clear,
    Personality,
    Realtime,
    Settings,
    TestApproval,
    #[strum(serialize = "subagents")]
    MultiAgents,
    // 调试命令
    #[strum(serialize = "debug-m-drop")]
    MemoryDrop,
    #[strum(serialize = "debug-m-update")]
    MemoryUpdate,
}
```

### 命令描述

```rust
impl SlashCommand {
    pub fn description(self) -> &'static str {
        match self {
            SlashCommand::Feedback => "send logs to maintainers",
            SlashCommand::New => "start a new chat during a conversation",
            SlashCommand::Init => "create an AGENTS.md file with instructions for Codex",
            SlashCommand::Compact => "summarize conversation to prevent hitting the context limit",
            SlashCommand::Review => "review my current changes and find issues",
            SlashCommand::Rename => "rename the current thread",
            SlashCommand::Resume => "resume a saved chat",
            SlashCommand::Clear => "clear the terminal and start a new chat",
            SlashCommand::Fork => "fork the current chat",
            SlashCommand::Quit | SlashCommand::Exit => "exit Codex",
            SlashCommand::Diff => "show git diff (including untracked files)",
            SlashCommand::Copy => "copy the latest Codex output to your clipboard",
            SlashCommand::Mention => "mention a file",
            SlashCommand::Skills => "use skills to improve how Codex performs specific tasks",
            SlashCommand::Status => "show current session configuration and token usage",
            // ... 更多命令
        }
    }
}
```

### 内联参数支持

```rust
pub fn supports_inline_args(self) -> bool {
    matches!(
        self,
        SlashCommand::Review
            | SlashCommand::Rename
            | SlashCommand::Plan
            | SlashCommand::Fast
            | SlashCommand::SandboxReadRoot
    )
}
```

支持内联参数的命令示例：
- `/review check for memory leaks`
- `/rename My New Thread Name`
- `/plan implement user authentication`

### 任务期间可用性

```rust
pub fn available_during_task(self) -> bool {
    match self {
        // 任务期间不可用的命令
        SlashCommand::New
        | SlashCommand::Resume
        | SlashCommand::Fork
        | SlashCommand::Init
        | SlashCommand::Compact
        | SlashCommand::Model
        | SlashCommand::Fast
        // ... 更多
        => false,
        
        // 任务期间可用的命令
        SlashCommand::Diff
        | SlashCommand::Copy
        | SlashCommand::Rename
        | SlashCommand::Mention
        | SlashCommand::Skills
        | SlashCommand::Status
        // ... 更多
        => true,
    }
}
```

### 可见性控制

```rust
fn is_visible(self) -> bool {
    match self {
        // Windows 平台特定命令
        SlashCommand::SandboxReadRoot => cfg!(target_os = "windows"),
        
        // Android 平台隐藏命令
        SlashCommand::Copy => !cfg!(target_os = "android"),
        
        // 仅在 debug 构建显示
        SlashCommand::Rollout | SlashCommand::TestApproval => cfg!(debug_assertions),
        
        _ => true,
    }
}
```

### 命令遍历

```rust
pub fn built_in_slash_commands() -> Vec<(&'static str, SlashCommand)> {
    SlashCommand::iter()
        .filter(|command| command.is_visible())
        .map(|c| (c.command(), c))
        .collect()
}
```

## 关键代码路径与文件引用

### 本文件关键函数/方法

| 方法 | 行号 | 职责 |
|------|------|------|
| `description` | 69 | 获取命令描述 |
| `command` | 119 | 获取命令字符串（无 `/`） |
| `supports_inline_args` | 124 | 检查是否支持内联参数 |
| `available_during_task` | 136 | 检查任务期间是否可用 |
| `is_visible` | 183 | 检查命令是否可见 |
| `built_in_slash_commands` | 194 | 获取所有可见命令列表 |

### 依赖模块

| 模块 | 来源 | 用途 |
|------|------|------|
| `strum` | 外部 crate | 枚举宏（EnumString, EnumIter 等） |
| `strum_macros` | 外部 crate | 派生宏 |

### 调用方

| 文件 | 用途 |
|------|------|
| `bottom_pane/slash_commands.rs` | 命令过滤和匹配 |
| `bottom_pane/command_popup.rs` | 命令弹窗展示 |
| `bottom_pane/chat_composer.rs` | 命令解析和执行 |
| `chatwidget.rs` | 命令处理 |

## 依赖与外部交互

### strum 宏功能

| 宏 | 功能 |
|----|------|
| `EnumString` | 支持从字符串解析枚举 |
| `EnumIter` | 支持迭代所有枚举值 |
| `AsRefStr` | 支持转换为 `&str` |
| `IntoStaticStr` | 支持转换为 `&'static str` |
| `strum(serialize_all = "kebab-case")` | 自动 kebab-case 序列化 |
| `strum(serialize = "...")` | 自定义序列化名称 |
| `strum(to_string = "...")` | 自定义 `to_string()` 输出 |

### 命令分类

| 类别 | 命令 |
|------|------|
| **会话管理** | New, Resume, Fork, Clear, Quit, Exit |
| **模型配置** | Model, Fast, Personality, Plan, Collab |
| **权限控制** | Approvals, Permissions, ElevateSandbox, SandboxReadRoot |
| **代码操作** | Diff, Copy, Mention, Review |
| **状态查看** | Status, DebugConfig, Ps, Rollout |
| **技能系统** | Skills |
| **工具集成** | Mcp, Apps |
| **界面控制** | Theme, Statusline, Settings |
| **调试** | MemoryDrop, MemoryUpdate, TestApproval |

## 风险、边界与改进建议

### 风险分析

1. **枚举顺序敏感**
   - 注释明确说明枚举顺序即弹窗展示顺序
   - 新命令添加到错误位置可能影响用户体验

2. **硬编码描述**
   - 所有描述都是硬编码的英文
   - 不支持国际化（i18n）

3. **可见性逻辑分散**
   - `is_visible()` 包含平台、构建类型判断
   - 功能开关控制在 `slash_commands.rs` 中
   - 逻辑分散在多个文件

4. **命令别名限制**
   - 仅 `Stop` 命令支持别名（`clean`）
   - 不支持用户自定义别名

### 边界情况处理

| 场景 | 处理方式 |
|------|----------|
| 未知命令 | 由调用方处理（通常显示错误） |
| 命令在任务期间不可用 | UI 层禁用或提示 |
| 平台不支持命令 | 命令不显示在列表中 |
| 大小写敏感 | `EnumString` 默认大小写敏感 |

### 改进建议

1. **国际化支持**
   - 将描述提取到资源文件
   - 支持多语言切换

2. **动态命令**
   - 支持插件注册自定义命令
   - 支持用户自定义别名

3. **配置化**
   - 将功能开关移到配置系统
   - 支持运行时切换命令可见性

4. **命令分组**
   - 在弹窗中按类别分组显示
   - 添加类别标题和分隔

5. **搜索增强**
   - 支持按描述搜索命令
   - 支持关键词标签

6. **文档生成**
   - 从代码自动生成命令文档
   - 保持代码和文档同步

7. **测试覆盖**
   - 当前仅有基础解析测试
   - 建议添加：
     - 可见性测试（各平台、构建类型）
     - 可用性状态测试
     - 描述完整性测试

### 与其他模块的关系

```
slash_command.rs (命令定义)
    ↑ 被使用
bottom_pane/slash_commands.rs (命令过滤)
bottom_pane/command_popup.rs (命令弹窗)
bottom_pane/chat_composer.rs (命令执行)
chatwidget.rs (命令处理)
    ↑ 发送事件
AppEvent (应用事件)
    ↑ 处理
app.rs (应用逻辑)
```

该模块是命令系统的数据层，定义了"有哪些命令"，而具体的"如何展示"和"如何执行"由其他模块负责。这种分层设计使得命令定义与业务逻辑解耦，便于维护和扩展。
