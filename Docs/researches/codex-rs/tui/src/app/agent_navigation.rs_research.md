# agent_navigation.rs 深度研究文档

## 场景与职责

`agent_navigation.rs` 是 Codex TUI（终端用户界面）中负责**多智能体（Multi-Agent）导航状态管理**的专用模块。它从主 `App` 结构中分离出来，专门处理以下场景：

1. **多智能体会话管理**：当用户同时与多个 AI Agent（主线程 + 子 Agent）交互时，需要在不同线程间快速切换
2. **Agent 选择器（/agent picker）**：提供 `/agent` 命令的列表展示，让用户选择要查看的 Agent 线程
3. **键盘快捷键导航**：支持 `Alt+Left`/`Alt+Right` 在 Agent 间快速切换
4. **上下文页脚标签**：在底部状态栏显示当前正在查看的 Agent 名称

**核心设计原则**：
- 保持纯逻辑，不涉及 UI 副作用
- 维护稳定的遍历顺序（按首次发现顺序，而非线程 ID 排序）
- 与 `App` 的职责分离：`App` 负责线程生命周期和 UI 状态变更，本模块负责导航规则

## 功能点目的

### 1. AgentNavigationState - 导航状态容器

```rust
#[derive(Debug, Default)]
pub(crate) struct AgentNavigationState {
    /// 每个被跟踪线程的最新选择器元数据
    threads: HashMap<ThreadId, AgentPickerThreadEntry>,
    /// 稳定的首见遍历顺序（用于选择器行和键盘循环）
    order: Vec<ThreadId>,
}
```

**设计意图**：
- `threads` 存储最新的 Agent 元数据（昵称、角色、关闭状态）
- `order` 保持首次发现顺序，确保导航稳定性（即使元数据更新也不改变位置）

### 2. AgentPickerThreadEntry - Agent 元数据

定义在 `multi_agents.rs`（被本模块使用）：
```rust
pub(crate) struct AgentPickerThreadEntry {
    pub(crate) agent_nickname: Option<String>,  // 人类友好的昵称
    pub(crate) agent_role: Option<String>,      // Agent 类型，如 "worker"
    pub(crate) is_closed: bool,                 // 线程是否已关闭
}
```

### 3. AgentNavigationDirection - 导航方向

```rust
pub(crate) enum AgentNavigationDirection {
    Previous,  // 向 spawn 顺序中更早的条目移动，在前端环绕
    Next,      // 向 spawn 顺序中更晚的条目移动，在末端环绕
}
```

### 4. 核心方法

| 方法 | 用途 |
|------|------|
| `upsert()` | 插入或更新 Agent 信息，首次插入时记录顺序 |
| `mark_closed()` | 标记线程为关闭状态（不从选择器中移除） |
| `adjacent_thread_id()` | 获取当前线程的相邻线程 ID（用于键盘导航） |
| `active_agent_label()` | 生成当前线程的页脚标签文本 |
| `picker_subtitle()` | 生成 `/agent` 选择器的副标题（含快捷键提示） |
| `ordered_threads()` | 按稳定顺序返回所有线程条目 |

## 具体技术实现

### 1. 首次发现顺序维护

```rust
pub(crate) fn upsert(
    &mut self,
    thread_id: ThreadId,
    agent_nickname: Option<String>,
    agent_role: Option<String>,
    is_closed: bool,
) {
    // 关键：只在首次看到时追加到 order
    if !self.threads.contains_key(&thread_id) {
        self.order.push(thread_id);
    }
    self.threads.insert(thread_id, AgentPickerThreadEntry { ... });
}
```

**关键不变式**：`order` 只记录首次发现的线程 ID，后续更新不改变位置。

### 2. 环绕式导航算法

```rust
pub(crate) fn adjacent_thread_id(
    &self,
    current_displayed_thread_id: Option<ThreadId>,
    direction: AgentNavigationDirection,
) -> Option<ThreadId> {
    let ordered_threads = self.ordered_threads();
    if ordered_threads.len() < 2 {
        return None;
    }

    let current_thread_id = current_displayed_thread_id?;
    let current_idx = ordered_threads.iter().position(|(thread_id, _)| *thread_id == current_thread_id)?;
    
    let next_idx = match direction {
        AgentNavigationDirection::Next => (current_idx + 1) % ordered_threads.len(),
        AgentNavigationDirection::Previous => {
            if current_idx == 0 {
                ordered_threads.len() - 1
            } else {
                current_idx - 1
            }
        }
    };
    Some(ordered_threads[next_idx].0)
}
```

### 3. 标签格式化

与 `multi_agents.rs` 中的 `format_agent_picker_item_name` 函数配合：

```rust
// 主线程特殊显示
if is_primary {
    return "Main [default]".to_string();
}

// 组合昵称和角色
match (agent_nickname, agent_role) {
    (Some(nickname), Some(role)) => format!("{nickname} [{role}]"),
    (Some(nickname), None) => nickname.to_string(),
    (None, Some(role)) => format!("[{role}]"),
    (None, None) => "Agent".to_string(),
}
```

### 4. 快捷键绑定

```rust
// multi_agents.rs
pub(crate) fn previous_agent_shortcut() -> crate::key_hint::KeyBinding {
    crate::key_hint::alt(KeyCode::Left)  // Alt + ←
}

pub(crate) fn next_agent_shortcut() -> crate::key_hint::KeyBinding {
    crate::key_hint::alt(KeyCode::Right) // Alt + →
}
```

**macOS 回退支持**：某些终端不支持增强键盘报告，提供 `Option+b`/`Option+f` 作为备选。

## 关键代码路径与文件引用

### 本模块关键代码

| 行号 | 代码 | 说明 |
|------|------|------|
| 38-44 | `AgentNavigationState` 结构体 | 核心状态容器 |
| 47-53 | `AgentNavigationDirection` 枚举 | 导航方向定义 |
| 79-97 | `upsert()` 方法 | 插入/更新线程元数据 |
| 105-114 | `mark_closed()` 方法 | 标记线程关闭 |
| 154-179 | `adjacent_thread_id()` 方法 | 相邻线程计算 |
| 187-214 | `active_agent_label()` 方法 | 页脚标签生成 |
| 220-227 | `picker_subtitle()` 方法 | 选择器副标题 |

### 调用方（App.rs 中的使用）

```rust
// app.rs:760 - App 结构体字段
agent_navigation: AgentNavigationState,

// app.rs:1722-1731 - 更新 Agent 选择器线程
fn upsert_agent_picker_thread(...) {
    self.agent_navigation.upsert(thread_id, agent_nickname, agent_role, is_closed);
    self.sync_active_agent_label();
}

// app.rs:1738-1741 - 标记线程关闭
fn mark_agent_picker_thread_closed(&mut self, thread_id: ThreadId) {
    self.agent_navigation.mark_closed(thread_id);
    self.sync_active_agent_label();
}

// app.rs:1404-1409 - 同步页脚标签
fn sync_active_agent_label(&mut self) {
    let label = self.agent_navigation.active_agent_label(
        self.current_displayed_thread_id(), 
        self.primary_thread_id
    );
    self.chat_widget.set_active_agent_label(label);
}
```

### 依赖模块

| 文件 | 用途 |
|------|------|
| `multi_agents.rs` | `AgentPickerThreadEntry`、`format_agent_picker_item_name`、快捷键定义 |
| `key_hint.rs` | `KeyBinding` 结构体和快捷键构造 |
| `codex_protocol::ThreadId` | 线程 ID 类型 |
| `ratatui::text::Span` | UI 文本渲染 |

## 依赖与外部交互

### 上游依赖（被调用）

1. **multi_agents.rs**
   - `AgentPickerThreadEntry`：元数据结构
   - `format_agent_picker_item_name()`：格式化显示名称
   - `previous_agent_shortcut()` / `next_agent_shortcut()`：快捷键绑定
   - `agent_picker_status_dot_spans()`：状态点渲染

2. **key_hint.rs**
   - `alt(KeyCode)`：构造 Alt 快捷键
   - `KeyBinding::is_press()`：匹配按键事件

3. **codex_protocol**
   - `ThreadId`：线程标识符类型

### 下游调用方

1. **app.rs**
   - 初始化：`agent_navigation: AgentNavigationState::default()`
   - 线程切换时调用 `upsert()` 和 `sync_active_agent_label()`
   - `/agent` 选择器使用 `ordered_threads()` 和 `picker_subtitle()`
   - 键盘导航使用 `adjacent_thread_id()`

## 风险、边界与改进建议

### 潜在风险

1. **顺序漂移风险**
   - 风险：如果 `order` 和 `threads` 不同步，导航会出现跳跃
   - 缓解：所有修改通过 `upsert()`/`mark_closed()`/`clear()` 集中处理

2. **关闭线程的显示**
   - 当前：关闭线程仍保留在选择器中（灰显）
   - 风险：长期运行会话可能积累大量已关闭线程
   - 建议：考虑添加清理机制或折叠显示

3. **线程 ID 查找失败**
   - `get()` 返回 `Option`，调用方需处理缺失情况
   - `adjacent_thread_id()` 中 `ordered_threads()` 会过滤掉无元数据的线程

### 边界情况

1. **单线程会话**
   - `active_agent_label()` 在线程数 ≤1 时返回 `None`，避免浪费页脚空间

2. **空导航状态**
   - `is_empty()` 检查，用于显示 "No agents available yet."

3. **环绕导航**
   - 在第一个线程按 `Previous` 会跳到最后一个
   - 在最后一个线程按 `Next` 会跳到第一个

### 改进建议

1. **性能优化**
   - 当前 `ordered_threads()` 每次创建新 Vec
   - 建议：如果性能成为问题，可缓存有序列表

2. **功能增强**
   - 支持按昵称/角色搜索过滤
   - 支持手动重新排序（拖拽）
   - 支持批量关闭/清理已完成的 Agent

3. **可观测性**
   - 添加指标：当前跟踪的线程数、切换频率
   - 日志：记录导航操作便于调试

4. **测试覆盖**
   - 当前已有基础单元测试（行 242-331）
   - 建议：添加并发场景测试、边界条件测试

### 测试要点

```rust
// 现有测试覆盖
#[test]
fn upsert_preserves_first_seen_order() { ... }

#[test]
fn adjacent_thread_id_wraps_in_spawn_order() { ... }

#[test]
fn picker_subtitle_mentions_shortcuts() { ... }

#[test]
fn active_agent_label_tracks_current_thread() { ... }
```

测试使用 `pretty_assertions` 进行清晰断言，使用固定 UUID 确保可重复性。
