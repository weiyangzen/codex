# 研究文档：单调用内顺序读取合并快照测试

## 场景与职责

该快照测试验证了 `ExecCell` 在**单个调用（single call）**内部合并连续读取操作的能力。与跨调用合并不同，此测试关注的是当多个读取操作发生在同一次命令执行中时的渲染行为。

### 典型使用场景
在 Codex 执行复杂任务时，单条命令可能包含多个子操作：
```bash
# 伪代码表示
search "shimmer_spans" && cat shimmer.rs && cat status_indicator_widget.rs
```

这对应于：
1. **Search**：搜索 shimmer_spans 字符串
2. **Read**：读取 shimmer.rs 文件
3. **Read**：读取 status_indicator_widget.rs 文件

## 功能点目的

### 核心功能
- **单调用内操作合并**：在同一个 ExecCall 的 parsed 命令列表中，将连续的 Read 操作合并
- **层级树形展示**：使用缩进和树形符号展示操作层级
- **操作类型分组**：不同类型的操作（Search vs Read）有明确的分组边界

### 预期输出
```
• Explored
  └ Search shimmer_spans
    Read shimmer.rs
    Read status_indicator_widget.rs
```

### 与跨调用合并的区别

| 特性 | 单调用内合并 | 跨调用合并 |
|------|-------------|-----------|
| 数据来源 | 同一 `ExecCall.parsed` | 多个 `ExecCall` 实例 |
| 合并粒度 | 命令级别 | 调用级别 |
| 显示格式 | 每个文件单独一行 | 文件列表逗号分隔 |
| 使用场景 | 复杂单命令 | 多步骤执行 |

## 具体技术实现

### 测试数据结构

```rust
let call_id = "c1".to_string();
let mut cell = ExecCell::new(
    ExecCall {
        call_id: call_id.clone(),
        command: vec!["bash".into(), "-lc".into(), "echo".into()],
        parsed: vec![
            // 三个操作在同一个 parsed 列表中
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
        output: None,
        source: ExecCommandSource::Agent,
        start_time: Some(Instant::now()),
        duration: None,
        interaction_input: None,
    },
    true,
);
```

### 渲染层级结构

```
• Explored                    <- 根节点（第一级）
  └ Search shimmer_spans      <- 操作类型（第二级）
    Read shimmer.rs           <- 读取操作 1（第三级）
    Read status_indicator_widget.rs  <- 读取操作 2（第三级）
```

### 缩进规则

| 层级 | 前缀 | 说明 |
|------|------|------|
| 1 | "• " | 根节点标记 |
| 2 | "  └ " | 操作类型，树形分支 |
| 3 | "    " | 具体操作，统一缩进 |

### 关键渲染代码

在 `exec_cell.rs` 中：

```rust
impl HistoryCell for ExecCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        // 1. 遍历所有调用
        for call in &self.calls {
            // 2. 处理每个调用的 parsed 命令
            render_parsed_commands(&call.parsed, ...);
        }
    }
}

fn render_parsed_commands(commands: &[ParsedCommand], ...) {
    let mut current_group: Vec<&ParsedCommand> = Vec::new();
    
    for cmd in commands {
        match cmd {
            Read { .. } => current_group.push(cmd),
            _ => {
                // 遇到非 Read 命令，先刷新当前组
                if !current_group.is_empty() {
                    render_read_group(&current_group);
                    current_group.clear();
                }
                render_other(cmd);
            }
        }
    }
    
    // 处理剩余的 Read 组
    if !current_group.is_empty() {
        render_read_group(&current_group);
    }
}
```

## 关键代码路径与文件引用

### 主要文件
1. **`tui/src/history_cell.rs`**（第 3491-3529 行）
   - 测试用例 `coalesces_sequential_reads_within_one_call`
   - 构建包含 Search + 2x Read 的单个 ExecCall

2. **`tui/src/exec_cell.rs`**
   - `ExecCell::display_lines()` - 主渲染入口
   - `render_parsed_commands()` - 命令分组渲染
   - `render_read_group()` - 读取操作组渲染

### 相关快照文件
- `tui/src/snapshots/codex_tui__history_cell__tests__coalesces_sequential_reads_within_one_call.snap`

### 渲染工具
- `tui/src/render/line_utils.rs::prefix_lines` - 行前缀处理
- `tui/src/wrapping.rs::adaptive_wrap_lines` - 自适应换行

## 依赖与外部交互

### 类型依赖
```rust
// 核心类型
ExecCell -> ExecCall -> ParsedCommand

// 渲染类型  
Line<'static>, Span<'static>  // from ratatui
```

### 测试依赖
- `insta::assert_snapshot` - 快照断言
- `render_lines()` - 将 Line 转换为可比较的字符串

### 配置依赖
- `ExecCommandSource::Agent` - 命令来源标识
- `animations_enabled: true` - 启用动画效果

## 风险、边界与改进建议

### 当前实现的风险

1. **层级深度限制**
   - 当前实现固定为 3 层结构
   - 如果未来需要更深的嵌套，需要重构缩进逻辑

2. **操作类型硬编码**
   - Search 和 Read 的处理逻辑是硬编码的
   - 新增操作类型需要修改渲染逻辑

3. **空组处理**
   - 如果 parsed 列表为空，应该显示什么？
   - 当前行为：仅显示 "• Explored" 根节点

### 边界情况分析

| 场景 | 预期行为 | 测试状态 |
|------|----------|----------|
| 无 Search，只有 Read | 直接显示 Read 列表 | 待验证 |
| Search 后无 Read | 仅显示 Search | 待验证 |
| 多个 Search 穿插 Read | 每个 Search 后独立分组 | 待验证 |
| 大量 Read（>20） | 可能需要分页或折叠 | 未处理 |
| 超长文件名 | 依赖换行机制 | 依赖外部实现 |

### 改进建议

1. **动态层级支持**
   ```rust
   struct RenderContext {
       depth: usize,
       prefix_stack: Vec<Span<'static>>,
   }
   ```

2. **操作类型注册机制**
   ```rust
   trait ParsedCommandRenderer {
       fn render(&self, ctx: &mut RenderContext) -> Vec<Line<'static>>;
       fn can_coalesce_with(&self, other: &Self) -> bool;
   }
   ```

3. **智能折叠**
   - 当同一组的操作数量超过阈值时，显示摘要
   - 提供键盘快捷键展开/折叠

4. **性能优化**
   - 对于大量 parsed 命令，考虑使用迭代器而非收集到 Vec
   - 缓存渲染结果，避免重复计算

### 相关测试矩阵

| 测试名称 | 覆盖场景 | 优先级 |
|----------|----------|--------|
| `coalesces_sequential_reads_within_one_call` | 单调用内合并 | P0（已覆盖）|
| `coalesces_reads_across_multiple_calls` | 跨调用合并 | P0（已覆盖）|
| `coalesced_reads_dedupe_names` | 重复文件名去重 | P1（已覆盖）|
| `empty_parsed_list` | 空命令列表 | P2（待添加）|
| `mixed_operations_no_search` | 无 Search 的操作序列 | P2（待添加）|
