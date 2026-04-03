# Agent Picker Item Name 研究文档

## 场景与职责

该组件负责在 Codex TUI 的多代理（multi-agent）协作场景中，为 `/agent` 选择器生成标准化的代理名称显示格式。当用户通过 `/agent` 命令切换不同的 AI 代理线程时，需要在选择器列表中清晰展示每个代理的标识信息，包括主代理（Primary Agent）和子代理（Sub-agents）。

## 功能点目的

`format_agent_picker_item_name` 函数的核心目的是统一代理名称的展示格式，支持以下显示模式：

1. **主代理标识**：主线程显示为 "Main [default]"
2. **带角色的代理名**：如 "Robie [explorer]" - 显示代理昵称和角色
3. **仅昵称**：如 "Robie" - 只有代理昵称
4. **仅角色**：如 "[explorer]" - 只有角色信息
5. **默认标识**：如 "Agent" - 无其他信息时的默认显示

每种格式后跟随代理的 UUID（如 `00000000-0000-0000-0000-000000000123`），用于唯一标识代理线程。

## 具体技术实现

### 核心函数
```rust
pub(crate) fn format_agent_picker_item_name(
    agent_nickname: Option<&str>,
    agent_role: Option<&str>,
    is_primary: bool,
) -> String
```

### 格式化逻辑流程

1. **主代理判断**：如果 `is_primary` 为 true，直接返回 "Main [default]"
2. **数据清理**：对 `agent_nickname` 和 `agent_role` 进行 trim 和空值过滤
3. **模式匹配**：根据 (nickname, role) 的组合情况返回不同格式：
   - `(Some(nickname), Some(role))` → `"{nickname} [{role}]"`
   - `(Some(nickname), None)` → `nickname.to_string()`
   - `(None, Some(role))` → `"[{role}]"`
   - `(None, None)` → `"Agent"`

### 数据结构

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct AgentPickerThreadEntry {
    /// 在选择器行和页脚标签中显示的人类友好昵称
    pub(crate) agent_nickname: Option<String>,
    /// 代理类型，如 `worker`，在括号中显示
    pub(crate) agent_role: Option<String>,
    /// 线程是否已关闭（发出关闭事件）
    pub(crate) is_closed: bool,
}
```

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/tui/src/multi_agents.rs` | 包含 `format_agent_picker_item_name` 函数实现（第 70-89 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/multi_agents.rs` | `AgentPickerThreadEntry` 结构体定义（第 38-46 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/app.rs` | 在 `open_agent_picker` 方法中调用格式化函数（第 1687-1691 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/app.rs` | `thread_label` 方法中用于生成线程标签（第 1371-1385 行） |

### 调用示例
```rust
let name = format_agent_picker_item_name(
    entry.agent_nickname.as_deref(),
    entry.agent_role.as_deref(),
    is_primary,
);
```

## 依赖与外部交互

### 依赖模块
- `codex_protocol::ThreadId` - 线程 ID 类型
- `ratatui::style::Stylize` - 终端样式处理
- `crate::history_cell::PlainHistoryCell` - 历史记录单元格渲染

### 与 App 模块的交互
- `App::open_agent_picker()` - 打开代理选择器时生成列表项
- `App::thread_label()` - 生成当前线程的标签显示
- `AgentNavigationState` - 管理代理导航状态

### 测试覆盖
- 快照测试验证不同组合下的输出格式
- 样式测试验证标题、昵称和角色的正确渲染

## 风险、边界与改进建议

### 边界情况

1. **空字符串处理**：函数会过滤掉仅包含空白字符的昵称或角色
2. **UUID 截断**：在 `thread_label` 中，当标签为 "Agent" 时会追加截断的 UUID 前 8 位
3. **主代理优先级**：`is_primary` 为 true 时忽略其他参数

### 潜在风险

1. **国际化支持**：当前格式为硬编码英文，不支持本地化
2. **长度限制**：长昵称或角色名可能导致选择器界面溢出
3. **特殊字符**：昵称或角色中包含 `]` 等特殊字符可能影响格式解析

### 改进建议

1. **本地化支持**：
   ```rust
   // 建议添加本地化支持
   fn format_agent_picker_item_name_i18n(
       agent_nickname: Option<&str>,
       agent_role: Option<&str>,
       is_primary: bool,
       locale: &str,
   ) -> String
   ```

2. **长度截断**：
   ```rust
   // 建议添加最大长度限制
   const MAX_NICKNAME_LEN: usize = 20;
   const MAX_ROLE_LEN: usize = 15;
   ```

3. **特殊字符转义**：
   ```rust
   // 建议对特殊字符进行转义处理
   fn escape_brackets(s: &str) -> String {
       s.replace('[', "\\[").replace(']', "\\]")
   }
   ```

4. **可配置格式**：允许用户自定义代理名称显示模板

### 相关测试
- `collab_events_snapshot` - 协作事件快照测试
- `title_styles_nickname_and_role` - 标题样式测试
- `agent_picker_status_dot_spans` - 状态点样式测试
