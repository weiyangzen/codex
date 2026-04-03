# Research: Coalesces Sequential Reads Within One Call Snapshot

## 场景与职责

此快照测试验证 Codex TUI 在单个 ExecCall 内部合并多个连续 Read 命令的能力。当 AI 代理在一次调用中执行多个文件读取操作时，UI 应当将这些读取操作合并为单一的展示行，提供更简洁的视觉呈现。

## 功能点目的

1. **单调用内读取合并**：将单个 ExecCall 中的多个 Read 命令合并为一行展示
2. **探索性活动识别**：自动识别 Read-only 的探索性操作模式
3. **紧凑展示**：减少历史记录中的视觉噪音，提升可读性

## 具体技术实现

### 核心合并逻辑

```rust
// exec_cell/render.rs:exploring_display_lines
let reads_only = call
    .parsed
    .iter()
    .all(|parsed| matches!(parsed, ParsedCommand::Read { .. }));

let call_lines: Vec<(&str, Vec<Span<'static>>)> = if reads_only {
    // 全部为 Read 命令时，合并文件名
    let names = call
        .parsed
        .iter()
        .map(|parsed| match parsed {
            ParsedCommand::Read { name, .. } => name.clone(),
            _ => unreachable!(),
        })
        .unique();
    vec![(
        "Read",
        Itertools::intersperse(names.into_iter().map(Into::into), ", ".dim()).collect(),
    )]
} else {
    // 混合命令类型，逐条展示
    let mut lines = Vec::new();
    for parsed in &call.parsed {
        match parsed {
            ParsedCommand::Read { name, .. } => {
                lines.push(("Read", vec![name.clone().into()]));
            }
            // ... 其他命令类型
        }
    }
    lines
}
```

### 测试场景

```rust
// history_cell.rs:3491-3529
#[test]
fn coalesces_sequential_reads_within_one_call() {
    let call_id = "c1".to_string();
    let mut cell = ExecCell::new(
        ExecCall {
            call_id: call_id.clone(),
            command: vec!["bash".into(), "-lc".into(), "echo".into()],
            parsed: vec![
                // 混合命令：Search + 两个 Read
                ParsedCommand::Search {
                    query: Some("shimmer_spans".into()),
                    path: None,
                    cmd: "rg shimmer_spans".into(),
                },
                ParsedCommand::Read {
                    name: "shimmer.rs".into(),
                    cmd: "cat shimmer.rs".into(),
                    path: "shimmer.rs".into(),
                },
                ParsedCommand::Read {
                    name: "status_indicator_widget.rs".into(),
                    cmd: "cat status_indicator_widget.rs".into(),
                    path: "status_indicator_widget.rs".into(),
                },
            ],
            // ...
        },
        true,
    );
    cell.complete_call(&call_id, CommandOutput::default(), Duration::from_millis(1));

    let lines = cell.display_lines(80);
    let rendered = render_lines(&lines).join("\n");
    insta::assert_snapshot!(rendered);
}
```

### 输出格式

```
• Explored
  └ Search shimmer_spans
    Read shimmer.rs
    Read status_indicator_widget.rs
```

注意：由于 Search 命令的存在，Read 命令没有被合并到同一行，而是分别展示。

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/history_cell.rs` | 测试用例 `coalesces_sequential_reads_within_one_call` |
| `codex-rs/tui/src/exec_cell/render.rs` | 读取合并渲染逻辑（`exploring_display_lines` 函数） |
| `codex-rs/tui/src/exec_cell/model.rs` | ExecCell 和 ExecCall 数据模型 |
| `codex-rs/tui/src/shimmer.rs` | 微光动画效果 |
| `codex-rs/tui/src/status_indicator_widget.rs` | 状态指示器组件 |

### 渲染流程

```
ExecCell::display_lines
    ↓
exploring_display_lines (render.rs:253)
    ↓
遍历 calls
    ↓
检测 reads_only (line 292-295)
    ↓
if reads_only:
    合并所有 Read 文件名 (line 297-309)
else:
    逐条渲染每个命令 (line 311-336)
    ↓
prefix_lines 添加缩进前缀
```

## 依赖与外部交互

### 外部依赖

- `itertools`: `intersperse` 用于在文件名间插入逗号分隔符
- `codex_protocol::parse_command::ParsedCommand`: 命令类型定义

### 内部模块交互

```
┌─────────────────────────┐
│    history_cell.rs      │
│   (测试用例入口)         │
└───────────┬─────────────┘
            ↓
┌─────────────────────────┐
│   exec_cell/mod.rs      │
│  (HistoryCell trait 实现)│
└───────────┬─────────────┘
            ↓
┌─────────────────────────┐
│  exec_cell/render.rs    │
│ ┌─────────────────────┐ │
│ │exploring_display_   │ │
│ │lines()              │ │
│ │ ┌─────────────────┐ │ │
│ │ │ reads_only 检测 │ │ │
│ │ │ 文件名合并逻辑  │ │ │
│ │ └─────────────────┘ │ │
│ └─────────────────────┘ │
└───────────┬─────────────┘
            ↓
┌─────────────────────────┐
│      shimmer.rs         │
│   (动画效果支持)         │
└─────────────────────────┘
```

## 风险、边界与改进建议

### 潜在风险

1. **误判为 reads_only**：如果命令列表中包含非 Read 命令但被错误识别，可能导致展示异常
2. **文件名冲突**：同名不同路径的文件合并后可能产生歧义
3. **性能问题**：大量 Read 命令的合并操作可能影响渲染性能

### 边界情况

1. **零个 Read**：parsed 列表为空时的处理
2. **单个 Read**：只有一个 Read 命令时的展示（应正常显示）
3. **混合命令**：Read 与其他命令混合时的正确识别
4. **超长文件名列表**：需要换行处理的边界

### 改进建议

1. **路径显示优化**：显示相对路径而非仅文件名，减少歧义
2. **折叠/展开功能**：对于大量 Read 命令，提供折叠选项
3. **文件类型图标**：根据文件扩展名显示不同图标增强可读性
4. **读取顺序指示**：用箭头或序号指示读取顺序
5. **性能优化**：缓存 reads_only 检测结果，避免重复计算

### 相关测试

- `coalesces_sequential_reads_within_one_call`：本快照测试
- `coalesces_reads_across_multiple_calls`：跨调用合并
- `coalesced_reads_dedupe_names`：去重验证
