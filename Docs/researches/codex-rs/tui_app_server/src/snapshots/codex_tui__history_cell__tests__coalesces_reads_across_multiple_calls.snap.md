# 研究文档：跨多个调用合并读取操作快照测试

## 场景与职责

该快照测试验证了 `ExecCell` 在跨多个独立调用（multiple calls）场景下合并连续读取操作（Read 操作）的能力。这是 Codex TUI 历史记录渲染系统的核心功能之一，用于优化和简化命令执行历史的视觉呈现。

在实际使用场景中，Codex 可能会执行一系列相关的文件读取操作：
1. 首先执行搜索操作（Search）定位代码
2. 然后依次读取多个相关文件（Read）

如果这些读取操作分散在多个独立的调用中，UI 应该智能地将它们合并显示，避免重复列出相同的操作类型，从而提供更清晰的执行历史视图。

## 功能点目的

### 核心功能
- **读取操作合并（Read Coalescing）**：将跨多个调用的连续读取操作合并为一个统一的显示组
- **树状结构渲染**：使用缩进和树形符号（└）展示操作之间的层级关系
- **去重显示**：相同类型的连续操作只显示一次操作类型标签

### 预期输出
```
• Explored
  └ Search shimmer_spans
    Read shimmer.rs, status_indicator_widget.rs
```

### 设计意图
1. **减少视觉噪音**：避免每个读取操作都单独显示一行
2. **保持语义清晰**：用户能够理解哪些文件是在同一次"探索"中被读取的
3. **区分操作类型**：搜索（Search）和读取（Read）有明确的层级关系

## 具体技术实现

### 涉及的数据结构

```rust
// ExecCell - 执行命令的历史单元格
pub(crate) struct ExecCell {
    calls: Vec<ExecCall>,  // 多个调用
    // ...
}

// ExecCall - 单个调用
pub(crate) struct ExecCall {
    call_id: String,
    command: Vec<String>,
    parsed: Vec<ParsedCommand>,  // 解析后的命令列表
    // ...
}

// ParsedCommand - 解析后的命令类型
pub enum ParsedCommand {
    Search { query: Option<String>, path: Option<String>, cmd: String },
    Read { name: String, cmd: String, path: String },
    // ...
}
```

### 关键处理流程

1. **多调用构建**：
   - 调用 1：Search 操作（搜索 shimmer_spans）
   - 调用 2：Read 操作（读取 shimmer.rs）
   - 调用 3：Read 操作（读取 status_indicator_widget.rs）

2. **合并逻辑**（在 `ExecCell::display_lines` 中）：
   ```rust
   // 遍历所有调用的 parsed 命令
   // 识别连续的 Read 操作
   // 将连续的 Read 合并为一个组
   ```

3. **渲染逻辑**：
   - 使用 "• Explored" 作为根节点
   - 使用 "  └ " 作为子节点前缀
   - 使用 "    " 作为孙节点前缀
   - 多个读取文件使用逗号分隔

### 代码路径

```
tui/src/history_cell.rs::tests::coalesces_reads_across_multiple_calls
  └── tui/src/exec_cell.rs::ExecCell::display_lines
        └── tui/src/exec_cell.rs::render_parsed_commands
              └── 合并逻辑实现
```

## 关键代码路径与文件引用

### 主要文件
1. **`tui/src/history_cell.rs`**（第 3532-3586 行）
   - 测试用例定义
   - 验证跨调用读取合并行为

2. **`tui/src/exec_cell.rs`**
   - `ExecCell` 结构体实现
   - `display_lines()` 方法 - 渲染逻辑入口
   - 读取合并算法的核心实现

### 相关测试文件
- `tui/src/snapshots/codex_tui__history_cell__tests__coalesces_reads_across_multiple_calls.snap`

### 依赖模块
- `tui/src/render/line_utils.rs` - 行渲染工具函数
- `tui/src/wrapping.rs` - 文本换行处理

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `ExecCell` | 执行命令历史单元格 |
| `ParsedCommand` | 命令解析结果枚举 |
| `CommandOutput` | 命令输出结构 |
| `ExecCommandSource` | 命令来源标识 |

### 外部 crate 依赖
- `ratatui` - TUI 渲染框架，提供 `Line`、`Span` 等类型
- `serde_json` - 测试中的 JSON 参数序列化
- `insta` - 快照测试框架

### 测试辅助函数
```rust
fn render_lines(lines: &[Line<'static>]) -> Vec<String>
fn test_cwd() -> PathBuf
```

## 风险、边界与改进建议

### 潜在风险

1. **合并边界识别错误**
   - 风险：如果非读取操作插入到读取操作之间，合并可能会错误地中断
   - 缓解：测试用例验证了 Search 后接多个 Read 的场景

2. **文件顺序丢失**
   - 风险：合并后文件读取的顺序信息可能丢失
   - 现状：使用逗号分隔的文件列表保持了原始顺序

3. **大量文件读取的性能**
   - 风险：如果一次"探索"涉及数十个文件读取，单行显示可能过长
   - 现状：依赖文本换行机制处理

### 边界情况

| 场景 | 当前行为 | 评估 |
|------|----------|------|
| 单个调用内的连续读取 | 合并显示 | ✅ 正确 |
| 跨调用的连续读取 | 合并显示 | ✅ 正确（本测试验证）|
| 读取操作被其他操作中断 | 分开展示 | ✅ 符合预期 |
| 同一文件被多次读取 | 去重展示 | 由 `coalesced_reads_dedupe_names` 测试验证 |
| 空读取列表 | 不显示 Read 行 | 边界安全 |

### 改进建议

1. **可配置合并策略**
   ```rust
   pub enum ReadCoalescingStrategy {
       Always,      // 总是合并
       SameCall,    // 仅合并同调用内的读取
       Never,       // 从不合并
   }
   ```

2. **文件数量限制**
   - 当合并的文件数量超过阈值（如 10 个）时，显示为 "Read file1, file2, and 8 more"
   - 提供展开/折叠交互

3. **时间戳信息**
   - 在合并显示中保留时间范围信息（如 "Read 3 files in 120ms"）

4. **文件类型分组**
   - 按文件类型分组显示（如 "Source files: a.rs, b.rs | Config files: a.toml"）

### 测试覆盖建议

- [ ] 大量文件读取的换行行为
- [ ] 特殊字符文件名的处理
- [ ] 超长文件名的截断显示
- [ ] 与撤销（undo）操作的交互
