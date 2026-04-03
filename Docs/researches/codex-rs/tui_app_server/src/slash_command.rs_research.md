# SlashCommand 研究文档

## 场景与职责

`slash_command.rs` 定义了 Codex TUI 中所有以 `/` 开头的斜杠命令系统。这是用户与 Codex CLI 交互的核心命令接口，提供了一种统一、可发现的方式来执行各种操作，从简单的退出到复杂的模型切换、沙箱配置等。

该模块位于 `codex-rs/tui_app_server/src/slash_command.rs`，是 TUI 应用服务器的一部分，负责：
- 定义所有可用的斜杠命令枚举
- 提供命令的元数据（描述、可见性、可用性）
- 支持命令别名的解析
- 控制命令在特定状态下的可用性（如任务运行时）

## 功能点目的

### 1. 命令定义与枚举

`SlashCommand` 枚举使用 `strum` 宏派生，实现了多种字符串转换特性：

```rust
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, Hash, EnumString, EnumIter, AsRefStr, IntoStaticStr,
)]
#[strum(serialize_all = "kebab-case")]
pub enum SlashCommand {
    Model,
    Fast,
    Approvals,
    // ... 更多命令
}
```

**关键设计决策：**
- 使用 `kebab-case` 序列化（如 `setup-default-sandbox`）
- 显式指定 `#[strum(serialize = "...")]` 覆盖默认行为
- 支持命令别名（如 `Stop` 命令同时响应 `stop` 和 `clean`）

### 2. 命令描述系统

`description()` 方法为每个命令提供用户可见的描述，用于命令选择弹窗：

```rust
pub fn description(self) -> &'static str {
    match self {
        SlashCommand::Feedback => "send logs to maintainers",
        SlashCommand::New => "start a new chat during a conversation",
        // ...
    }
}
```

### 3. 命令可用性控制

`available_during_task()` 方法控制命令在任务运行时的可用性：

- **任务运行时不可用**：`New`, `Resume`, `Fork`, `Init`, `Compact`, `Model`, `Fast` 等会改变会话状态的命令
- **任务运行时可用**：`Diff`, `Copy`, `Status`, `Ps`, `Quit` 等查询或控制类命令

### 4. 内联参数支持

`supports_inline_args()` 标识哪些命令支持在行内传递参数：

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

### 5. 平台特定可见性

`is_visible()` 方法控制命令在不同平台的可见性：

```rust
fn is_visible(self) -> bool {
    match self {
        SlashCommand::SandboxReadRoot => cfg!(target_os = "windows"),
        SlashCommand::Copy => !cfg!(target_os = "android"),
        SlashCommand::Rollout | SlashCommand::TestApproval => cfg!(debug_assertions),
        _ => true,
    }
}
```

## 具体技术实现

### 数据结构

```rust
// 命令枚举 - 217行代码的核心
pub enum SlashCommand {
    Model,           // 选择模型和推理强度
    Fast,            // 切换快速模式
    Approvals,       // 审批设置
    Permissions,     // 权限设置（Approvals 的别名）
    ElevateSandbox,  // 提升沙箱权限
    SandboxReadRoot, // 添加沙箱读取目录（Windows 专用）
    Experimental,    // 实验性功能开关
    Skills,          // 技能管理
    Review,          // 审查当前更改
    Rename,          // 重命名线程
    New,             // 新建聊天
    Resume,          // 恢复已保存的聊天
    Fork,            // 分叉当前聊天
    Init,            // 创建 AGENTS.md
    Compact,         // 压缩对话
    Plan,            // 切换到计划模式
    Collab,          // 协作模式
    Agent,           // 切换活动代理线程
    MultiAgents,     // 子代理管理
    Diff,            // 显示 git diff
    Copy,            // 复制最新输出到剪贴板
    Mention,         // 提及文件
    Status,          // 显示会话配置和令牌使用
    DebugConfig,     // 调试配置层
    Statusline,      // 配置状态栏
    Theme,           // 选择语法高亮主题
    Mcp,             // 列出配置的 MCP 工具
    Apps,            // 管理应用
    Logout,          // 退出登录
    Rollout,         // 打印 rollout 文件路径（调试）
    Ps,              // 列出后台终端
    Stop,            // 停止所有后台终端（别名 clean）
    Clear,           // 清屏并新建聊天
    Personality,     // 选择沟通风格
    Realtime,        // 切换实时语音模式
    Settings,        // 配置实时麦克风/扬声器
    TestApproval,    // 测试审批请求（调试）
    MemoryDrop,      // 调试：丢弃内存
    MemoryUpdate,    // 调试：更新内存
}
```

### 关键流程

**命令解析流程：**
1. 用户输入以 `/` 开头的文本
2. 使用 `SlashCommand::from_str()` 解析命令名
3. 根据 `supports_inline_args()` 决定是否解析行内参数
4. 根据 `available_during_task()` 检查当前状态是否允许执行

**命令列表生成：**
```rust
pub fn built_in_slash_commands() -> Vec<(&'static str, SlashCommand)> {
    SlashCommand::iter()
        .filter(|command| command.is_visible())
        .map(|c| (c.command(), c))
        .collect()
}
```

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/slash_command.rs` (217 行)

### 调用方
- `bottom_pane/command_popup.rs` - 命令选择弹窗
- `bottom_pane/chat_composer.rs` - 输入解析
- `chatwidget.rs` - 命令执行路由

### 依赖
- `strum` 和 `strum_macros` - 枚举工具宏

### 测试
```rust
#[test]
fn stop_command_is_canonical_name() {
    assert_eq!(SlashCommand::Stop.command(), "stop");
}

#[test]
fn clean_alias_parses_to_stop_command() {
    assert_eq!(SlashCommand::from_str("clean"), Ok(SlashCommand::Stop));
}
```

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|------|------|
| `strum` | 枚举迭代和字符串转换 |
| `strum_macros` | 派生宏（EnumString, EnumIter 等） |

### 内部交互
- 被 `bottom_pane` 模块调用以构建命令选择 UI
- 被输入处理模块用于命令解析
- 被状态管理模块用于可用性检查

## 风险、边界与改进建议

### 潜在风险

1. **命令顺序敏感**：注释明确说明 "DO NOT ALPHA-SORT!"，枚举顺序决定弹窗中的展示顺序。新开发者可能误排序。

2. **平台特定命令可见性**：`SandboxReadRoot` 仅在 Windows 可见，这种隐式行为可能导致跨平台测试遗漏。

3. **调试命令暴露**：`MemoryDrop` 和 `MemoryUpdate` 标记为 "DO NOT USE"，但仍可通过 `/debug-m-drop` 和 `/debug-m-update` 访问。

### 边界情况

1. **命令别名解析**：`Stop` 命令有两个序列化名称（`stop` via `to_string`, `clean` via `serialize`），需要确保两者都能正确解析。

2. **大小写敏感**：命令解析是大小写敏感的，但用户可能期望不区分大小写。

### 改进建议

1. **添加命令分类**：将命令按功能分类（会话管理、配置、调试等），便于用户发现。

2. **动态命令注册**：考虑支持插件动态注册命令，而非硬编码所有命令。

3. **命令使用统计**：收集命令使用频率数据，优化默认展示顺序。

4. **增强测试覆盖**：添加更多边界测试，如无效命令名、特殊字符等。

5. **文档生成**：利用 `strum` 的迭代能力自动生成命令文档。
