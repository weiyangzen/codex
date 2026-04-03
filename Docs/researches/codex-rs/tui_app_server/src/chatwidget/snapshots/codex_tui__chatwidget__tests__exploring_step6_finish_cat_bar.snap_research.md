# 研究文档：探索步骤6 - 完成读取 bar.txt

## 场景与职责

本快照测试验证 Codex TUI 在"探索模式"(Exploring Mode)下的历史记录渲染行为。这是六步探索测试序列的最后一步，验证当执行 `cat bar.txt` 命令完成后，系统如何将其与之前的探索操作一起显示，特别是当读取不同文件时的展示方式。

**探索模式**是 Codex 的一种智能命令分组机制，用于将相关的文件读取、列表和搜索操作聚合在一起显示。

## 功能点目的

1. **多文件探索追踪**：验证系统能够追踪对不同文件（foo.txt 和 bar.txt）的读取操作
2. **探索组扩展**：验证新的探索操作能够正确添加到现有的探索组中
3. **文件列表展示**：验证多个文件的读取操作在历史记录中的展示格式
4. **探索序列完整性**：验证完整的探索流程（List → Read foo.txt → Read bar.txt）正确渲染

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
    pub(crate) output: Option<CommandOutput>,
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
// 完整的六步探索测试序列
async fn exec_history_extends_previous_when_consecutive() {
    // 1) Start "ls -la" (List)
    let begin_ls = begin_exec(&mut chat, "call-ls", "ls -la");
    assert_snapshot!("exploring_step1_start_ls", active_blob(&chat));

    // 2) Finish "ls -la"
    end_exec(&mut chat, begin_ls, "", "", 0);
    assert_snapshot!("exploring_step2_finish_ls", active_blob(&chat));

    // 3) Start "cat foo.txt" (Read)
    let begin_cat_foo = begin_exec(&mut chat, "call-cat-foo", "cat foo.txt");
    assert_snapshot!("exploring_step3_start_cat_foo", active_blob(&chat));

    // 4) Complete "cat foo.txt"
    end_exec(&mut chat, begin_cat_foo, "hello from foo", "", 0);
    assert_snapshot!("exploring_step4_finish_cat_foo", active_blob(&chat));

    // 5) Start & complete "sed -n 100,200p foo.txt" (treated as Read of foo.txt)
    let begin_sed_range = begin_exec(&mut chat, "call-sed-range", "sed -n 100,200p foo.txt");
    end_exec(&mut chat, begin_sed_range, "chunk", "", 0);
    assert_snapshot!("exploring_step5_finish_sed_range", active_blob(&chat));

    // 6) Start & complete "cat bar.txt"
    let begin_cat_bar = begin_exec(&mut chat, "call-cat-bar", "cat bar.txt");
    end_exec(&mut chat, begin_cat_bar, "hello from bar", "", 0);
    assert_snapshot!("exploring_step6_finish_cat_bar", active_blob(&chat));
}
```

### 快照输出解析

```
• Explored
  └ List ls -la
    Read foo.txt, bar.txt
```

此时快照显示：
- 所有探索命令被归类在 "Explored" 组下
- `ls -la` 显示为 `List` 操作
- `foo.txt` 和 `bar.txt` 的读取操作合并显示为 `Read foo.txt, bar.txt`
- 这展示了系统能够智能地将同一类型的文件操作合并展示

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/exec_cell/model.rs` | ExecCell 和 ExecCall 数据结构，探索模式判定逻辑 |
| `codex-rs/tui/src/exec_cell/render.rs` | 探索单元格的渲染逻辑，文件列表格式化 |
| `codex-rs/tui/src/chatwidget/tests.rs` | 快照测试定义（约第 8216-8219 行） |
| `codex-rs/tui/src/history_cell.rs` | 历史记录单元格的通用接口 |
| `codex-rs/tui/src/chatwidget/snapshots/codex_tui__chatwidget__tests__exploring_step6_finish_cat_bar.snap` | 本快照文件 |

### 相关测试函数

- `exec_history_extends_previous_when_consecutive()` - 完整的六步探索测试（约第 8192 行开始）
- `begin_exec()` - 辅助函数，模拟开始执行命令
- `end_exec()` - 辅助函数，模拟完成命令执行
- `active_blob()` - 获取当前活动的探索 blob 显示内容

## 依赖与外部交互

### 依赖模块

1. **codex_protocol::parse_command::ParsedCommand**
   - 将原始命令解析为语义化的操作类型
   - `cat foo.txt` 和 `cat bar.txt` 都被识别为 Read 操作

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

1. **文件列表长度限制**
   - 当探索大量文件时，文件列表可能过长
   - 当前快照显示 `foo.txt, bar.txt`，需要确认大量文件时的截断策略

2. **文件顺序一致性**
   - 需要确保文件按读取顺序或字母顺序一致展示

3. **探索组生命周期**
   - 需要明确定义探索组何时结束（非探索命令、用户输入等）

### 边界情况

| 场景 | 预期行为 |
|------|---------|
| 大量文件读取（10+ 文件） | 可能需要截断显示或折叠 |
| 同一文件多次读取 | 应该去重显示还是分别显示 |
| 探索命令与非探索命令交替 | 非探索命令应中断探索组 |
| 探索命令失败 | 失败的命令是否仍显示在探索组中 |

### 改进建议

1. **增强测试覆盖**
   - 添加对大量文件读取的测试
   - 测试探索组中断场景（插入非探索命令）
   - 验证文件列表的排序逻辑

2. **可视化改进**
   - 考虑当文件数量超过阈值时的折叠显示
   - 添加探索组的展开/折叠功能
   - 显示每个文件读取的摘要信息（如行数）

3. **交互增强**
   - 允许用户点击探索组查看详细信息
   - 支持在探索组内导航到特定文件读取

4. **文档完善**
   - 明确探索模式的完整判定规则
   - 文档化文件列表的展示策略（排序、截断等）
