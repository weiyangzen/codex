# 多代理恢复中断状态快照研究文档

## 场景与职责

该快照文件记录了 `codex-rs/tui` 项目中**多代理恢复（Resume）功能**在中断状态下的渲染结果。它展示了当主代理恢复一个之前被中断的子代理时，转录中显示的状态信息。这是多代理协作系统中错误恢复和状态管理的重要组成部分。

**核心职责：**
- 显示代理恢复操作的状态
- 标识被恢复代理的身份（昵称、角色）
- 展示代理的当前状态（"Interrupted"）
- 提供清晰的操作反馈

## 功能点目的

### 1. 恢复操作可视化
- **Resumed 前缀**：明确标识这是一个恢复操作
- **代理标识**：显示被恢复代理的昵称和角色
- **状态摘要**：显示代理被中断时的状态

### 2. 中断状态处理
- **状态传递**：保留代理中断时的状态信息
- **用户反馈**：让用户了解代理之前发生了什么
- **恢复确认**：确认恢复操作已成功执行

### 3. 与 Begin/End 事件配对
- **Resume Begin**：显示 "Resuming"（操作开始）
- **Resume End**：显示 "Resumed" + 状态（操作完成）
- 本快照展示的是 End 事件的渲染结果

## 具体技术实现

### 核心数据结构

**CollabResumeEndEvent** - 恢复结束事件：
```rust
pub struct CollabResumeEndEvent {
    pub call_id: String,
    pub sender_thread_id: ThreadId,
    pub receiver_thread_id: ThreadId,
    pub receiver_agent_nickname: Option<String>,
    pub receiver_agent_role: Option<String>,
    pub status: AgentStatus,  // 关键字段：恢复时的状态
}
```

**AgentStatus** - 代理状态枚举：
```rust
pub enum AgentStatus {
    PendingInit,
    Running,
    Interrupted,  // 本快照展示的状态
    Completed(Option<String>),
    Errored(String),
    Shutdown,
    NotFound,
}
```

### 恢复事件处理

**Resume Begin（开始恢复）：**
```rust
pub(crate) fn resume_begin(ev: CollabResumeBeginEvent) -> PlainHistoryCell {
    let CollabResumeBeginEvent {
        call_id: _,
        sender_thread_id: _,
        receiver_thread_id,
        receiver_agent_nickname,
        receiver_agent_role,
    } = ev;

    collab_event(
        title_with_agent(
            "Resuming",  // 注意：进行时态
            AgentLabel {
                thread_id: Some(receiver_thread_id),
                nickname: receiver_agent_nickname.as_deref(),
                role: receiver_agent_role.as_deref(),
            },
            /*spawn_request*/ None,
        ),
        Vec::new(),
    )
}
```

**Resume End（恢复完成）：**
```rust
pub(crate) fn resume_end(ev: CollabResumeEndEvent) -> PlainHistoryCell {
    let CollabResumeEndEvent {
        call_id: _,
        sender_thread_id: _,
        receiver_thread_id,
        receiver_agent_nickname,
        receiver_agent_role,
        status,  // 恢复时的状态
    } = ev;

    collab_event(
        title_with_agent(
            "Resumed",  // 注意：完成时态
            AgentLabel {
                thread_id: Some(receiver_thread_id),
                nickname: receiver_agent_nickname.as_deref(),
                role: receiver_agent_role.as_deref(),
            },
            /*spawn_request*/ None,
        ),
        vec![status_summary_line(&status)],  // 显示状态
    )
}
```

### 状态摘要渲染

```rust
fn status_summary_line(status: &AgentStatus) -> Line<'static> {
    status_summary_spans(status).into()
}

#[allow(clippy::disallowed_methods)]
fn status_summary_spans(status: &AgentStatus) -> Vec<Span<'static>> {
    match status {
        AgentStatus::PendingInit => vec![Span::from("Pending init").cyan()],
        AgentStatus::Running => vec![Span::from("Running").cyan().bold()],
        AgentStatus::Interrupted => vec![Span::from("Interrupted").yellow()],  // 本快照
        AgentStatus::Completed(message) => {
            let mut spans = vec![Span::from("Completed").green()];
            if let Some(message) = message {
                let message_preview = truncate_text(
                    &message.split_whitespace().collect::<Vec<_>>().join(" "),
                    COLLAB_AGENT_RESPONSE_PREVIEW_GRAPHEMES,
                );
                if !message_preview.is_empty() {
                    spans.push(Span::from(" - ").dim());
                    spans.push(Span::from(message_preview));
                }
            }
            spans
        }
        AgentStatus::Errored(error) => {
            let mut spans = vec![Span::from("Error").red()];
            // ... 错误预览
            spans
        }
        AgentStatus::Shutdown => vec![Span::from("Shutdown")],
        AgentStatus::NotFound => vec![Span::from("Not found").red()],
    }
}
```

## 关键代码路径与文件引用

### 主要源文件

| 文件路径 | 职责 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/tui/src/multi_agents.rs` | 多代理渲染实现，包含恢复事件处理 |

### 关键函数路径

```
multi_agents.rs:772
└── fn collab_resume_interrupted_snapshot()  [测试函数]
    ├── resume_end(CollabResumeEndEvent { ... })  [line 326]
    │   ├── title_with_agent("Resumed", agent_label, None)
    │   │   ├── agent_label_spans(AgentLabel { nickname: "Robie", role: "explorer" })
    │   │   └── title_spans_line(["• ".dim(), "Resumed ".bold(), "Robie".cyan().bold(), " [explorer]"])
    │   └── status_summary_line(&AgentStatus::Interrupted)
    │       └── status_summary_spans(AgentStatus::Interrupted)
    │           └── vec![Span::from("Interrupted").yellow()]
    ├── collab_event(title, details)  [line 350]
    │   └── PlainHistoryCell::new(lines)  [line 355]
    └── assert_snapshot!("collab_resume_interrupted", cell_to_text(&cell))  [line 788]
```

### 测试数据

```rust
let sender_thread_id = ThreadId::from_string("00000000-0000-0000-0000-000000000001").expect("valid");
let robie_id = ThreadId::from_string("00000000-0000-0000-0000-000000000002").expect("valid");

let cell = resume_end(CollabResumeEndEvent {
    call_id: "call-resume".to_string(),
    sender_thread_id,
    receiver_thread_id: robie_id,
    receiver_agent_nickname: Some("Robie".to_string()),
    receiver_agent_role: Some("explorer".to_string()),
    status: AgentStatus::Interrupted,  // 中断状态
});
```

## 依赖与外部交互

### 颜色编码

| 状态 | 颜色 | 用途 |
|-----|------|------|
| `PendingInit` | 青色 | 等待初始化 |
| `Running` | 青色 + 粗体 | 运行中 |
| `Interrupted` | 黄色 | 已中断（本快照）|
| `Completed` | 绿色 | 成功完成 |
| `Errored` | 红色 | 执行错误 |
| `Shutdown` | 默认 | 已关闭 |
| `NotFound` | 红色 | 代理未找到 |

### 与相关功能的对比

| 功能 | 前缀 | 状态显示 | 用途 |
|-----|------|---------|------|
| Spawn | "Spawned" | 无 | 创建代理 |
| Interaction | "Sent input to" | 无 | 发送任务 |
| Waiting Begin | "Waiting for" | 无 | 开始等待 |
| Waiting End | "Finished waiting" | 多代理状态列表 | 等待结束 |
| Resume Begin | "Resuming" | 无 | 开始恢复 |
| Resume End | "Resumed" | 单个代理状态 | 恢复完成（本快照）|
| Close | "Closed" | 无 | 关闭代理 |

## 风险、边界与改进建议

### 已知风险

1. **状态信息不足**
   - 仅显示 "Interrupted"，不说明中断原因
   - 风险：用户不知道为何代理被中断
   - 建议：添加中断原因字段（如用户取消、超时、错误）

2. **恢复失败处理**
   - 当前假设恢复总是成功
   - 风险：恢复失败时无反馈
   - 建议：添加恢复失败状态和错误信息

3. **状态过时**
   - 显示的是中断时的状态，可能不是当前状态
   - 风险：用户可能对代理实际状态产生误解
   - 建议：添加时间戳或状态 freshness 指示

### 边界情况

1. **代理不存在**
   - 尝试恢复已删除的代理
   - 当前行为：可能显示 `NotFound` 状态

2. **并发恢复**
   - 多个恢复操作同时进行
   - 当前渲染：每个恢复独立显示

3. **恢复后立即中断**
   - 恢复后代理再次中断
   - 当前显示：两个独立事件

### 改进建议

1. **丰富状态信息**
   - 添加中断原因（用户取消、系统错误、超时）
   - 显示中断发生的时间
   - 添加上下文摘要（中断前执行的任务）

2. **恢复操作增强**
   - 添加 "Resume with changes" 选项
   - 允许修改任务后恢复
   - 支持批量恢复多个中断代理

3. **视觉区分**
   - 使用不同图标区分恢复类型
   - 添加动画效果表示恢复进行中

4. **历史记录**
   - 记录代理的中断/恢复历史
   - 显示在代理详情面板中

5. **自动恢复**
   - 添加配置选项：某些错误自动重试
   - 减少用户手动恢复的负担

6. **恢复确认**
   - 对于长时间运行的代理，恢复前确认
   - 避免意外恢复消耗资源
