# 研究文档：探索步骤5 - 完成 sed 范围操作

## 场景与职责

本快照测试验证 Codex TUI 在"探索模式"(Exploring Mode)下的历史记录渲染行为。具体来说，这是测试探索模式第五步完成后的 UI 状态 - 当执行 `sed -n 100,200p foo.txt` 命令完成后，系统如何将其归类并与之前的探索操作一起显示。

**探索模式**是 Codex 的一种智能命令分组机制，用于将相关的文件读取、列表和搜索操作聚合在一起显示，而不是作为独立的命令历史项分散显示。

## 功能点目的

1. **智能命令分组**：将 `ls -la`、`cat foo.txt`、`sed` 范围读取等探索性命令归类为"Explored"组
2. **文件操作追踪**：识别并记录对同一文件（foo.txt）的多次读取操作
3. **历史记录压缩**：避免历史记录被大量单独的文件探索命令填满
4. **视觉层次展示**：使用树形结构展示探索组内的操作序列

## 具体技术实现

### 核心数据结构

```rust
// exec_cell/model.rs
pub(crate) struct ExecCell {
    pub(crate) calls: Vec<ExecCall>,
    animations_enabled: bool,
}

pub(crate) struct ExecCall {
    pub(crate) call_id: String,
    pub(crate) command: Vec<String>,
    pub(crate) parsed: Vec<ParsedCommand>,
    pub(crate) source: ExecCommandSource,
    // ...
}
```

### 探索模式判定逻辑

```rust
// exec_cell/model.rs
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

### 测试流程（来自 tests.rs）

```rust
// 5) Start & complete "sed -n 100,200p foo.txt" (treated as Read of foo.txt)
let begin_sed_range = begin_exec(&mut chat, "call-sed-range", "sed -n 100,200p foo.txt");
end_exec(&mut chat, begin_sed_range, "chunk", "", 0);
assert_snapshot!("exploring_step5_finish_sed_range", active_blob(&chat));
```

### 快照输出解析

```
• Explored
  └ List ls -la
    Read foo.txt
```

此时快照显示：
- `ls -la` 被识别为 `List` 操作
- `cat foo.txt` 和 `sed -n 100,200p foo.txt` 都被识别为对 `foo.txt` 的 `Read` 操作
- 但 `sed` 命令完成后，由于是对同一文件的读取，可能被合并显示或简化展示

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/exec_cell/model.rs` | ExecCell 和 ExecCall 数据结构，探索模式判定逻辑 |
| `codex-rs/tui/src/exec_cell/render.rs` | 探索单元格的渲染逻辑 |
| `codex-rs/tui/src/chatwidget/tests.rs` | 快照测试定义（约第 8211-8214 行） |
| `codex-rs/tui/src/history_cell.rs` | 历史记录单元格的通用接口 |
| `codex-rs/tui/src/chatwidget/snapshots/codex_tui__chatwidget__tests__exploring_step5_finish_sed_range.snap` | 本快照文件 |

### 相关测试函数

- `exec_history_extends_previous_when_consecutive()` - 完整的六步探索测试
- `begin_exec()` - 辅助函数，模拟开始执行命令
- `end_exec()` - 辅助函数，模拟完成命令执行
- `active_blob()` - 获取当前活动的探索 blob 显示内容

## 依赖与外部交互

### 依赖模块

1. **codex_protocol::parse_command::ParsedCommand**
   - 将原始命令解析为语义化的操作类型（Read/ListFiles/Search）
   - `sed -n 100,200p foo.txt` 被识别为对 foo.txt 的 Read 操作

2. **ExecCommandSource**
   - 区分命令来源（Agent vs UserShell）
   - 只有非 UserShell 的命令才参与探索模式分组

3. **ratatui**
   - 用于终端 UI 渲染

### 测试辅助设施

```rust
// 测试中使用的主要辅助函数
fn begin_exec(chat: &mut ChatWidget, call_id: &str, command: &str) -> String
fn end_exec(chat: &mut ChatWidget, call_id: String, stdout: &str, stderr: &str, exit_code: i32)
fn active_blob(chat: &ChatWidget) -> String
```

## 风险、边界与改进建议

### 潜在风险

1. **命令解析准确性**
   - `sed -n 100,200p foo.txt` 必须被正确识别为读取 foo.txt
   - 如果解析逻辑有误，可能导致文件操作追踪不准确

2. **同一文件多次读取的显示策略**
   - 当前快照显示 `Read foo.txt` 只出现一次
   - 需要确认这是合并显示还是简化展示的预期行为

3. **探索模式边界判定**
   - 复杂的管道命令或组合命令可能无法正确归类
   - 用户通过 shell 执行的探索命令（UserShell 源）不会被分组

### 边界情况

| 场景 | 预期行为 |
|------|---------|
| 长时间运行的探索命令 | 显示为活跃状态，有动画指示器 |
| 探索命令失败 | 应保留在历史记录中，可能带有错误标记 |
| 混合探索与非探索命令 | 非探索命令会中断探索组，创建新的历史项 |
| 同一文件多次不同操作 | 需要明确定义是合并显示还是分别显示 |

### 改进建议

1. **增强测试覆盖**
   - 添加对失败探索命令的快照测试
   - 测试探索模式与非探索命令交替执行的场景
   - 验证同一文件多次读取的显示策略

2. **可视化改进**
   - 考虑在探索组内显示每个操作的完成状态
   - 对于 `sed` 范围读取，可考虑显示读取的行范围信息

3. **文档完善**
   - 在代码中添加更多注释说明探索模式的判定规则
   - 明确 `sed` 等复杂命令的解析逻辑

4. **性能考虑**
   - 对于大量探索操作的长会话，确保历史记录渲染性能
   - 考虑探索组的折叠/展开功能
