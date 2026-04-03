# Research: Unified Exec Wait Status Renders Command in Single Details Row

## 场景与职责

该 snapshot 测试验证当 Codex TUI 处于**统一执行等待状态**（Unified Exec Wait Status）时，状态指示器（Status Indicator）能够正确地在单行详情中渲染当前正在执行的命令。

**测试场景：**
- 用户启动了一个后台终端进程（如 `cargo test -p codex-core -- --exact some::very::long::test::name`）
- 该进程处于等待状态，需要显示"Waiting for background terminal"
- 命令文本较长，需要验证其在有限宽度（48字符）下的渲染行为

**核心职责：**
1. 确保状态指示器头部显示"Waiting for background terminal"
2. 确保命令文本在单行详情行中正确截断/显示
3. 验证底部弹出框（bottom popup）的整体布局稳定性

---

## 功能点目的

### 1. 统一执行等待状态（Unified Exec Wait State）
当 Codex 启动后台终端进程（通过 `ExecCommandSource::UnifiedExecStartup` 或 `ExecCommandSource::UnifiedExecInteraction`）时，TUI 需要向用户显示当前正在等待的进程状态。

### 2. 状态指示器详情行（Status Indicator Details）
状态指示器包含：
- **Header**: 显示当前状态（如 "Waiting for background terminal"）
- **Details**: 显示具体命令（单行，可能截断）
- **计时器**: 显示等待时长
- **中断提示**: "esc to interrupt"

### 3. 命令显示优化
对于长命令，需要在有限宽度内优雅地显示，确保用户能够识别正在执行的命令，同时不影响 UI 布局。

---

## 具体技术实现

### 测试代码路径
**文件**: `codex-rs/tui/src/chatwidget/tests.rs`  
**函数**: `unified_exec_wait_status_renders_command_in_single_details_row_snapshot`

```rust
#[tokio::test]
async fn unified_exec_wait_status_renders_command_in_single_details_row_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.on_task_started();
    begin_unified_exec_startup(
        &mut chat,
        "call-wait-ui",
        "proc-ui",
        "cargo test -p codex-core -- --exact some::very::long::test::name",
    );

    terminal_interaction(&mut chat, "call-wait-ui-stdin", "proc-ui", "");

    let rendered = render_bottom_popup(&chat, 48);
    assert_snapshot!(
        "unified_exec_wait_status_renders_command_in_single_details_row",
        rendered
    );
}
```

### 关键实现组件

#### 1. UnifiedExecWaitStreak 结构体
```rust
struct UnifiedExecWaitStreak {
    process_id: String,
    command_display: Option<String>,
}
```
用于跟踪统一执行等待状态，维护进程ID和命令显示文本。

#### 2. 状态指示器渲染
在 `chatwidget.rs` 中，`on_terminal_interaction` 方法处理终端交互事件：
- 当 `stdin` 为空时，表示正在轮询后台输出
- 设置状态指示器头部为 "Waiting for background terminal"
- 在单行详情中显示命令（`details_max_lines: 1`）

#### 3. 命令显示截断
命令显示通过 `strip_bash_lc_and_escape` 函数处理，去除 `bash -lc` 前缀并转义特殊字符。

---

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/chatwidget.rs` | ChatWidget 主实现，包含统一执行状态管理 |
| `codex-rs/tui/src/chatwidget/tests.rs` | 测试代码，包含 snapshot 测试 |
| `codex-rs/tui/src/status_indicator_widget.rs` | 状态指示器组件 |
| `codex-rs/tui/src/bottom_pane/mod.rs` | 底部面板，包含状态指示器容器 |

### 关键函数

| 函数 | 位置 | 职责 |
|-----|------|------|
| `begin_unified_exec_startup` | `tests.rs:3506` | 测试辅助函数，启动统一执行 |
| `terminal_interaction` | `tests.rs` | 模拟终端交互事件 |
| `render_bottom_popup` | `tests.rs:6661` | 渲染底部弹出框并返回字符串 |
| `on_terminal_interaction` | `chatwidget.rs:2661` | 处理终端交互事件 |
| `flush_unified_exec_wait_streak` | `chatwidget.rs:1102` | 刷新等待状态到历史记录 |

### 相关协议类型

| 类型 | 定义位置 | 说明 |
|-----|---------|------|
| `ExecCommandSource` | `codex-protocol/src/protocol.rs` | 命令执行来源枚举 |
| `ExecCommandBeginEvent` | `codex-protocol/src/protocol.rs` | 命令开始事件 |
| `TerminalInteractionEvent` | `codex-protocol/src/protocol.rs` | 终端交互事件 |

---

## 依赖与外部交互

### 内部依赖

```
tui/src/chatwidget.rs
├── tui/src/bottom_pane/mod.rs
├── tui/src/status_indicator_widget.rs
├── tui/src/history_cell.rs
└── codex-protocol/src/protocol.rs
```

### 外部协议依赖

| 依赖 | 用途 |
|-----|------|
| `codex_protocol::protocol::ExecCommandSource` | 区分命令来源（UnifiedExecStartup/Interaction） |
| `codex_protocol::protocol::ExecCommandBeginEvent` | 命令开始事件数据 |
| `codex_protocol::protocol::TerminalInteractionEvent` | 终端交互事件数据 |

### 测试依赖

| 依赖 | 用途 |
|-----|------|
| `insta::assert_snapshot` | Snapshot 测试断言 |
| `VT100Backend` | 终端模拟后端 |
| `ratatui::Terminal` | TUI 渲染终端 |

---

## 风险、边界与改进建议

### 潜在风险

1. **命令截断导致信息丢失**
   - 长命令在单行显示时可能被截断，用户无法看到完整命令
   - **缓解**: 通过历史记录或详情视图提供完整命令查看

2. **状态指示器与历史记录竞争**
   - 多个并发统一执行进程可能导致状态显示混乱
   - **缓解**: `unified_exec_processes` 向量跟踪所有活动进程

3. **终端宽度变化**
   - 窄终端可能导致命令显示不完整
   - **缓解**: 测试使用固定宽度（48字符）验证行为

### 边界情况

| 场景 | 行为 |
|-----|------|
| 空命令 | 不显示详情行 |
| 极长命令 | 截断显示，保留可识别部分 |
| 多个等待进程 | 显示最近活动的进程 |
| 任务中断 | 清空等待状态，显示中断信息 |

### 改进建议

1. **添加工具提示（Tooltip）**
   - 当命令被截断时，允许用户悬停查看完整命令

2. **支持多进程显示**
   - 当前仅显示单个进程，可考虑显示进程数量

3. **优化命令显示**
   - 对于非常长的命令，显示首尾部分而非中间截断

4. **添加测试覆盖**
   - 添加不同宽度（80、120字符）的 snapshot 测试
   - 添加多进程并发等待的测试场景

---

## Snapshot 内容分析

```
• Waiting for background terminal (0s • esc to …
  └ cargo test -p codex-core -- --exact…


› Ask Codex to do anything

  ? for shortcuts            100% context left
```

**观察要点：**
1. 状态头部显示 "Waiting for background terminal" 和计时器
2. 详情行以树形结构（└）显示命令
3. 命令被截断（以 … 结尾）以适应宽度
4. 底部显示输入提示和快捷键帮助
