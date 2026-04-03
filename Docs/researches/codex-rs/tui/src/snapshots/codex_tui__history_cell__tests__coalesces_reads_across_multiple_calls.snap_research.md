# Research: Coalesces Reads Across Multiple Calls Snapshot

## 场景与职责

此快照测试验证 Codex TUI 在执行探索性（Exploring）任务时，能够跨多个 ExecCall 合并连续的 Read 命令。当 AI 代理分多次执行读取操作时，UI 应当将这些读取操作智能合并为单一的展示组，提供更清晰的视觉呈现。

## 功能点目的

1. **跨调用读取合并**：将多个 ExecCall 中的连续 Read 命令合并展示
2. **探索性活动分组**：将 Search 和多个 Read 命令归类为统一的"Exploring/Explored"活动
3. **渐进式探索展示**：反映 AI 代理先搜索后逐步读取文件的典型工作流

## 具体技术实现

### 核心合并算法

```rust
// exec_cell/render.rs:exploring_display_lines
fn exploring_display_lines(&self, width: u16) -> Vec<Line<'static>> {
    let mut calls = self.calls.clone();
    let mut out_indented = Vec::new();
    
    while !calls.is_empty() {
        let mut call = calls.remove(0);
        
        // 关键：检测当前调用是否全部为 Read 命令
        if call.parsed.iter().all(|parsed| matches!(parsed, ParsedCommand::Read { .. })) {
            // 合并后续连续的 Read-only 调用
            while let Some(next) = calls.first() {
                if next.parsed.iter().all(|parsed| matches!(parsed, ParsedCommand::Read { .. })) {
                    call.parsed.extend(next.parsed.clone());  // 合并 parsed 命令
                    calls.remove(0);  // 移除已合并的调用
                } else {
                    break;
                }
            }
        }
        // ... 渲染逻辑
    }
}
```

### 测试场景构建

```rust
// history_cell.rs:3532-3586
#[test]
fn coalesces_reads_across_multiple_calls() {
    // 第一个调用：Search
    let mut cell = ExecCell::new(
        ExecCall {
            call_id: "c1".to_string(),
            parsed: vec![ParsedCommand::Search {
                query: Some("shimmer_spans".into()),
                path: None,
                cmd: "rg shimmer_spans".into(),
            }],
            // ...
        },
        true,
    );
    cell.complete_call("c1", CommandOutput::default(), Duration::from_millis(1));
    
    // 第二个调用：Read A
    cell = cell.with_added_call("c2".into(), ..., vec![ParsedCommand::Read {
        name: "shimmer.rs".into(),
        // ...
    }], ...).unwrap();
    cell.complete_call("c2", CommandOutput::default(), Duration::from_millis(1));
    
    // 第三个调用：Read B
    cell = cell.with_added_call("c3".into(), ..., vec![ParsedCommand::Read {
        name: "status_indicator_widget.rs".into(),
        // ...
    }], ...).unwrap();
    cell.complete_call("c3", CommandOutput::default(), Duration::from_millis(1));
    
    // 验证：三个调用应合并为统一的展示
    let rendered = render_lines(&cell.display_lines(80)).join("\n");
    insta::assert_snapshot!(rendered);
}
```

### 渲染输出格式

```
• Explored
  └ Search shimmer_spans
    Read shimmer.rs, status_indicator_widget.rs
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/history_cell.rs` | 测试用例 `coalesces_reads_across_multiple_calls` |
| `codex-rs/tui/src/exec_cell/render.rs` | 跨调用读取合并的核心算法 |
| `codex-rs/tui/src/exec_cell/model.rs` | ExecCell 和 ExecCall 数据模型 |
| `codex-rs/tui/src/shimmer.rs` | 动画效果组件 |
| `codex-rs/tui/src/status_indicator_widget.rs` | 状态指示器（与 shimmer 联动） |

### 关键函数调用链

```
HistoryCell::display_lines (ExecCell 实现)
    ↓
exploring_display_lines
    ↓
while !calls.is_empty()  // 遍历所有调用
    ↓
call.parsed.iter().all(|p| matches!(p, ParsedCommand::Read {..}))  // 检测 Read-only
    ↓
call.parsed.extend(next.parsed.clone())  // 合并命令
```

## 依赖与外部交互

### 外部依赖

- `codex_protocol::parse_command::ParsedCommand`: 命令解析类型
- `itertools::Itertools`: 提供 `intersperse` 用于格式化输出

### 内部模块关系

```
┌─────────────────┐
│  history_cell   │ (测试入口)
│   (tests mod)   │
└────────┬────────┘
         ↓
┌─────────────────┐
│  exec_cell/mod  │
│  (HistoryCell   │
│   实现)         │
└────────┬────────┘
         ↓
┌─────────────────┐     ┌─────────────────┐
│ exec_cell/model │────→│ shimmer.rs      │
│ (数据结构)       │     │ (动画效果)       │
└─────────────────┘     └─────────────────┘
         ↓
┌─────────────────┐
│exec_cell/render │ (跨调用合并逻辑)
│ (exploring_     │
│  display_lines) │
└─────────────────┘
```

## 风险、边界与改进建议

### 潜在风险

1. **状态不一致**：如果调用完成顺序与预期不符，合并逻辑可能产生意外结果
2. **内存开销**：克隆整个 calls 向量可能导致内存峰值
3. **时序依赖**：合并逻辑依赖于调用添加的顺序

### 边界情况

1. **非连续 Read**：如果 Read 调用被非 Read 调用中断，不会跨边界合并
2. **空 parsed 列表**：需要处理 parsed 为空的边界情况
3. **大量调用**：数十个调用的合并性能需要验证

### 改进建议

1. **惰性合并**：考虑使用迭代器链而非克隆整个向量
2. **配置阈值**：添加最大合并调用数限制，防止过度合并
3. **元数据保留**：保留原始调用信息用于调试或详细视图
4. **可视化增强**：在合并组之间添加微妙的视觉分隔
5. **动画优化**：对于长合并列表，考虑分批动画展示

### 相关测试覆盖

- `coalesces_sequential_reads_within_one_call`: 单调用内合并
- `coalesces_reads_across_multiple_calls`: 跨调用合并（本快照）
- `coalesced_reads_dedupe_names`: 去重验证
