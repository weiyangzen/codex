# ChatWidget Snapshots 目录研究文档

## 1. 场景与职责

### 1.1 目录定位

`snapshots/` 目录位于 `codex-rs/tui/src/chatwidget/` 下，是 Codex TUI（Terminal User Interface）项目中 **ChatWidget 组件的 UI 快照测试数据存储目录**。该目录包含 84 个 `.snap` 文件，用于存储基于 `insta` 框架的 UI 回归测试预期输出。

### 1.2 核心职责

- **UI 回归测试基准**: 存储 ChatWidget 在各种状态下的预期渲染输出
- **视觉变更检测**: 通过快照比对检测意外的 UI 变更
- **文档化 UI 状态**: 以文本形式记录组件在不同场景下的视觉表现
- **跨平台测试**: 包含平台特定快照（如 `@windows`, `@windows_degraded` 后缀）

### 1.3 测试覆盖范围

| 类别 | 覆盖场景 |
|------|----------|
| 布局渲染 | 不同高度（h1/h2/h3）、空闲/运行状态 |
| 审批弹窗 | Exec/Patch 命令审批、多行命令、无原因场景 |
| 执行状态 | Unified Exec 等待、后台终端、探索模式 |
| Guardian 审核 | 批准/拒绝执行请求、并行审核聚合 |
| 实时对话 | 音频选择、麦克风选择、窄屏适配 |
| 计划模式 | 计划实现弹窗、推理选择、范围提示 |
| 反馈系统 | 反馈选择、上传同意弹窗、好结果评价 |
| 协作功能 | 多代理启用提示、分叉线程历史线 |
| 权限管理 | 审批选择历史、全访问确认 |
| 模型选择 | 模型选择弹窗、推理级别选择 |
| MCP 启动 | 启动头信息、工具调用 |
| 图片处理 | 本地图片附件、图片生成调用 |
| 终端交互 | 用户 shell 输出、Markdown 代码块 |

---

## 2. 功能点目的

### 2.1 快照测试机制

```rust
// 典型测试模式（来自 tests.rs）
#[tokio::test]
async fn exec_approval_emits_proposed_command_and_decision_history() {
    // ... 设置测试场景 ...
    
    // 渲染 UI
    let area = Rect::new(0, 0, 80, chat.desired_height(80));
    let mut buf = ratatui::buffer::Buffer::empty(area);
    chat.render(area, &mut buf);
    
    // 断言快照
    assert_snapshot!("exec_approval_modal_exec", format!("{buf:?}"));
    
    // 模拟用户按键
    chat.handle_key_event(KeyEvent::new(KeyCode::Char('y'), KeyModifiers::NONE));
    
    // 验证历史输出
    let decision = drain_insert_history(&mut rx).pop().expect("expected decision cell");
    assert_snapshot!("exec_approval_history_decision_approved_short", lines_to_single_string(&decision));
}
```

### 2.2 关键功能验证点

#### 2.2.1 审批流程验证
- **Exec 审批**: 验证命令显示、原因说明、决策选项渲染
- **Patch 审批**: 验证文件变更展示、应用确认界面
- **Guardian 审核**: 验证自动审核结果的视觉呈现

#### 2.2.2 状态指示器验证
- 工作状态（Working）与空闲状态的区分
- 后台终端等待状态的命令显示
- Unified Exec 进程列表渲染

#### 2.2.3 弹窗交互验证
- 模型选择弹窗的过滤与隐藏模型处理
- 推理级别选择的额外高警告显示
- 计划实现弹窗的是/否选项状态

#### 2.2.4 历史记录验证
- 用户消息与助手消息的区分渲染
- 执行命令的历史记录格式
- 分叉线程的历史线显示

---

## 3. 具体技术实现

### 3.1 快照文件格式

```yaml
---
source: tui/src/chatwidget/tests.rs
expression: terminal.backend().vt100().screen().contents()
---

• Working (0s • esc to interrupt)

› Ask Codex to do anything

  ? for shortcuts                                            100% context left
```

**格式说明**:
- `source`: 生成快照的源文件路径
- `expression`: 生成快照的表达式
- `---` 分隔符后的内容: 实际的预期输出

### 3.2 关键数据结构

#### 3.2.1 ChatWidget 状态管理
```rust
pub(crate) struct ChatWidget {
    app_event_tx: AppEventSender,
    codex_op_tx: UnboundedSender<Op>,
    bottom_pane: BottomPane,
    active_cell: Option<Box<dyn HistoryCell>>,
    active_cell_revision: u64,  // 用于缓存失效的单调计数器
    
    // 会话状态
    thread_id: Option<ThreadId>,
    thread_name: Option<String>,
    forked_from: Option<ThreadId>,
    
    // 运行时状态
    agent_turn_running: bool,
    mcp_startup_status: Option<HashMap<String, McpStartupStatus>>,
    
    // 中断管理
    interrupts: InterruptManager,
    
    // 流控制
    stream_controller: Option<StreamController>,
    plan_stream_controller: Option<PlanStreamController>,
    
    // 用户输入队列
    queued_user_messages: VecDeque<UserMessage>,
    pending_steers: VecDeque<PendingSteer>,
    
    // ... 其他字段
}
```

#### 3.2.2 中断管理器
```rust
#[derive(Debug)]
pub(crate) enum QueuedInterrupt {
    ExecApproval(ExecApprovalRequestEvent),
    ApplyPatchApproval(ApplyPatchApprovalRequestEvent),
    Elicitation(ElicitationRequestEvent),
    RequestPermissions(RequestPermissionsEvent),
    RequestUserInput(RequestUserInputEvent),
    ExecBegin(ExecCommandBeginEvent),
    ExecEnd(ExecCommandEndEvent),
    McpBegin(McpToolCallBeginEvent),
    McpEnd(McpToolCallEndEvent),
    PatchEnd(PatchApplyEndEvent),
}

#[derive(Default)]
pub(crate) struct InterruptManager {
    queue: VecDeque<QueuedInterrupt>,
}
```

### 3.3 关键流程

#### 3.3.1 事件处理流程
```rust
pub fn handle_codex_event(&mut self, event: Event) {
    match event.msg {
        EventMsg::ExecApprovalRequest(ev) => self.on_exec_approval_request(event.id, ev),
        EventMsg::ExecCommandBegin(ev) => self.on_exec_command_begin(ev),
        EventMsg::ExecCommandEnd(ev) => self.on_exec_command_end(ev),
        EventMsg::AgentMessage(ev) => self.on_agent_message(ev.message),
        EventMsg::AgentMessageDelta(ev) => self.on_agent_message_delta(ev.delta),
        EventMsg::TurnComplete(ev) => self.on_task_complete(ev.last_agent_message, false),
        // ... 其他事件处理
    }
}
```

#### 3.3.2 渲染流程
```rust
fn render(&mut self, area: Rect, buf: &mut Buffer) {
    // 1. 更新任务运行状态
    self.update_task_running_state();
    
    // 2. 刷新运行时指标
    self.refresh_runtime_metrics();
    
    // 3. 恢复状态指示器（如果需要）
    self.maybe_restore_status_indicator_after_stream_idle();
    
    // 4. 渲染底部面板（包含输入、状态、弹窗）
    self.bottom_pane.render(area, buf);
}
```

#### 3.3.3 快照测试执行流程
```
测试函数
  ↓
创建 ChatWidget（手动构造，绕过正常初始化）
  ↓
模拟事件序列（handle_codex_event）
  ↓
触发渲染（render 到 TestBackend/VT100Backend）
  ↓
捕获输出（terminal.backend().vt100().screen().contents()）
  ↓
与 .snap 文件比对（assert_snapshot!）
```

### 3.4 测试辅助函数

```rust
// 创建手动测试实例
async fn make_chatwidget_manual(
    model_override: Option<&str>,
) -> (ChatWidget, UnboundedReceiver<AppEvent>, UnboundedReceiver<Op>) {
    // 构造最小化 ChatWidget，绕过 agent 初始化
}

// 排空历史插入事件
fn drain_insert_history(
    rx: &mut UnboundedReceiver<AppEvent>,
) -> Vec<Vec<ratatui::text::Line<'static>>> {
    // 收集所有 InsertHistoryCell 事件
}

// 行转字符串
fn lines_to_single_string(lines: &[ratatui::text::Line<'static>]) -> String {
    // 用于快照比对
}

// 渲染底部弹窗
fn render_bottom_popup(chat: &ChatWidget, width: u16) -> String {
    // 辅助函数，用于弹窗快照测试
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件结构

```
codex-rs/tui/src/chatwidget/
├── mod.rs                    # 模块入口（无实际代码，仅组织子模块）
├── lib.rs                    # 实际 ChatWidget 实现（约 3000+ 行）
├── tests.rs                  # 测试文件（约 5000+ 行，包含快照测试）
├── agent.rs                  # Agent 启动与管理（spawn_agent 等）
├── interrupts.rs             # 中断事件队列管理
├── realtime.rs               # 实时语音对话状态管理
├── session_header.rs         # 会话头信息管理
├── skills.rs                 # Skills 功能集成
└── snapshots/                # 快照文件目录
    ├── codex_tui__chatwidget__tests__*.snap
    └── ...
```

### 4.2 关键代码路径

| 功能 | 文件路径 | 关键函数/结构体 |
|------|----------|-----------------|
| 主组件 | `chatwidget.rs` | `ChatWidget` struct, `handle_codex_event` |
| 测试 | `chatwidget/tests.rs` | `make_chatwidget_manual`, `drain_insert_history` |
| Agent | `chatwidget/agent.rs` | `spawn_agent`, `spawn_agent_from_existing` |
| 中断 | `chatwidget/interrupts.rs` | `InterruptManager`, `QueuedInterrupt` |
| 实时 | `chatwidget/realtime.rs` | `RealtimeConversationUiState` |
| Skills | `chatwidget/skills.rs` | `collect_tool_mentions`, `find_skill_mentions_with_tool_mentions` |

### 4.3 快照生成路径

```rust
// 路径 1: VT100 终端模拟器输出
tui/src/chatwidget/tests.rs:9195
assert_snapshot!("guardian_approved_exec_renders_approved_request", 
    term.backend().vt100().screen().contents());

// 路径 2: 缓冲区直接格式化
tui/src/chatwidget/tests.rs:3322
assert_snapshot!("exec_approval_modal_exec", format!("{buf:?}"));

// 路径 3: 行内容合并
tui/src/chatwidget/tests.rs:3330
assert_snapshot!("exec_approval_history_decision_approved_short", 
    lines_to_single_string(&decision));

// 路径 4: 底部弹窗渲染
tui/src/chatwidget/tests.rs:2457
assert_snapshot!("rate_limit_switch_prompt_popup", render_bottom_popup(&chat, 80));
```

---

## 5. 依赖与外部交互

### 5.1 直接依赖

| 依赖 | 用途 |
|------|------|
| `ratatui` | 终端 UI 渲染框架 |
| `insta` | 快照测试框架 |
| `crossterm` | 终端事件处理（按键等） |
| `tokio` | 异步运行时 |
| `serde` | 序列化/反序列化 |

### 5.2 内部模块依赖

```
chatwidget
  ├── app_event          # 应用事件定义
  ├── app_event_sender   # 事件发送器
  ├── bottom_pane        # 底部面板（输入、状态、弹窗）
  ├── history_cell       # 历史记录单元格
  ├── exec_cell          # 执行命令单元格
  ├── status             # 状态显示
  ├── streaming          # 流控制（chunking, controller）
  ├── voice              # 语音功能（非 Linux 平台）
  └── ...
```

### 5.3 协议依赖

```rust
use codex_protocol::protocol::*;
use codex_protocol::items::*;
use codex_protocol::config_types::*;
```

ChatWidget 通过 `Event` 和 `Op` 与 codex-core 通信：
- **输入**: `Event`（来自 core 的事件流）
- **输出**: `Op`（提交给 core 的操作）

### 5.4 测试依赖

```rust
use crate::test_backend::VT100Backend;  // 自定义测试后端
use codex_core::test_support::*;         // 测试辅助函数
```

---

## 6. 风险、边界与改进建议

### 6.1 当前风险

#### 6.1.1 快照维护成本
- **问题**: 84 个快照文件，UI 变更时需要批量更新
- **影响**: 开发迭代中的额外开销
- **缓解**: 使用 `cargo insta review` 交互式审查变更

#### 6.1.2 平台差异
- **问题**: Windows 平台有特定快照（`@windows`, `@windows_degraded`）
- **影响**: 跨平台功能差异导致测试复杂度增加
- **缓解**: 条件编译和平台特定测试逻辑

#### 6.1.3 测试与实现耦合
- **问题**: `tests.rs` 与实现紧密耦合，使用 `make_chatwidget_manual` 构造内部状态
- **影响**: 内部重构可能破坏测试
- **缓解**: 保持构造函数稳定，或使用更抽象的测试接口

### 6.2 边界情况

#### 6.2.1 极端尺寸
- **h1/h2/h3 测试**: 验证极小高度下的渲染
- **窄屏测试**: `realtime_audio_selection_popup_narrow` 测试窄屏适配

#### 6.2.2 并发场景
- **并行 Guardian 审核**: `guardian_parallel_reviews_render_aggregate_status`
- **多 Unified Exec**: `unified_exec_waiting_multiple_empty_after`

#### 6.2.3 中断恢复
- **中断后恢复**: `interrupted_turn_restores_queued_messages_with_images_and_elements`
- **计划模式切换**: `interrupted_turn_restore_keeps_active_mode_for_resubmission`

### 6.3 改进建议

#### 6.3.1 快照组织
```
snapshots/
├── approval/           # 审批相关快照
├── exec/               # 执行命令快照
├── popup/              # 弹窗快照
├── status/             # 状态指示器快照
└── ...
```

#### 6.3.2 测试覆盖率增强
- 增加无障碍（accessibility）输出快照
- 增加颜色/主题变体快照
- 增加更多错误状态快照

#### 6.3.3 自动化工具
- CI 中集成 `cargo insta` 自动审查
- 快照变更的自动化通知机制
- 快照文件大小优化（去除冗余空白）

#### 6.3.4 文档化
- 每个快照文件添加注释说明测试场景
- 维护快照与测试函数的映射索引
- 提供快照更新最佳实践指南

---

## 7. 附录

### 7.1 快照命名约定

```
codex_tui__chatwidget__tests__{test_name}.snap
```

- 前缀 `codex_tui__chatwidget__tests__` 由 `insta` 自动生成
- `{test_name}` 对应测试函数名
- 平台变体使用 `@{platform}` 后缀

### 7.2 常用命令

```bash
# 运行 ChatWidget 测试
cargo test -p codex-tui chatwidget

# 查看待审查快照
cargo insta pending-snapshots -p codex-tui

# 接受所有新快照
cargo insta accept -p codex-tui

# 显示特定快照
cargo insta show -p codex-tui path/to/file.snap.new
```

### 7.3 相关文档

- `AGENTS.md`: 项目级开发规范
- `codex-rs/tui/styles.md`: TUI 样式规范
- `codex-rs/tui/README.md`: TUI 模块文档
