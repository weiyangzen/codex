# compact.rs 研究文档

## 场景与职责

`compact.rs` 实现了 **CompactTask**（对话压缩任务），用于处理 Codex 会话中的历史对话压缩功能。当对话历史变得过长、接近或超过模型上下文窗口限制时，系统会触发压缩操作，将历史对话总结为更紧凑的形式，以释放上下文空间。

### 主要使用场景
1. **手动压缩**：用户通过 `/compact` 命令主动触发对话压缩
2. **自动压缩**：当对话历史接近上下文窗口限制时自动触发
3. **远程压缩**：针对 OpenAI 提供商使用服务端压缩 API
4. **本地压缩**：使用本地模型进行对话总结和压缩

## 功能点目的

### 1. 双模式压缩支持
- **本地压缩** (`run_compact_task`)：使用本地模型流式处理对话历史，生成摘要
- **远程压缩** (`run_remote_compact_task`)：调用 OpenAI 的远程压缩 API，由服务端处理

### 2. 智能压缩策略
- 保留用户消息（非摘要消息）
- 生成对话摘要并作为用户消息插入历史
- 保留 GhostSnapshot 项目以支持 undo 功能
- 支持初始上下文注入控制（`InitialContextInjection` 枚举）

### 3. 压缩流程生命周期
- 发送 `TurnStarted` 事件通知客户端
- 调用压缩逻辑（本地或远程）
- 替换历史记录为压缩后的版本
- 重新计算 token 使用量

## 具体技术实现

### 关键数据结构

```rust
#[derive(Clone, Copy, Default)]
pub(crate) struct CompactTask;
```

- `CompactTask` 是一个零大小类型（ZST），实现了 `SessionTask` trait
- 使用 `TaskKind::Compact` 标识任务类型

### 核心流程

```rust
async fn run(
    self: Arc<Self>,
    session: Arc<SessionTaskContext>,
    ctx: Arc<TurnContext>,
    input: Vec<UserInput>,
    _cancellation_token: CancellationToken,
) -> Option<String>
```

**决策逻辑**：
1. 检查提供商类型：`crate::compact::should_use_remote_compact_task(&ctx.provider)`
2. OpenAI 提供商 → 使用远程压缩 (`run_remote_compact_task`)
3. 其他提供商 → 使用本地压缩 (`run_compact_task`)

### 依赖模块

| 模块 | 用途 |
|------|------|
| `crate::compact` | 本地压缩实现 (`run_compact_task`) |
| `crate::compact_remote` | 远程压缩实现 (`run_remote_compact_task`) |
| `crate::state::TaskKind` | 任务类型标识 |
| `codex_protocol::user_input::UserInput` | 用户输入类型 |

## 关键代码路径与文件引用

### 调用路径
```
codex.rs:4853-4866 (Session::compact)
  → spawn_task(Arc<CompactTask>)
    → tasks/mod.rs:148-227 (spawn_task implementation)
      → compact.rs:24-48 (CompactTask::run)
        → compact.rs:32-38 (remote path) OR compact.rs:39-46 (local path)
```

### 相关文件
- `codex-rs/core/src/compact.rs`：本地压缩实现（442行）
- `codex-rs/core/src/compact_remote.rs`：远程压缩实现（300行）
- `codex-rs/core/src/tasks/mod.rs`：任务框架和 `spawn_task`
- `codex-rs/core/src/codex.rs`：会话级 compact 入口

### 压缩模板文件
- `codex-rs/core/templates/compact/prompt.md`：压缩提示词模板
- `codex-rs/core/templates/compact/summary_prefix.md`：摘要前缀模板

## 依赖与外部交互

### 外部 crate 依赖
- `async_trait`：异步 trait 支持
- `tokio_util::sync::CancellationToken`：取消令牌
- `codex_protocol::user_input::UserInput`：协议层用户输入

### 内部模块交互
```
compact.rs
  ├── uses crate::compact::should_use_remote_compact_task
  ├── uses crate::compact::run_compact_task
  ├── uses crate::compact_remote::run_remote_compact_task
  ├── uses crate::state::TaskKind
  └── uses super::{SessionTask, SessionTaskContext}
```

### 遥测指标
压缩任务会记录以下指标：
- `codex.task.compact`：压缩任务计数器，标签区分 `type=remote` 或 `type=local`

## 风险、边界与改进建议

### 已知风险

1. **压缩失败处理**
   - 本地压缩在 `ContextWindowExceeded` 时会尝试裁剪最旧的历史项目
   - 如果仅剩一个项目仍超出窗口，会报错并设置 `total_tokens_full` 标志

2. **远程压缩依赖**
   - 远程压缩仅支持 OpenAI 提供商
   - 网络故障时需要重试逻辑（已实现指数退避）

3. **上下文丢失**
   - 压缩会丢失部分对话细节，仅保留摘要
   - 长线程和多次压缩可能导致模型准确性下降（有警告提示）

### 边界条件

| 边界条件 | 处理策略 |
|---------|---------|
| 空输入 | 使用默认压缩提示 |
| 取消令牌触发 | 优雅退出，不修改历史 |
| 流式错误 | 重试最多 `stream_max_retries` 次 |
| 上下文窗口超限 | 裁剪最旧项目后重试 |

### 改进建议

1. **压缩质量评估**
   - 添加压缩质量指标，监控摘要是否保留了关键信息
   - 考虑实现压缩后验证机制

2. **增量压缩**
   - 当前实现每次压缩整个历史，可考虑增量压缩策略
   - 仅压缩超过一定阈值的部分

3. **用户控制**
   - 提供压缩粒度选项（激进/保守）
   - 允许用户预览压缩结果后再确认

4. **错误恢复**
   - 压缩失败时应保留原始历史
   - 提供更详细的错误诊断信息
