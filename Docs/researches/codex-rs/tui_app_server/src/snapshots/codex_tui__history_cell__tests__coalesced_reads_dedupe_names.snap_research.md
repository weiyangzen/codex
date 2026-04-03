# Research: Coalesced Reads with Deduplicated Names

## 场景与职责

该快照测试验证 Codex TUI 中对重复读取操作的合并与去重显示。当 AI 助手在同一调用中多次读取相同文件时，历史记录应智能地去重并合并显示，避免重复列出相同的文件名，提供更简洁的用户体验。

## 功能点目的

1. **读取合并**: 将同一调用中的多个 `Read` 操作合并为一行显示
2. **去重处理**: 去除重复的文件名，只显示唯一的文件列表
3. **简洁格式**: 使用 "Read file1, file2, file3" 的格式展示多个读取
4. **视觉层次**: 使用树形结构（└）表示从属关系

## 具体技术实现

### 核心逻辑
在 `exploring_display_lines` 方法中，当检测到调用只包含 `Read` 操作时，使用 `itertools::unique()` 去重：

```rust
let call_lines: Vec<(&str, Vec<Span<'static>>)> = if reads_only {
    let names = call
        .parsed
        .iter()
        .map(|parsed| match parsed {
            ParsedCommand::Read { name, .. } => name.clone(),
            _ => unreachable!(),
        })
        .unique();  // <-- 去重关键
    vec![(
        "Read",
        Itertools::intersperse(names.into_iter().map(Into::into), ", ".dim()).collect(),
    )]
}
```

### 显示格式
```
• Explored
  └ Read auth.rs, shimmer.rs
```

格式分解：
- `•`: 状态指示器（完成时暗淡，进行中为 spinner）
- `Explored`: 标题（粗体）
- `└`: 树形连接线
- `Read`: 操作类型（青色）
- `auth.rs, shimmer.rs`: 去重后的文件名列表

### 测试代码位置
- 文件: `codex-rs/tui/src/history_cell.rs`
- 测试函数: `coalesced_reads_dedupe_names`
- 行号: 约 3589-3620

```rust
#[test]
fn coalesced_reads_dedupe_names() {
    let mut cell = ExecCell::new(
        ExecCall {
            call_id: "c1".to_string(),
            command: vec!["bash".into(), "-lc".into(), "echo".into()],
            parsed: vec![
                ParsedCommand::Read {
                    name: "auth.rs".into(),
                    cmd: "cat auth.rs".into(),
                    path: "auth.rs".into(),
                },
                ParsedCommand::Read {
                    name: "auth.rs".into(),  // 重复
                    cmd: "cat auth.rs".into(),
                    path: "auth.rs".into(),
                },
                ParsedCommand::Read {
                    name: "shimmer.rs".into(),
                    cmd: "cat shimmer.rs".into(),
                    path: "shimmer.rs".into(),
                },
            ],
            // ...
        },
        true,
    );
    cell.complete_call("c1", CommandOutput::default(), Duration::from_millis(1));
    // 预期输出: "Read auth.rs, shimmer.rs"（auth.rs 只出现一次）
}
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/exec_cell/render.rs` | `ExecCell` 渲染逻辑，包含读取合并 |
| `codex-rs/tui/src/exec_cell/render.rs:253-354` | `exploring_display_lines` 方法 |
| `codex-rs/tui/src/exec_cell/render.rs:292-309` | 读取去重和格式化逻辑 |
| `codex-rs/tui/src/exec_cell/model.rs` | `ExecCell` 和 `ExecCall` 数据模型 |
| `codex-rs/tui/src/history_cell.rs:3589-3620` | 测试用例 |

### 依赖模块
- `itertools::Itertools`: 提供 `unique()` 和 `intersperse()` 方法
- `codex_protocol::parse_command::ParsedCommand::Read`: 读取命令解析结果

## 依赖与外部交互

### 输入
- `ExecCell` 包含多个 `ExecCall`
- 每个 `ExecCall` 包含多个 `ParsedCommand::Read`
- 读取命令可能有重复的文件名

### 输出
```
• Explored
  └ Read auth.rs, shimmer.rs
```

注意：尽管输入中有两个 `auth.rs` 读取操作，输出中只显示一次。

### 去重逻辑流程
```
输入: [Read(auth.rs), Read(auth.rs), Read(shimmer.rs)]
  ↓
map: ["auth.rs", "auth.rs", "shimmer.rs"]
  ↓
unique(): ["auth.rs", "shimmer.rs"]
  ↓
intersperse(", "): ["auth.rs", ", ", "shimmer.rs"]
  ↓
输出: "Read auth.rs, shimmer.rs"
```

## 风险、边界与改进建议

### 潜在风险
1. **顺序丢失**: `unique()` 保持顺序，但如果需要按原始出现次数排序则无法满足
2. **大量文件**: 如果读取数十个文件，单行可能过长需要换行
3. **路径差异**: 相同文件名但不同路径的文件被视为不同文件（这是正确的，但用户可能困惑）

### 边界情况
1. **单文件读取**: 只有一个文件时正常显示 "Read filename"
2. **全重复**: 所有读取都是同一文件时只显示一个文件名
3. **无读取**: 空列表不会创建 Read 行（由调用逻辑保证）
4. **混合操作**: 如果调用中混合了 Read 和其他操作（如 Search），则每个 Read 单独显示，不合并

### 改进建议
1. **文件计数**: 当文件很多时，显示 "Read 12 files" 并支持展开查看完整列表
2. **分组显示**: 按目录分组显示文件，如 "Read src/: auth.rs, shimmer.rs"
3. **读取统计**: 显示读取的总字节数或行数
4. **差异高亮**: 如果同一文件被多次读取且内容有变化，高亮显示
5. **排序选项**: 支持按字母顺序或读取顺序显示
6. **路径截断**: 长路径智能截断，保留关键信息
