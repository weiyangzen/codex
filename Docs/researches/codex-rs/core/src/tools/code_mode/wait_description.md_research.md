# wait_description.md 研究文档

## 场景与职责

`wait_description.md` 是 Code Mode **`wait` 工具的文档模板**，用于向模型描述 `wait` 工具的功能和使用方式。它是 `description.md` 的配套文档，专门用于处理长时间运行的 `exec` 执行。

**核心定位**：
- 说明 `wait` 工具的使用前提（必须在 `exec` 返回运行状态后使用）
- 描述 `wait` 工具的参数和行为
- 解释 `wait` 与 `exec` 的协作关系

## 功能点目的

### 1. 使用前提说明
```markdown
- Use `wait` only after `exec` returns `Script running with cell ID ...`.
```
- 明确告知模型 `wait` 工具的使用时机
- 防止模型在不适当的时候调用 `wait`

### 2. Cell ID 说明
```markdown
- `cell_id` identifies the running `exec` cell to resume.
```
- 解释 `cell_id` 的用途：标识要恢复的执行单元
- 与 `exec` 返回的 "Script running with cell ID ..." 对应

### 3. 轮询参数说明
```markdown
- `yield_time_ms` controls how long to wait for more output before yielding again.
  If omitted, `wait` uses its default wait timeout.
- `max_tokens` limits how much new output this wait call returns.
```
- `yield_time_ms`：控制轮询间隔，等待新输出的时间
- `max_tokens`：限制返回的输出量

### 4. 终止功能说明
```markdown
- `terminate: true` stops the running cell instead of waiting for more output.
```
- 说明 `terminate` 参数的特殊用途：强制终止执行
- 这是处理失控脚本的重要手段

### 5. 输出语义说明
```markdown
- `wait` returns only the new output since the last yield, or the final completion
  or termination result for that cell.
- If the cell is still running, `wait` may yield again with the same `cell_id`.
- If the cell has already finished, `wait` returns the completed result and closes the cell.
```
- 增量输出：只返回自上次让出以来的新输出
- 重复让出：如果 cell 仍在运行，可能再次让出
- 完成处理：如果 cell 已完成，返回最终结果并关闭 cell

## 具体技术实现

### 文档结构
```markdown
wait_description.md
├── 使用前提（必须在 exec 返回运行状态后使用）
├── cell_id 参数说明
├── yield_time_ms 参数说明
├── max_tokens 参数说明
├── terminate 参数说明
└── 输出语义说明
    ├── 增量输出
    ├── 重复让出
    └── 完成处理
```

### 在代码中的使用

**mod.rs 中的常量定义**（第 36 行）：
```rust
const CODE_MODE_WAIT_DESCRIPTION_TEMPLATE: &str = include_str!("wait_description.md");
```

**wait_tool_description 函数**（第 101-103 行）：
```rust
pub(crate) fn wait_tool_description() -> &'static str {
    CODE_MODE_WAIT_DESCRIPTION_TEMPLATE
}
```

### 与 wait_handler.rs 的对应关系

| 文档描述 | 代码实现 |
|---------|---------|
| `cell_id` 标识 cell | `ExecWaitArgs::cell_id: String` |
| `yield_time_ms` 控制等待时间 | `ExecWaitArgs::yield_time_ms: u64` |
| `max_tokens` 限制输出 | `ExecWaitArgs::max_tokens: Option<usize>` |
| `terminate: true` 终止 cell | `HostToNodeMessage::Terminate` |
| 返回新输出 | `handle_node_message` 处理 `Yielded` 和 `Result` |
| cell 完成时关闭 | `completeSession` 从 sessions 中删除 |

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/wait_description.md`

### 调用方
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/mod.rs`
  - `wait_tool_description()` 函数返回此模板内容
  - 常量 `CODE_MODE_WAIT_DESCRIPTION_TEMPLATE` 嵌入此文件

### 相关文件
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/description.md` - `exec` 工具的文档模板
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/wait_handler.rs` - `wait` 工具的实现

### 数据流
```
wait_description.md
    │
    ├──> mod.rs:CODE_MODE_WAIT_DESCRIPTION_TEMPLATE (编译时嵌入)
    │
    ├──> mod.rs:wait_tool_description() (返回描述)
    │
    └──> 最终作为 wait 工具的 description 提供给模型
```

## 依赖与外部交互

### 输入依赖
| 来源 | 数据 | 说明 |
|------|------|------|
| 编译时 | 文件内容 | 通过 `include_str!` 嵌入 |

### 输出使用
| 目标 | 数据 | 说明 |
|------|------|------|
| 模型 | 工具描述 | 作为 system prompt 的一部分 |
| ToolSpec | description 字段 | `wait` 工具的元数据描述 |

### 与 runner.cjs 的对应关系
- 文档中描述的 `yield_time_ms` 对应 `runner.cjs` 中的 `schedulePollYield`
- 文档中描述的 `terminate` 对应 `runner.cjs` 中的 `terminateSession`
- 文档中描述的 "cell 完成时关闭" 对应 `runner.cjs` 中的 `sessions.delete(session.id)`

## 风险、边界与改进建议

### 风险点

1. **文档与实现不同步**
   - `wait_description.md` 描述的行为必须与 `wait_handler.rs` 和 `runner.cjs` 保持一致
   - 如果修改了实现而忘记更新文档，模型会得到错误信息

2. **使用时机不明确**
   - 文档说明 "Use `wait` only after `exec` returns `Script running with cell ID ...`"
   - 但模型可能不理解这个前提条件，或在错误时机调用

3. **Token 开销**
   - 文档内容虽短，但仍增加每次请求的 token 数量
   - 如果模型很少使用 `wait`，这部分开销是浪费的

### 边界情况

1. **文档未覆盖的错误场景**
   - 如果 `cell_id` 不存在，`wait` 会返回错误
   - 如果 cell 已经被终止，再次 `wait` 会返回错误
   - 这些边界情况在文档中未明确说明

2. **参数组合**
   - `terminate: true` 与 `yield_time_ms` 的组合行为
   - 文档未说明 `terminate: true` 时是否忽略 `yield_time_ms`

### 改进建议

1. **添加错误场景说明**
   ```markdown
   - If the `cell_id` is not found or the cell has already finished, `wait` returns an error.
   - If `terminate: true` is specified, `yield_time_ms` and `max_tokens` are ignored.
   ```

2. **添加使用示例**
   ```markdown
   Example usage:
   1. Call `exec` with long-running code
   2. If `exec` returns "Script running with cell ID 123", call `wait` with `{"cell_id": "123"}`
   3. If `wait` returns "Script running with cell ID 123", repeat step 2
   4. If `wait` returns completion or termination result, the cell is closed
   ```

3. **与 exec 文档的交叉引用**
   - 在 `description.md` 中添加对 `wait` 的引用
   - 在 `wait_description.md` 中添加对 `exec` 的引用

4. **版本控制**
   - 添加版本号，便于追踪文档与实现的兼容性

5. **参数默认值说明**
   ```markdown
   - `yield_time_ms`: defaults to 10000ms (10 seconds)
   - `max_tokens`: defaults to no limit
   ```

6. **合并到 description.md**
   - 考虑将 `wait` 的说明合并到 `description.md`
   - 减少文件数量，便于维护
