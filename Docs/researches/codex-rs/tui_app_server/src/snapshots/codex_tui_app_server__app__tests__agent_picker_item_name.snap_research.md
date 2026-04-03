# Agent Picker Item Name Display - Technical Research Document

## Snapshot File
`codex_tui_app_server__app__tests__agent_picker_item_name.snap`

## Snapshot Content
```
Main [default] | 00000000-0000-0000-0000-000000000123
Robie [explorer] | 00000000-0000-0000-0000-000000000123
Robie | 00000000-0000-0000-0000-000000000123
[explorer] | 00000000-0000-0000-0000-000000000123
Agent | 00000000-0000-0000-0000-000000000123
```

---

## 1. 场景与职责 (Scenario & Responsibilities)

### 1.1 功能场景
此快照测试验证多代理(Multi-Agent)系统中代理选择器(Agent Picker)的显示名称格式化逻辑。当用户在TUI中使用 `/agent` 命令或通过快捷键切换代理时，系统需要以一致且可读的方式展示每个代理的标识信息。

### 1.2 业务职责
- **代理标识显示**: 为每个代理线程生成人类可读的显示名称
- **主次代理区分**: 主代理(Primary Agent)显示为 "Main [default]"，区别于其他协作代理
- **元数据展示**: 组合显示代理昵称(nickname)、角色(role)和线程ID(thread_id)
- **回退机制**: 当缺少昵称和角色时，提供默认显示 "Agent"

### 1.3 使用场景
1. `/agent` 命令打开代理选择器弹窗
2. 底部状态栏显示当前活跃代理
3. 历史记录中标识哪个代理产生了某条消息
4. 会话恢复时显示代理列表

---

## 2. 功能点目的 (Feature Purpose)

### 2.1 核心功能
| 显示格式 | 条件 | 示例 |
|---------|------|------|
| `Main [default]` | 主代理(is_primary=true) | 主会话代理 |
| `{nickname} [{role}]` | 有昵称和角色 | `Robie [explorer]` |
| `{nickname}` | 仅有昵称 | `Robie` |
| `[{role}]` | 仅有角色 | `[explorer]` |
| `Agent` | 无昵称和角色 | `Agent` |

### 2.2 设计目的
1. **信息层次**: 优先显示用户定义的昵称，其次是系统角色，最后是默认标识
2. **视觉区分**: 主代理使用固定标签 "[default]"，便于用户识别主会话
3. **一致性**: 统一的格式化规则确保UI各处显示一致
4. **可搜索性**: 生成的名称用于代理选择器的搜索功能

---

## 3. 具体技术实现 (Technical Implementation)

### 3.1 核心函数
```rust
// multi_agents.rs
pub(crate) fn format_agent_picker_item_name(
    agent_nickname: Option<&str>,
    agent_role: Option<&str>,
    is_primary: bool,
) -> String {
    if is_primary {
        return "Main [default]".to_string();
    }

    let agent_nickname = agent_nickname
        .map(str::trim)
        .filter(|nickname| !nickname.is_empty());
    let agent_role = agent_role.map(str::trim).filter(|role| !role.is_empty());
    match (agent_nickname, agent_role) {
        (Some(agent_nickname), Some(agent_role)) => format!("{agent_nickname} [{agent_role}]"),
        (Some(agent_nickname), None) => agent_nickname.to_string(),
        (None, Some(agent_role)) => format!("[{agent_role}]"),
        (None, None) => "Agent".to_string(),
    }
}
```

### 3.2 测试用例分析
测试函数 `agent_picker_item_name_snapshot()` 验证了5种组合场景：

```rust
// app.rs - test module
fn agent_picker_item_name_snapshot() {
    let thread_id = ThreadId::from_string("00000000-0000-0000-0000-000000000123").expect("valid thread id");
    let snapshot = [
        // 1. 主代理(Primary) - 忽略传入的昵称和角色
        format!("{} | {}", format_agent_picker_item_name(Some("Robie"), Some("explorer"), true), thread_id),
        // 2. 非主代理，有昵称和角色
        format!("{} | {}", format_agent_picker_item_name(Some("Robie"), Some("explorer"), false), thread_id),
        // 3. 非主代理，仅有昵称
        format!("{} | {}", format_agent_picker_item_name(Some("Robie"), None, false), thread_id),
        // 4. 非主代理，仅有角色
        format!("{} | {}", format_agent_picker_item_name(None, Some("explorer"), false), thread_id),
        // 5. 非主代理，无昵称和角色
        format!("{} | {}", format_agent_picker_item_name(None, None, false), thread_id),
    ]
    .join("\n");
    assert_snapshot!("agent_picker_item_name", snapshot);
}
```

### 3.3 数据流
1. **输入**: `AgentPickerThreadEntry` 结构体包含 `agent_nickname`, `agent_role`, `is_primary`
2. **处理**: `format_agent_picker_item_name()` 根据优先级规则生成显示字符串
3. **输出**: 格式化后的名称与线程ID组合显示

---

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 4.1 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/multi_agents.rs` | 核心格式化函数实现 |
| `codex-rs/tui_app_server/src/app.rs` | 测试用例、代理选择器集成 |
| `codex-rs/tui_app_server/src/app/agent_navigation.rs` | 代理导航状态管理 |

### 4.2 调用链
```
App::build_agent_picker_items()
  └── format_agent_picker_item_name()
      └── SelectionItem { name, description: thread_id }

AgentNavigationState::footer_label()
  └── format_agent_picker_item_name()
      └── 底部状态栏显示
```

### 4.3 关键代码位置
```rust
// app.rs:1596-1607
let label = format_agent_picker_item_name(
    entry.agent_nickname.as_deref(),
    entry.agent_role.as_deref(),
    is_primary,
);
if label == "Agent" {
    // 当使用默认标识时，追加线程ID前8位以区分
    let thread_id = thread_id.to_string();
    let short_id: String = thread_id.chars().take(8).collect();
    format!("{label} ({short_id})")
} else {
    label
}
```

---

## 5. 依赖与外部交互 (Dependencies & External Interactions)

### 5.1 内部依赖
| 模块 | 依赖内容 |
|------|---------|
| `codex_protocol::ThreadId` | 线程唯一标识 |
| `crate::bottom_pane::SelectionItem` | 选择器UI组件 |
| `crate::history_cell::PlainHistoryCell` | 历史记录渲染 |

### 5.2 数据结构
```rust
// multi_agents.rs
pub(crate) struct AgentPickerThreadEntry {
    pub(crate) agent_nickname: Option<String>,
    pub(crate) agent_role: Option<String>,
    pub(crate) is_closed: bool,
}
```

### 5.3 协议交互
- 从 `CollabAgentSpawnEndEvent` 接收代理创建事件
- 从 `CollabAgentStatusEntry` 获取代理状态更新
- 通过 `AppEvent::SelectAgentThread` 处理代理切换

---

## 6. 风险、边界与改进建议 (Risks, Edge Cases & Improvements)

### 6.1 已知风险
| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| 重复标识 | 当多个代理无昵称/角色时，都显示 "Agent" | 追加线程ID前8位区分 |
| 空字符串 | 昵称/角色可能是空字符串或仅空白字符 | `trim()` 和 `filter()` 处理 |
| 超长名称 | 用户定义的昵称可能过长 | 调用处使用 `truncate_text()` 截断 |

### 6.2 边界情况
1. **主代理强制标识**: 即使主代理有自定义昵称，也强制显示 "Main [default]"
2. **大小写敏感**: 昵称和角色保留原始大小写
3. **特殊字符**: 方括号 `[]` 作为角色标识符，与用户昵称中的方括号可能冲突

### 6.3 改进建议
1. **国际化(i18n)**: 当前硬编码英文，建议支持本地化
   ```rust
   // 建议: 使用本地化字符串
   t!("agent.primary_label") // "Main [default]"
   ```

2. **自定义主代理标签**: 允许用户自定义主代理显示名称
   ```rust
   format_agent_picker_item_name(nickname, role, is_primary, primary_label_override)
   ```

3. **颜色编码**: 在TUI中为不同角色使用不同颜色
   ```rust
   agent_role.map(|r| r.color(role_color_map.get(r)))
   ```

4. **字符限制**: 增加最大长度限制，防止UI溢出
   ```rust
   const MAX_NICKNAME_LEN: usize = 32;
   ```

### 6.4 测试覆盖
当前测试覆盖：
- ✅ 5种参数组合
- ✅ 主代理优先级
- ✅ 空值处理

建议增加：
- 超长昵称截断
- Unicode字符处理
- 特殊字符转义

---

## 7. 相关文档链接

- [AGENTS.md](../../../../../../AGENTS.md) - 项目级代理开发指南
- [TUI Style Conventions](../../../../../../AGENTS.md#tui-style-conventions)
- [Snapshot Testing](../../../../../../AGENTS.md#snapshot-tests)
