# exit-confirmation-prompt-design.md 研究文档

## 场景与职责

exit-confirmation-prompt-design.md 是 Codex CLI 项目中关于 TUI（终端用户界面）退出、关闭和中断流程的设计文档。该文档详细描述了 Rust TUI (`codex-rs/tui`) 中退出机制的设计决策、事件模型和用户交互流程。

**适用场景：**
- TUI 开发者需要理解退出流程的实现
- 需要修改或扩展退出相关功能的开发者
- 调试退出相关问题的维护者

## 功能点目的

### 1. 术语定义
- **Exit（退出）**：结束 UI 事件循环并终止进程
- **Shutdown（关闭）**：请求优雅的 agent/core 关闭 (`Op::Shutdown`) 并等待 `ShutdownComplete` 以便执行清理
- **Interrupt（中断）**：取消正在运行的操作 (`Op::Interrupt`)

### 2. 事件模型（AppEvent）
通过单一事件协调退出，具有显式模式：

**ExitMode::ShutdownFirst**
- 优先用于用户发起的退出，以便执行清理

**ExitMode::Immediate**
- 立即退出的逃生舱口
- 绕过关闭，可能丢弃正在进行的工作（如任务、rollout flush、子进程清理）

**协调器**：`App` 负责提交 `Op::Shutdown`，仅在收到 `ExitMode::Immediate` 时退出 UI 循环（通常在 `ShutdownComplete` 之后）

### 3. 用户触发的退出流程

#### Ctrl+C 处理优先级
1. **活动模态/视图优先** (`BottomPane::on_ctrl_c`)
   - 如果模态处理了事件，退出流程停止
   - 当模态/弹出窗口处理 Ctrl+C 时，退出快捷键被清除，防止意外触发后续退出

2. **双击检测**
   - 如果用户已触发 Ctrl+C 且 1 秒窗口未过期，第二次 Ctrl+C 立即触发 shutdown-first 退出

3. **首次触发**
   - `ChatWidget` 激活 Ctrl+C 并显示退出提示（`ctrl + c again to quit`）1 秒

4. **可取消工作**
   - 如果有可取消的工作正在进行（streaming/tools/review），`ChatWidget` 提交 `Op::Interrupt`

#### Ctrl+D 处理
- **条件**：仅在 composer 为空**且**没有活动模态时参与退出
  - 首次按下显示退出提示（同 Ctrl+C）并启动 1 秒计时器
  - 如果提示可见时再次按下，请求 shutdown-first 退出
- **模态打开时**：键事件路由到视图，Ctrl+D 不尝试退出

#### Slash 命令
- `/quit`, `/exit`, `/logout` 请求 shutdown-first 退出**无需提示**
- 原因：slash 命令更难意外触发，且明确表示退出意图

#### /new 命令
- 使用 shutdown 而不退出（抑制 `ShutdownComplete`）
- 应用可以在不终止的情况下启动新会话

### 4. 关闭完成和抑制
`ShutdownComplete` 是 core 清理完成的信号，UI 将其视为退出的边界：

- `ChatWidget` 在 `ShutdownComplete` 时请求 `Exit(Immediate)`
- `App` 可以在 shutdown 用作清理步骤时抑制单个 `ShutdownComplete`（例如 `/new`）

### 5. 边界情况和不变量
- **Review 模式**被视为可取消的工作，Ctrl+C 应该中断 review 而不是退出
- **模态打开**意味着 Ctrl+C/Ctrl+D 不应该退出，除非模态明确拒绝处理 Ctrl+C
- **立即退出**不是正常的用户路径，它是 shutdown 完成或紧急退出的后备方案，应谨慎使用因为它跳过清理

### 6. 测试预期
最低测试覆盖要求：
- Ctrl+C 工作时中断，不退出
- Ctrl+C 空闲且为空时显示退出提示，然后第二次按下 shutdown-first 退出
- Ctrl+D 模态打开时不退出
- `/quit` / `/exit` / `/logout` 退出无需提示，但仍为 shutdown-first
- Ctrl+D 空闲且为空时显示退出提示，然后第二次按下 shutdown-first 退出

### 7. 历史背景
Codex 历史上在各种退出手势中混合了"立即退出"和"shutdown-first"，主要是由于增量更改和状态跟踪回归。本文档反映了当前统一的 shutdown-first 方法。详细历史和原理参见 PR #8936。

## 具体技术实现

### 事件流

```
用户按下 Ctrl+C
    ↓
检查活动模态
    ↓
如果有：传递给模态处理
    ↓
如果模态处理：停止
    ↓
检查是否已激活（1 秒内）
    ↓
如果是：触发 Exit(ShutdownFirst)
    ↓
如果否：激活并显示提示
    ↓
检查可取消工作
    ↓
如果有：提交 Op::Interrupt
    ↓
等待 ShutdownComplete
    ↓
触发 Exit(Immediate)
    ↓
终止进程
```

### 状态机

```
[Idle] --Ctrl+C--> [Armed] --1s timeout--> [Idle]
                      |
                      --Second Ctrl+C--> [Exiting]
                      |
                      --Interrupt--> [Interrupting]
```

## 关键代码路径与文件引用

### 相关文件位置

| 文件路径 | 说明 |
|---------|------|
| `/home/sansha/Github/codex/docs/exit-confirmation-prompt-design.md` | 本文档 |
| `/home/sansha/Github/codex/codex-rs/tui/src/app.rs` | App 协调器 |
| `/home/sansha/Github/codex/codex-rs/tui/src/bottom_pane/` | 底部面板，包含 composer |
| `/home/sansha/Github/codex/codex-rs/tui/src/chatwidget.rs` | ChatWidget 实现 |
| `/home/sansha/Github/codex/codex-rs/protocol/src/` | Op 定义（推测） |

### 关键类型和函数

**AppEvent 枚举**：
```rust
enum AppEvent {
    Exit(ExitMode),
    // ...
}

enum ExitMode {
    ShutdownFirst,
    Immediate,
}
```

**关键函数**：
- `BottomPane::on_ctrl_c()` - 处理 Ctrl+C
- `ChatWidget::handle_ctrl_c()` - ChatWidget 的 Ctrl+C 处理
- `App::handle_shutdown_complete()` - 处理关闭完成

## 依赖与外部交互

### 内部依赖

1. **Core 模块**
   - `Op::Shutdown` 操作
   - `Op::Interrupt` 操作
   - `ShutdownComplete` 事件

2. **TUI 组件**
   - `BottomPane` - 底部面板
   - `ChatWidget` - 聊天组件
   - 模态系统

3. **定时器**
   - 1 秒双击检测窗口

### 外部依赖

1. **crossterm**
   - 终端事件处理
   - 键码定义

## 风险、边界与改进建议

### 潜在风险

1. **状态不一致**
   - 复杂的退出状态机可能导致状态不一致
   - 建议：添加状态机不变量检查和断言

2. **清理失败**
   - 如果 shutdown 清理挂起，用户可能无法退出
   - 建议：添加 shutdown 超时机制

3. **意外退出**
   - 快速双击可能意外触发退出
   - 建议：考虑增加确认提示或延长窗口时间

### 边界情况

1. **信号中断**
   - 如何处理 SIGTERM、SIGINT 信号

2. **子进程**
   - 子进程在退出时的清理

3. **网络操作**
   - 正在进行的网络请求如何处理

4. **文件操作**
   - 未完成的文件写入如何确保完整性

### 改进建议

1. **可配置超时**
   - 允许用户配置双击窗口时间
   - 允许配置 shutdown 超时

2. **退出确认**
   - 对于重要操作，添加显式确认
   - 提供"强制退出"选项

3. **状态保存**
   - 在退出前自动保存对话状态
   - 支持会话恢复

4. **日志记录**
   - 记录退出流程的详细日志
   - 便于调试退出相关问题

5. **测试覆盖**
   - 添加更多边界情况的测试
   - 模拟各种退出场景

6. **文档改进**
   - 添加流程图
   - 提供调试指南
