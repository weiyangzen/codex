# Research: codex_tui__app__tests__agent_picker_item_name.snap

## 场景与职责

本快照文件是 `codex-tui` crate 中 `app.rs` 的测试快照，用于验证 Agent 选择器（Agent Picker）中项目名称格式化功能的正确性。该功能用于在多代理协作场景中显示代理的标识名称。

## 功能点目的

`format_agent_picker_item_name` 函数负责根据代理的昵称（nickname）和角色（role）生成可读的显示名称。测试用例验证了以下场景的格式化输出：

1. **主代理（Main [default]）**：主线程/默认代理的特殊显示
2. **带角色和昵称的代理**：如 "Robie [explorer]"
3. **仅昵称的代理**：如 "Robie"
4. **仅角色的代理**：如 "[explorer]"
5. **无昵称无角色的默认代理**：显示为 "Agent"

## 具体技术实现

### 关键数据结构

```rust
// AgentPickerThreadEntry 结构体定义
pub(crate) struct AgentPickerThreadEntry {
    pub(crate) agent_nickname: Option<String>,
    pub(crate) agent_role: Option<String>,
    pub(crate) is_closed: bool,
}
```

### 格式化逻辑

```rust
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

### 格式化规则

| 昵称 | 角色 | 输出示例 |
|------|------|----------|
| 有 | 有 | `昵称 [角色]` |
| 有 | 无 | `昵称` |
| 无 | 有 | `[角色]` |
| 无 | 无 | `Agent` |
| 主代理 | - | `Main [default]` |

## 关键代码路径与文件引用

- **源文件**: `codex-rs/tui/src/multi_agents.rs`
- **测试文件**: `codex-rs/tui/src/app.rs` (测试函数 `agent_picker_item_name`)
- **相关函数**: `format_agent_picker_item_name`
- **调用方**: Agent 选择器 UI (`/agent` 命令)

## 依赖与外部交互

- **依赖模块**: `multi_agents` 模块提供格式化功能
- **协议类型**: `CollabAgentRef`, `AgentStatus`
- **UI 集成**: 在 Agent 选择器弹窗中显示代理列表

## 风险、边界与改进建议

### 边界情况

1. **空字符串处理**：函数会对昵称和角色进行 `trim()` 和空值过滤，空字符串会被视为 None
2. **特殊字符**：快照显示 UUID 作为代理 ID 后缀（`00000000-0000-0000-0000-000000000123`）
3. **主代理优先级**：`is_primary` 标志优先级最高，会覆盖其他格式化逻辑

### 风险点

1. **国际化**：当前硬编码的 "Main", "default", "Agent" 字符串不支持本地化
2. **长名称截断**：超长昵称或角色可能导致 UI 显示问题（依赖调用方截断）

### 改进建议

1. 考虑添加国际化支持（i18n）
2. 添加最大长度限制或截断提示
3. 考虑添加角色图标/颜色区分不同代理类型
