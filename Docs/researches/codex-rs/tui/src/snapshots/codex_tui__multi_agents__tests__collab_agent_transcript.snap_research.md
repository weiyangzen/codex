# 多代理协作会话转录快照研究文档

## 场景与职责

该快照文件记录了 `codex-rs/tui` 项目中**多代理协作系统**的会话转录渲染结果。它展示了当主代理（Main Agent）派生子代理（Sub-agents）执行任务时的完整交互流程，包括代理创建、任务分配、等待执行和结果收集的全过程。

**核心职责：**
- 可视化多代理系统的协作流程
- 记录代理生命周期事件（Spawn、Send、Wait、Complete、Close）
- 显示代理状态和任务结果
- 提供清晰的层次结构展示（使用缩进和符号）

## 功能点目的

### 1. 代理生命周期可视化
- **Spawned**：显示代理创建，包含昵称、角色和模型配置
- **Sent input**：记录向代理发送的任务指令
- **Waiting**：显示等待代理执行的状态
- **Finished waiting**：汇总所有代理的执行结果
- **Closed**：标记代理会话结束

### 2. 代理身份标识
- **昵称（Nickname）**：如 "Robie"、"Bob"
- **角色（Role）**：如 "explorer"、"worker"
- **模型配置**：如 "gpt-5 high"（模型 + 推理努力级别）

### 3. 任务结果展示
- **成功状态**：显示 "Completed" 和结果摘要（如 "39916800"）
- **错误状态**：显示 "Error" 和错误信息（如 "tool timeout"）
- **状态颜色编码**：成功为绿色，错误为红色

### 4. 层次结构渲染
- **主事件**：使用 `•` 符号标记
- **详情行**：使用 `└` 符号表示从属关系
- **缩进对齐**：保持视觉层次清晰

## 具体技术实现

### 核心数据结构

**AgentLabel** - 代理标识：
```rust
#[derive(Clone, Copy)]
struct AgentLabel<'a> {
    thread_id: Option<ThreadId>,
    nickname: Option<&'a str>,
    role: Option<&'a str>,
}
```

**SpawnRequestSummary** - 创建请求摘要：
```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct SpawnRequestSummary {
    pub(crate) model: String,
    pub(crate) reasoning_effort: ReasoningEffortConfig,
}
```

**CollabAgentRef** - 代理引用（来自协议）：
```rust
pub struct CollabAgentRef {
    pub thread_id: ThreadId,
    pub agent_nickname: Option<String>,
    pub agent_role: Option<String>,
}
```

### 事件处理函数

**Spawn 事件处理：**
```rust
pub(crate) fn spawn_end(
    ev: CollabAgentSpawnEndEvent,
    spawn_request: Option<&SpawnRequestSummary>,
) -> PlainHistoryCell {
    let CollabAgentSpawnEndEvent {
        call_id: _,
        sender_thread_id: _,
        new_thread_id,
        new_agent_nickname,
        new_agent_role,
        prompt,
        status: _,
        ..
    } = ev;

    let title = match new_thread_id {
        Some(thread_id) => title_with_agent(
            "Spawned",
            AgentLabel {
                thread_id: Some(thread_id),
                nickname: new_agent_nickname.as_deref(),
                role: new_agent_role.as_deref(),
            },
            spawn_request,
        ),
        None => title_text("Agent spawn failed"),
    };

    let mut details = Vec::new();
    if let Some(line) = prompt_line(&prompt) {
        details.push(line);
    }
    collab_event(title, details)
}
```

**Interaction 事件处理：**
```rust
pub(crate) fn interaction_end(ev: CollabAgentInteractionEndEvent) -> PlainHistoryCell {
    let CollabAgentInteractionEndEvent {
        call_id: _,
        sender_thread_id: _,
        receiver_thread_id,
        receiver_agent_nickname,
        receiver_agent_role,
        prompt,
        status: _,
    } = ev;

    let title = title_with_agent(
        "Sent input to",
        AgentLabel {
            thread_id: Some(receiver_thread_id),
            nickname: receiver_agent_nickname.as_deref(),
            role: receiver_agent_role.as_deref(),
        },
        /*spawn_request*/ None,
    );

    let mut details = Vec::new();
    if let Some(line) = prompt_line(&prompt) {
        details.push(line);
    }
    collab_event(title, details)
}
```

**Waiting 结束事件处理：**
```rust
pub(crate) fn waiting_end(ev: CollabWaitingEndEvent) -> PlainHistoryCell {
    let CollabWaitingEndEvent {
        call_id: _,
        sender_thread_id: _,
        agent_statuses,
        statuses,
    } = ev;
    let details = wait_complete_lines(&statuses, &agent_statuses);
    collab_event(title_text("Finished waiting"), details)
}
```

### 标题构建

```rust
fn title_with_agent(
    prefix: &str,
    agent: AgentLabel<'_>,
    spawn_request: Option<&SpawnRequestSummary>,
) -> Line<'static> {
    let mut spans = vec![Span::from(format!("{prefix} ")).bold()];
    spans.extend(agent_label_spans(agent));
    spans.extend(spawn_request_spans(spawn_request));
    title_spans_line(spans)
}

fn agent_label_spans(agent: AgentLabel<'_>) -> Vec<Span<'static>> {
    let mut spans = Vec::new();
    let nickname = agent.nickname.map(str::trim).filter(|n| !n.is_empty());
    let role = agent.role.map(str::trim).filter(|r| !r.is_empty());

    if let Some(nickname) = nickname {
        spans.push(Span::from(nickname.to_string()).cyan().bold());
    } else if let Some(thread_id) = agent.thread_id {
        spans.push(Span::from(thread_id.to_string()).cyan());
    } else {
        spans.push(Span::from("agent").cyan());
    }

    if let Some(role) = role {
        spans.push(Span::from(" ").dim());
        spans.push(Span::from(format!("[{role}]")));
    }

    spans
}

fn spawn_request_spans(spawn_request: Option<&SpawnRequestSummary>) -> Vec<Span<'static>> {
    let Some(spawn_request) = spawn_request else {
        return Vec::new();
    };

    let model = spawn_request.model.trim();
    if model.is_empty() && spawn_request.reasoning_effort == ReasoningEffortConfig::default() {
        return Vec::new();
    }

    let details = if model.is_empty() {
        format!("({})", spawn_request.reasoning_effort)
    } else {
        format!("({model} {})", spawn_request.reasoning_effort)
    };

    vec![Span::from(" ").dim(), Span::from(details).magenta()]
}
```

### 事件组装

```rust
fn collab_event(title: Line<'static>, details: Vec<Line<'static>>) -> PlainHistoryCell {
    let mut lines: Vec<Line<'static>> = vec![title];
    if !details.is_empty() {
        lines.extend(prefix_lines(details, "  └ ".dim(), "    ".into()));
    }
    PlainHistoryCell::new(lines)
}
```

## 关键代码路径与文件引用

### 主要源文件

| 文件路径 | 职责 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/tui/src/multi_agents.rs` | 多代理渲染和导航的完整实现 |

### 关键函数路径

```
multi_agents.rs:595
└── fn collab_events_snapshot()  [测试函数]
    ├── spawn_end(CollabAgentSpawnEndEvent { ... })  [line 174]
    │   └── title_with_agent("Spawned", agent_label, spawn_request)
    │       └── agent_label_spans(agent)
    │       └── spawn_request_spans(spawn_request)
    ├── interaction_end(CollabAgentInteractionEndEvent { ... })  [line 209]
    ├── waiting_begin(CollabWaitingBeginEvent { ... })  [line 237]
    ├── waiting_end(CollabWaitingEndEvent { ... })  [line 268]
    │   └── wait_complete_lines(&statuses, &agent_statuses)
    │       └── status_summary_spans(&status)  [line 546]
    ├── close_end(CollabCloseEndEvent { ... })  [line 279]
    └── assert_snapshot!("collab_agent_transcript", snapshot)  [line 683]
```

### 协议事件类型

来自 `codex_protocol::protocol`：

| 事件类型 | 描述 |
|---------|------|
| `CollabAgentSpawnEndEvent` | 代理创建完成 |
| `CollabAgentInteractionEndEvent` | 向代理发送输入完成 |
| `CollabWaitingBeginEvent` | 开始等待代理 |
| `CollabWaitingEndEvent` | 等待代理结束 |
| `CollabCloseEndEvent` | 关闭代理完成 |
| `CollabAgentStatusEntry` | 代理状态条目 |

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `codex_protocol` | 协议定义（事件类型、ThreadId、AgentStatus 等） |
| `ratatui` | 终端 UI 渲染 |
| `crossterm` | 键盘事件处理 |

### 内部模块交互

```
multi_agents.rs
├── history_cell::PlainHistoryCell  [历史单元格]
├── render::line_utils::prefix_lines  [行前缀工具]
├── text_formatting::truncate_text  [文本截断]
└── key_hint  [按键提示]
```

### 颜色编码

| 元素 | 颜色 | 样式 |
|-----|------|------|
| 代理昵称 | 青色 | 粗体 |
| 代理角色 | 默认 | 无 |
| 模型配置 | 洋红色 | 无 |
| 事件前缀（Spawned/Sent 等） | 默认 | 粗体 |
| 状态点 `•` | 绿色（活跃）/默认（关闭） | 无 |
| 详情前缀 `└` | 暗淡 | 无 |

## 风险、边界与改进建议

### 已知风险

1. **状态显示延迟**
   - 代理状态更新依赖事件流
   - 风险：网络延迟可能导致状态显示不及时
   - 缓解：使用本地乐观更新

2. **长提示截断**
   - 任务提示超过 `COLLAB_PROMPT_PREVIEW_GRAPHEMES`（160 字符）会被截断
   - 风险：重要上下文信息可能丢失
   - 建议：添加展开查看完整提示的功能

3. **多代理状态拥挤**
   - 当同时等待多个代理时，状态行可能过长
   - 风险：终端宽度不足时显示混乱
   - 建议：添加折叠/展开功能

### 边界情况

1. **代理创建失败**
   - 当 `new_thread_id` 为 `None` 时显示 "Agent spawn failed"
   - 测试覆盖：需要验证错误处理路径

2. **空提示处理**
   - `prompt_line()` 在提示为空时返回 `None`
   - 确保不渲染空行

3. **代理名称冲突**
   - 多个代理可能有相同昵称
   - 当前使用 thread_id 作为后备标识

### 改进建议

1. **交互增强**
   - 添加点击/快捷键查看代理详情
   - 支持在转录中直接跳转到特定代理的会话

2. **状态可视化**
   - 添加进度指示器（如旋转图标）表示等待中
   - 使用不同图标区分代理类型（🔍 explorer、🔧 worker）

3. **时间戳显示**
   - 添加相对时间戳（如 "2s ago"）
   - 帮助用户理解执行时间

4. **结果折叠**
   - 长结果默认折叠，点击展开
   - 避免转录过长

5. **错误重试**
   - 在错误状态旁添加重试按钮/快捷键
   - 简化错误恢复流程

6. **代理树视图**
   - 对于嵌套代理创建，显示树形结构
   - 更清晰地展示代理层次关系

7. **搜索和过滤**
   - 添加按代理名称/角色过滤功能
   - 在大量代理中快速定位
