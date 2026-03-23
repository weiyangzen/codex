# exec_cell/model.rs 研究文档

## 场景与职责

`exec_cell/model.rs` 定义了 TUI 中命令执行历史单元格的核心数据模型。该模块负责：

1. **命令执行状态管理**：跟踪单个命令调用（`ExecCall`）从启动到完成的完整生命周期
2. **探索模式聚合**：将多个相关的轻量级命令（Read/ListFiles/Search）自动分组为"探索单元格"（Exploring Cell），减少界面视觉噪音
3. **输出数据封装**：管理命令的标准输出、标准错误以及格式化后的模型可见输出

在 Codex TUI 的交互流程中，当 Agent 执行命令时：
- `ExecCommandBeginEvent` → 创建 `ExecCall` → 包装为 `ExecCell`
- 输出流 → `append_output()` 更新状态
- `ExecCommandEndEvent` → `complete_call()` 标记完成
- UI 渲染 → 根据 `is_exploring_cell()` 决定展示方式

## 功能点目的

### CommandOutput

```rust
#[derive(Clone, Debug, Default)]
pub(crate) struct CommandOutput {
    pub(crate) exit_code: i32,
    pub(crate) aggregated_output: String,  // stderr + stdout 交错聚合
    pub(crate) formatted_output: String,   // 模型可见的格式化输出
}
```

**设计意图**：
- 区分原始聚合输出与格式化输出，支持不同消费场景
- `aggregated_output` 用于 TUI 显示，`formatted_output` 用于模型上下文

### ExecCall

```rust
#[derive(Debug, Clone)]
pub(crate) struct ExecCall {
    pub(crate) call_id: String,
    pub(crate) command: Vec<String>,
    pub(crate) parsed: Vec<ParsedCommand>,
    pub(crate) output: Option<CommandOutput>,
    pub(crate) source: ExecCommandSource,
    pub(crate) start_time: Option<Instant>,
    pub(crate) duration: Option<Duration>,
    pub(crate) interaction_input: Option<String>,
}
```

**字段说明**：

| 字段 | 类型 | 用途 |
|------|------|------|
| `call_id` | `String` | 唯一标识，用于事件路由匹配 |
| `command` | `Vec<String>` | 原始命令参数（如 `["bash", "-lc", "echo hi"]`）|
| `parsed` | `Vec<ParsedCommand>` | 语义化解析结果（Read/ListFiles/Search/Unknown）|
| `output` | `Option<CommandOutput>` | `None` 表示执行中， `Some` 表示已完成 |
| `source` | `ExecCommandSource` | 命令来源（Agent/UserShell/UnifiedExec*）|
| `start_time` | `Option<Instant>` | 执行开始时间，用于计算持续时间 |
| `duration` | `Option<Duration>` | 执行耗时，完成时设置 |
| `interaction_input` | `Option<String>` | 统一执行交互模式的输入数据 |

### ExecCell

```rust
#[derive(Debug)]
pub(crate) struct ExecCell {
    pub(crate) calls: Vec<ExecCall>,
    animations_enabled: bool,
}
```

**核心能力**：
- 单命令模式：包含一个 `ExecCall`，显示详细命令和输出
- 探索模式：包含多个同类型轻量级命令，聚合显示为"Exploring/Explored"

## 具体技术实现

### 探索模式判定逻辑

```rust
pub(super) fn is_exploring_call(call: &ExecCall) -> bool {
    !matches!(call.source, ExecCommandSource::UserShell)
        && !call.parsed.is_empty()
        && call.parsed.iter().all(|p| {
            matches!(
                p,
                ParsedCommand::Read { .. }
                    | ParsedCommand::ListFiles { .. }
                    | ParsedCommand::Search { .. }
            )
        })
}
```

**判定条件**（需同时满足）：
1. 来源不是 `UserShell`（用户直接执行的命令单独显示）
2. 解析结果非空（有明确的语义化命令）
3. 所有解析结果都是探索类命令（Read/ListFiles/Search）

### 命令追加机制

```rust
pub(crate) fn with_added_call(
    &self,
    call_id: String,
    command: Vec<String>,
    parsed: Vec<ParsedCommand>,
    source: ExecCommandSource,
    interaction_input: Option<String>,
) -> Option<Self>
```

**逻辑流程**：
1. 检查当前单元格是否为探索模式（`is_exploring_cell()`）
2. 检查新调用是否为探索类型（`is_exploring_call()`）
3. 仅当两者都为 true 时，才返回包含追加调用的新单元格
4. 否则返回 `None`，调用方应创建新单元格

**设计考量**：此设计避免了不同类型命令的意外聚合，确保用户执行的 Shell 命令始终独立显示。

### 完成状态管理

```rust
pub(crate) fn complete_call(
    &mut self,
    call_id: &str,
    output: CommandOutput,
    duration: Duration,
) -> bool
```

**关键实现细节**：
- 使用 `iter_mut().rev()` 从后向前查找匹配（支持同一 call_id 的重复调用场景）
- 返回 `bool` 表示是否找到匹配，调用方据此处理"孤儿事件"
- 完成后清除 `start_time`，设置 `duration`

### 刷新策略

```rust
pub(crate) fn should_flush(&self) -> bool {
    !self.is_exploring_cell() && self.calls.iter().all(|c| c.output.is_some())
}
```

非探索模式的单元格在所有调用完成后应立即刷新（从活跃区移入历史区）。

### 失败标记

```rust
pub(crate) fn mark_failed(&mut self)
```

当连接中断或会话异常结束时调用，为所有未完成调用设置失败状态：
- 退出码设为 1
- 根据已耗时计算 duration
- 清空输出内容

## 关键代码路径与文件引用

### 创建流程

```
app.rs 接收 ExecCommandBeginEvent
    ↓
render::new_active_exec_command() 创建 ExecCall
    ↓
ExecCell::new(call, animations_enabled) 包装为单元格
    ↓
插入活跃单元格列表
```

### 更新流程

```
app.rs 接收 ExecCommandOutputEvent
    ↓
ExecCell::append_output(call_id, chunk) 追加输出
    ↓
UI 重新渲染显示新输出
```

### 完成流程

```
app.rs 接收 ExecCommandEndEvent
    ↓
ExecCell::complete_call(call_id, output, duration)
    ↓
检查 should_flush() 决定是否移入历史
    ↓
UI 更新为完成状态（成功/失败指示）
```

### 探索模式聚合流程

```
已有活跃探索单元格
    ↓
收到新的探索类型命令
    ↓
with_added_call() 返回 Some(new_cell)
    ↓
替换活跃单元格，实现聚合显示
```

## 依赖与外部交互

### 外部类型依赖

| 来源 Crate | 类型 | 用途 |
|------------|------|------|
| `codex_protocol::parse_command` | `ParsedCommand` | 命令语义化解析结果 |
| `codex_protocol::protocol` | `ExecCommandSource` | 命令来源枚举 |
| `std::time` | `Instant`, `Duration` | 执行时间跟踪 |

### ExecCommandSource 枚举定义

```rust
pub enum ExecCommandSource {
    Agent,                  // Agent 发起的命令
    UserShell,             // 用户通过 Shell 执行的命令
    UnifiedExecStartup,    // 统一执行会话启动
    UnifiedExecInteraction, // 统一执行会话交互
}
```

### ParsedCommand 枚举定义

```rust
pub enum ParsedCommand {
    Read { cmd: String, name: String, path: PathBuf },
    ListFiles { cmd: String, path: Option<String> },
    Search { cmd: String, query: Option<String>, path: Option<String> },
    Unknown { cmd: String },
}
```

## 风险、边界与改进建议

### 当前风险

1. **call_id 匹配风险**：`complete_call` 和 `append_output` 使用反向查找，若存在重复 call_id 可能匹配到错误调用
   - 缓解：协议层保证 call_id 唯一性

2. **时间计算边界**：`mark_failed` 中 `start_time` 为 `None` 时回退到 0ms，可能丢失实际耗时信息
   - 建议：考虑记录事件到达时间作为备选

3. **探索模式误判**：`Unknown` 命令永远不会被判定为探索类型，可能导致预期外分组
   - 现状：这是设计决策，确保未知命令单独显示

### 边界情况

1. **空单元格**：`ExecCell::new` 要求至少一个调用，但 `calls` 字段为 `pub(crate)`，外部可构造空 Vec
   - 建议：添加构造函数验证或内部不变量断言

2. **长时间运行**：`start_time` 使用 `Instant`，不受系统时间调整影响，适合计时

3. **跨平台兼容性**：`Duration` 和 `Instant` 的行为在不同平台一致

### 改进建议

1. **类型安全增强**：
   ```rust
   // 考虑使用 newtype 模式包装 call_id
   pub struct CallId(String);
   ```

2. **不变量封装**：
   ```rust
   // 将 calls 设为私有，提供受控访问
   pub(crate) fn calls(&self) -> &[ExecCall] { &self.calls }
   ```

3. **错误信息丰富**：
   ```rust
   // complete_call 返回 Result 而非 bool
   pub enum CompleteError {
       CallNotFound,
       AlreadyCompleted,
   }
   ```

4. **探索模式可配置**：
   ```rust
   // 允许运行时配置探索命令类型
   pub struct ExploringConfig {
       include_unknown: bool,
       custom_predicates: Vec<Box<dyn Fn(&ParsedCommand) -> bool>>,
   }
   ```

5. **性能优化**：
   - `is_exploring_cell()` 每次调用都遍历所有 calls，对于大单元格可考虑缓存结果
   - `append_output` 的字符串追加可能导致多次重新分配，可考虑使用 `String::with_capacity` 预分配

### 测试建议

当前模块测试覆盖以下场景：
- 探索模式判定
- 命令完成状态转换
- 失败标记处理

建议补充：
- 边界条件：空 calls 向量处理
- 并发场景：同一 call_id 的快速连续更新
- 大输出场景：append_output 性能表现
