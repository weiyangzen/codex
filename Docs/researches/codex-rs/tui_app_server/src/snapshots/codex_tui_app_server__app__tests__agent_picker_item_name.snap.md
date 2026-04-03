# AgentPicker - Agent 选择器项名称格式化测试

## 场景与职责

该快照测试验证了 `format_agent_picker_item_name` 函数的各种输入组合下的输出格式。在多 Agent 协作场景中，每个 Agent（线程）需要一个可读的标识名称，用于在 Agent 选择器、页脚标签和历史记录中显示。该函数负责根据 Agent 的昵称、角色和主线程状态生成格式化的显示名称。

**典型使用场景：**
- `/agent` 命令显示 Agent 选择器列表
- 页脚显示当前激活的 Agent 标签
- 多 Agent 历史记录中标识消息来源
- Agent 导航快捷键显示目标 Agent 名称

## 功能点目的

### 核心功能
1. **主线程特殊标识**：主线程显示为 "Main [default]"
2. **昵称优先显示**：优先使用用户友好的昵称
3. **角色标注**：在方括号中显示 Agent 角色类型
4. **回退机制**：无昵称无角色时显示 "Agent"

### 渲染输出分析
根据快照内容：
```
Main [default] | 00000000-0000-0000-0000-000000000123
Robie [explorer] | 00000000-0000-0000-0000-000000000123
Robie | 00000000-0000-0000-0000-000000000123
[explorer] | 00000000-0000-0000-0000-000000000123
Agent | 00000000-0000-0000-0000-000000000123
```

**格式规则分析：**

| 昵称 | 角色 | 主线程 | 输出 |
|-----|------|-------|------|
| - | - | 是 | `Main [default]` |
| Robie | explorer | 是 | `Main [default]`（主线程优先） |
| Robie | explorer | 否 | `Robie [explorer]` |
| Robie | - | 否 | `Robie` |
| - | explorer | 否 | `[explorer]` |
| - | - | 否 | `Agent` |

## 具体技术实现

### 核心函数

```rust
pub(crate) fn format_agent_picker_item_name(
    agent_nickname: Option<&str>,
    agent_role: Option<&str>,
    is_primary: bool,
) -> String {
    // 主线程特殊处理
    if is_primary {
        return "Main [default]".to_string();
    }

    // 清理输入（去除空白）
    let agent_nickname = agent_nickname
        .map(str::trim)
        .filter(|nickname| !nickname.is_empty());
    let agent_role = agent_role.map(str::trim).filter(|role| !role.is_empty());
    
    // 根据可用信息组合输出
    match (agent_nickname, agent_role) {
        (Some(agent_nickname), Some(agent_role)) => {
            format!("{agent_nickname} [{agent_role}]")
        }
        (Some(agent_nickname), None) => agent_nickname.to_string(),
        (None, Some(agent_role)) => format!("[{agent_role}]"),
        (None, None) => "Agent".to_string(),
    }
}
```

### 调用上下文

```rust
// 在 app.rs 中的 thread_label 方法
fn thread_label(&self, thread_id: ThreadId) -> String {
    let is_primary = self.primary_thread_id == Some(thread_id);
    
    if let Some(entry) = self.agent_navigation.get(&thread_id) {
        let label = format_agent_picker_item_name(
            entry.agent_nickname.as_deref(),
            entry.agent_role.as_deref(),
            is_primary,
        );
        // 对于默认 "Agent" 标签，添加短 ID 区分
        if label == "Agent" {
            let thread_id = thread_id.to_string();
            let short_id: String = thread_id.chars().take(8).collect();
            format!("{label} ({short_id})")
        } else {
            label
        }
    } else {
        // 回退标签
        if is_primary {
            "Main [default]".to_string()
        } else {
            let thread_id = thread_id.to_string();
            let short_id: String = thread_id.chars().take(8).collect();
            format!("Agent ({short_id})")
        }
    }
}
```

### 数据结构

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct AgentPickerThreadEntry {
    /// 在选择器行和页脚标签中显示的人类友好昵称
    pub(crate) agent_nickname: Option<String>,
    /// Agent 类型，显示在方括号中，例如 `worker`
    pub(crate) agent_role: Option<String>,
    /// 线程是否已发出关闭事件，应显示为暗淡
    pub(crate) is_closed: bool,
}
```

### 测试实现

```rust
#[test]
fn agent_picker_item_name_snapshot() {
    let thread_id =
        ThreadId::from_string("00000000-0000-0000-0000-000000000123").expect("valid thread id");
    let snapshot = [
        format!(
            "{} | {}",
            format_agent_picker_item_name(Some("Robie"), Some("explorer"), true),
            thread_id
        ),
        format!(
            "{} | {}",
            format_agent_picker_item_name(Some("Robie"), Some("explorer"), false),
            thread_id
        ),
        format!(
            "{} | {}",
            format_agent_picker_item_name(Some("Robie"), None, false),
            thread_id
        ),
        format!(
            "{} | {}",
            format_agent_picker_item_name(None, Some("explorer"), false),
            thread_id
        ),
        format!(
            "{} | {}",
            format_agent_picker_item_name(None, None, false),
            thread_id
        ),
    ]
    .join("\n");
    assert_snapshot!("agent_picker_item_name", snapshot);
}
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui_app_server/src/multi_agents.rs` | `format_agent_picker_item_name()` 实现 |
| `codex-rs/tui_app_server/src/app.rs` | `thread_label()` 方法和测试用例 |
| `codex-rs/tui_app_server/src/agent_navigation.rs` | Agent 导航状态管理 |

### 相关函数

```rust
// multi_agents.rs
pub(crate) fn agent_picker_status_dot_spans(is_closed: bool) -> Vec<Span<'static>>;
pub(crate) fn format_agent_picker_item_name(...);
pub(crate) fn previous_agent_shortcut() -> crate::key_hint::KeyBinding;
pub(crate) fn next_agent_shortcut() -> crate::key_hint::KeyBinding;
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `codex_protocol::ThreadId` | 线程唯一标识 |
| `ratatui` | 样式和渲染类型 |

### 协议集成

Agent 信息来自 `codex_app_server_protocol`：

```rust
// 来自 ServerNotification::TurnStarted 等事件
pub struct Turn {
    pub agent_nickname: Option<String>,
    pub agent_role: Option<String>,
    // ...
}
```

## 风险、边界与改进建议

### 潜在风险

1. **空字符串处理**：
   - 使用 `filter(|s| !s.is_empty())` 过滤空字符串
   - 风险：仅包含空格的字符串被视为有效
   - 当前实现：`trim()` 后检查，处理得当

2. **特殊字符**：
   - 昵称或角色中可能包含特殊字符（如 `]`）
   - 可能影响方括号格式的解析
   - 建议：添加字符转义或验证

3. **长度限制**：
   - 无长度限制，过长名称可能影响 UI 布局
   - 建议：添加截断或最大长度限制

### 边界情况

1. **主线程优先级**：
   - `is_primary=true` 时直接返回 "Main [default]"
   - 忽略传入的昵称和角色参数
   - 确保主线程标识的一致性

2. **默认 Agent 标签**：
   - 当输出为 "Agent" 时，调用方（`thread_label`）会添加短 ID
   - 避免多个无昵称 Agent 无法区分

3. **线程 ID 显示**：
   - 使用 UUID 前 8 位作为短 ID
   - 冲突概率低但存在

### 改进建议

1. **格式化配置**：
   - 当前格式为硬编码
   - 建议：添加配置选项自定义格式模板
   - 例如：`"{nickname} ({role})"` 或 `"[{role}] {nickname}"`

2. **颜色编码**：
   - 当前返回纯字符串
   - 建议：返回带样式的 `Vec<Span>`
   - 不同角色使用不同颜色区分

3. **国际化**：
   - "Main"、"default"、"Agent" 为硬编码英文
   - 建议：添加本地化支持

4. **唯一性保证**：
   - 当前依赖短 ID 区分
   - 建议：在昵称冲突时自动添加序号
   - 例如：`"Robie (1)"`、`"Robie (2)"`

5. **角色本地化**：
   - 角色标识符（如 "explorer"、"worker"）为技术术语
   - 建议：提供用户友好的角色显示名称

### 相关测试

- `agent_picker_item_name_snapshot`：格式组合测试
- `collab_events_snapshot`：协作事件渲染测试
- `title_styles_nickname_and_role`：样式验证测试

### 样式约定

根据项目 `styles.md`：
- 主线程：特殊标识，不使用颜色
- Agent 昵称：`.cyan().bold()`
- Agent 角色：`[]` 包围，无特殊颜色
- 状态点：绿色表示活跃，默认色表示关闭
