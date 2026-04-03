# Research: Coalesced Reads Dedupe Names Snapshot

## 场景与职责

此快照测试验证 Codex TUI 历史记录单元格（History Cell）在处理探索性（Exploring）命令组时，对重复文件读取名称的去重能力。当 AI 代理在单次调用中多次读取同一文件时，UI 应当智能合并重复项，避免冗余显示。

## 功能点目的

1. **重复项去重**：当同一文件被多次读取时，只显示一次文件名
2. **探索性命令组展示**：将 Read、List、Search 等非破坏性命令归类为"Exploring"活动
3. **视觉层次优化**：通过树形结构（└）展示命令执行的层级关系

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

### 关键渲染流程

1. **探索性单元格检测** (`is_exploring_cell`):
```rust
pub(crate) fn is_exploring_cell(&self) -> bool {
    self.calls.iter().all(Self::is_exploring_call)
}

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

2. **读取命令合并与去重** (`exploring_display_lines`):
```rust
let names = call
    .parsed
    .iter()
    .map(|parsed| match parsed {
        ParsedCommand::Read { name, .. } => name.clone(),
        _ => unreachable!(),
    })
    .unique();  // 使用 itertools::Itertools::unique() 去重
```

3. **连续读取合并**:
```rust
if call.parsed.iter().all(|parsed| matches!(parsed, ParsedCommand::Read { .. })) {
    while let Some(next) = calls.first() {
        if next.parsed.iter().all(|parsed| matches!(parsed, ParsedCommand::Read { .. })) {
            call.parsed.extend(next.parsed.clone());
            calls.remove(0);
        } else {
            break;
        }
    }
}
```

### 输出格式

```
• Explored
  └ Read auth.rs, shimmer.rs
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/history_cell.rs` | 历史记录单元格主逻辑，包含测试用例 `coalesced_reads_dedupe_names` |
| `codex-rs/tui/src/exec_cell/model.rs` | ExecCell 数据模型，探索性命令检测逻辑 |
| `codex-rs/tui/src/exec_cell/render.rs` | ExecCell 渲染逻辑，读取命令合并与去重实现 |
| `codex-rs/tui/src/shimmer.rs` | 动画效果（本快照中未激活） |

### 测试代码位置

```rust
// history_cell.rs:3589-3623
#[test]
fn coalesced_reads_dedupe_names() {
    let mut cell = ExecCell::new(
        ExecCall {
            call_id: "c1".to_string(),
            command: vec!["bash".into(), "-lc".into(), "echo".into()],
            parsed: vec![
                ParsedCommand::Read { name: "auth.rs".into(), cmd: "cat auth.rs".into(), path: "auth.rs".into() },
                ParsedCommand::Read { name: "auth.rs".into(), cmd: "cat auth.rs".into(), path: "auth.rs".into() },  // 重复
                ParsedCommand::Read { name: "shimmer.rs".into(), cmd: "cat shimmer.rs".into(), path: "shimmer.rs".into() },
            ],
            // ...
        },
        true,
    );
    cell.complete_call("c1", CommandOutput::default(), Duration::from_millis(1));
    let lines = cell.display_lines(80);
    let rendered = render_lines(&lines).join("\n");
    insta::assert_snapshot!(rendered);
}
```

## 依赖与外部交互

### 外部依赖

- `itertools`: 提供 `unique()` 迭代器方法用于去重
- `codex_protocol::parse_command::ParsedCommand`: 解析命令类型定义

### 内部模块交互

```
history_cell.rs (测试)
    ↓
exec_cell/render.rs (exploring_display_lines)
    ↓
exec_cell/model.rs (is_exploring_call, is_exploring_cell)
    ↓
itertools::unique() (去重)
```

## 风险、边界与改进建议

### 潜在风险

1. **去重粒度问题**：当前仅按文件名去重，如果同一文件在不同路径下有相同名称，可能被错误去重
2. **顺序敏感性**：去重后保留了首次出现的顺序，但可能丢失后续读取的上下文信息

### 边界情况

1. **空读取列表**：所有读取都被去重后可能只剩空列表
2. **大量重复文件**：极端情况下去重逻辑的性能表现
3. **跨调用去重**：当前仅在单个调用内去重，跨调用的相同文件读取不会被合并

### 改进建议

1. **增强去重逻辑**：考虑使用完整路径而非仅文件名进行去重
2. **添加计数指示器**：显示"auth.rs (2x)"表示重复读取次数
3. **配置化去重**：允许用户配置是否启用去重功能
4. **性能优化**：对于大量文件读取场景，考虑使用 HashSet 替代迭代器去重
