# events.rs 研究文档

## 场景与职责

`events.rs` 是 Codex 工具系统的事件发射模块，负责将工具执行过程中的关键事件（开始、结束、成功、失败）发送到事件总线。它是连接工具执行层和 UI/遥测层的桥梁，支持以下工具类型的事件发射：

1. **Shell 命令执行**：标准 shell 工具调用
2. **Patch 应用**：代码补丁应用工具
3. **Unified Exec**：统一执行命令（支持会话保持）

该模块实现了类型安全的事件发射器，避免了 trait 对象和装箱 future 的开销。

## 功能点目的

### 1. 工具事件上下文 (`ToolEventCtx`)
封装事件发射所需的上下文信息：
- 会话和 Turn 上下文
- 调用 ID
- Turn 差异追踪器（用于 patch 工具）

### 2. 工具事件阶段 (`ToolEventStage`)
定义工具执行的生命周期阶段：
- `Begin`：开始执行
- `Success(ExecToolCallOutput)`：成功完成
- `Failure(ToolEventFailure)`：执行失败

### 3. 工具事件失败类型 (`ToolEventFailure`)
定义失败的具体类型：
- `Output(ExecToolCallOutput)`：有输出的失败（如非零退出码）
- `Message(String)`：纯消息失败（如执行错误）
- `Rejected(String)`：用户拒绝

### 4. 工具发射器枚举 (`ToolEmitter`)
类型安全的事件发射器，避免 trait 对象：
- `Shell`：Shell 命令发射器
- `ApplyPatch`：Patch 应用发射器
- `UnifiedExec`：统一执行发射器

### 5. 事件发射方法
- `emit()`：发射指定阶段的事件
- `begin()`：发射开始事件
- `finish()`：处理执行结果并发射完成事件

## 具体技术实现

### 关键数据结构

```rust
// 工具事件上下文
#[derive(Clone, Copy)]
pub(crate) struct ToolEventCtx<'a> {
    pub session: &'a Session,
    pub turn: &'a TurnContext,
    pub call_id: &'a str,
    pub turn_diff_tracker: Option<&'a SharedTurnDiffTracker>,
}

// 工具事件阶段
pub(crate) enum ToolEventStage {
    Begin,
    Success(ExecToolCallOutput),
    Failure(ToolEventFailure),
}

// 工具事件失败类型
pub(crate) enum ToolEventFailure {
    Output(ExecToolCallOutput),
    Message(String),
    Rejected(String),
}

// 工具发射器（无 trait 对象，无装箱）
pub(crate) enum ToolEmitter {
    Shell {
        command: Vec<String>,
        cwd: PathBuf,
        source: ExecCommandSource,
        parsed_cmd: Vec<ParsedCommand>,
        freeform: bool,
    },
    ApplyPatch {
        changes: HashMap<PathBuf, FileChange>,
        auto_approved: bool,
    },
    UnifiedExec {
        command: Vec<String>,
        cwd: PathBuf,
        source: ExecCommandSource,
        parsed_cmd: Vec<ParsedCommand>,
        process_id: Option<String>,
    },
}
```

### 核心流程

#### 1. Shell 命令事件发射流程
```rust
// 创建发射器
let emitter = ToolEmitter::shell(command, cwd, source, freeform);

// 发射开始事件
emitter.begin(ctx).await;

// 执行命令...

// 处理结果并发射完成事件
emitter.finish(ctx, result).await;
```

发射的事件：
- `ExecCommandBeginEvent`：包含命令、工作目录、解析后的命令、来源
- `ExecCommandEndEvent`：包含 stdout、stderr、退出码、执行时间、状态

#### 2. Patch 应用事件发射流程
```rust
// 创建发射器
let emitter = ToolEmitter::apply_patch(changes, auto_approved);

// 发射开始事件
emitter.begin(ctx).await;
// 触发：PatchApplyBeginEvent
// 同时更新 TurnDiffTracker

// 应用补丁...

// 发射完成事件
emitter.finish(ctx, result).await;
// 触发：PatchApplyEndEvent
// 成功后发送 TurnDiffEvent（统一差异）
```

#### 3. Unified Exec 事件发射流程
```rust
// 创建发射器
let emitter = ToolEmitter::unified_exec(command, cwd, source, process_id);

// 发射开始/完成事件
emitter.begin(ctx).await;
emitter.finish(ctx, result).await;
```

#### 4. 结果处理流程 (`finish` 方法)
```rust
pub async fn finish(
    &self,
    ctx: ToolEventCtx<'_>,
    out: Result<ExecToolCallOutput, ToolError>,
) -> Result<String, FunctionCallError> {
    match out {
        Ok(output) => {
            // 格式化输出
            // 发射 Success 事件
            // 根据 exit_code 返回 Ok 或 Err
        }
        Err(ToolError::Codex(CodexErr::Sandbox(SandboxErr::Timeout { output })))
        | Err(ToolError::Codex(CodexErr::Sandbox(SandboxErr::Denied { output, .. }))) => {
            // 格式化输出
            // 发射 Failure::Output 事件
            // 返回 RespondToModel 错误
        }
        Err(ToolError::Codex(err)) => {
            // 发射 Failure::Message 事件
            // 返回 RespondToModel 错误
        }
        Err(ToolError::Rejected(msg)) => {
            // 规范化拒绝消息
            // 发射 Failure::Rejected 事件
            // 返回 RespondToModel 错误
        }
    }
}
```

### 拒绝消息规范化
```rust
let normalized = if msg == "rejected by user" {
    match self {
        Self::Shell { .. } | Self::UnifiedExec { .. } => {
            "exec command rejected by user".to_string()
        }
        Self::ApplyPatch { .. } => "patch rejected by user".to_string(),
    }
} else {
    msg
};
```

### 关键代码路径

| 类型/函数 | 行号 | 职责 |
|-----------|------|------|
| `ToolEventCtx` | 28-50 | 事件上下文结构 |
| `ToolEventStage` | 52-56 | 事件阶段枚举 |
| `ToolEventFailure` | 58-62 | 失败类型枚举 |
| `ToolEmitter` | 89-109 | 发射器枚举定义 |
| `ToolEmitter::shell` | 111-126 | 创建 Shell 发射器 |
| `ToolEmitter::apply_patch` | 128-133 | 创建 Patch 发射器 |
| `ToolEmitter::unified_exec` | 135-149 | 创建 UnifiedExec 发射器 |
| `ToolEmitter::emit` | 151-287 | 主发射逻辑（匹配不同类型和阶段）|
| `ToolEmitter::begin` | 289-291 | 便捷方法：发射开始事件 |
| `ToolEmitter::finish` | 306-363 | 处理结果并发射完成事件 |
| `emit_exec_command_begin` | 64-88 | 发射 ExecCommandBegin 事件 |
| `emit_exec_stage` | 405-467 | 执行阶段事件发射 |
| `emit_exec_end` | 469-496 | 发射 ExecCommandEnd 事件 |
| `emit_patch_end` | 498-532 | 发射 PatchApplyEnd 和 TurnDiff 事件 |

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::codex::{Session, TurnContext}` | 会话和 Turn 上下文 |
| `crate::error::{CodexErr, SandboxErr}` | 错误类型 |
| `crate::exec::ExecToolCallOutput` | 执行输出类型 |
| `crate::function_tool::FunctionCallError` | 函数调用错误 |
| `crate::parse_command::parse_command` | 命令解析 |
| `crate::protocol::*` | 协议事件类型 |
| `crate::tools::context::SharedTurnDiffTracker` | 差异追踪器 |
| `crate::tools::sandboxing::ToolError` | 工具错误类型 |

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_protocol::parse_command::ParsedCommand` | 解析后的命令类型 |
| `std::collections::HashMap` | 变更映射 |
| `std::path::{Path, PathBuf}` | 路径处理 |
| `std::time::Duration` | 持续时间 |

### 调用关系

```
工具运行时 (orchestrator.rs / runtimes/)
    └── ToolEmitter::shell/apply_patch/unified_exec
        ├── ToolEmitter::begin
        │   └── emit_exec_stage / PatchApplyBeginEvent
        ├── 执行工具...
        └── ToolEmitter::finish
            ├── emit_exec_stage (Success/Failure)
            └── emit_patch_end (ApplyPatch)
                └── TurnDiffEvent
```

## 风险、边界与改进建议

### 已知风险

1. **消息规范化 TODO**
   ```rust
   // TODO: We should add a new ToolError variant for user-declined approvals.
   ```
   当前 `ToolError::Rejected` 同时用于用户拒绝和操作失败，需要区分。

2. **TurnDiffTracker 锁持有**
   ```rust
   let mut guard = tracker.lock().await;
   guard.on_patch_begin(changes);
   ```
   锁在 await 点持有，如果 `on_patch_begin` 耗时可能影响并发。

3. **硬编码消息字符串**
   ```rust
   if msg == "rejected by user" { ... }
   ```
   依赖具体字符串值，容易因修改而失效。

### 边界情况

| 场景 | 处理方式 |
|------|----------|
| 无 TurnDiffTracker | Patch 开始事件正常发射，但不记录差异 |
| 退出码为 0 | 视为成功，返回 `Ok(content)` |
| 退出码非 0 | 视为失败，返回 `Err(FunctionCallError::RespondToModel(...))` |
| Sandbox 超时 | 格式化输出并返回 RespondToModel 错误 |
| Sandbox 拒绝 | 同上 |
| 执行错误 | 发射 Message 失败事件 |
| 用户拒绝 | 规范化消息并发射 Rejected 事件 |

### 改进建议

1. **区分拒绝类型**
   ```rust
   pub(crate) enum ToolError {
       RejectedByUser { message: String },
       OperationFailed { message: String },
       Codex(CodexErr),
   }
   ```

2. **使用常量替代硬编码字符串**
   ```rust
   pub const REJECTED_BY_USER_MESSAGE: &str = "rejected by user";
   ```

3. **优化锁使用**
   ```rust
   // 当前
   let mut guard = tracker.lock().await;
   guard.on_patch_begin(changes);
   
   // 建议：如果 on_patch_begin 不跨越 await
   {
       let mut guard = tracker.lock().await;
       guard.on_patch_begin(changes);
   } // 锁在这里释放
   ```

4. **添加事件批量发射**
   ```rust
   impl ToolEmitter {
       pub async fn emit_batch(&self, ctx: ToolEventCtx<'_>, stages: Vec<ToolEventStage>) {
           for stage in stages {
               self.emit(ctx, stage).await;
           }
       }
   }
   ```

5. **添加事件过滤**
   ```rust
   pub(crate) struct EventFilter {
       pub include_stdout: bool,
       pub include_stderr: bool,
       pub max_event_size: usize,
   }
   ```

6. **改进错误消息**
   ```rust
   // 当前：简单字符串匹配
   let normalized = if msg == "rejected by user" { ... }
   
   // 建议：结构化错误代码
   if msg.contains("rejected") && msg.contains("user") { ... }
   ```

7. **添加测试覆盖**
   - 当前 `events.rs` 没有对应的测试文件
   - 建议添加 `events_tests.rs` 测试各种事件发射场景

### 设计决策说明

1. **为何使用枚举而非 trait**
   - 避免 trait 对象的开销（虚表查找、装箱）
   - 编译期确定所有可能的工具类型
   - 更好的性能（内联友好）

2. **为何分离 `emit` 和 `finish`**
   - `emit` 处理原始阶段事件
   - `finish` 处理结果转换和错误映射
   - 职责分离，便于测试

3. **为何 Patch 特殊处理 TurnDiff**
   - Patch 工具需要生成统一差异视图
   - 差异信息需要在所有 patch 完成后汇总
   - 通过 `TurnDiffTracker` 跨多次调用保持状态
