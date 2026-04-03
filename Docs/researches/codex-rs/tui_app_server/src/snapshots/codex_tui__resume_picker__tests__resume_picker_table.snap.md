# Resume Picker 表格渲染快照测试文档

## 场景与职责

此快照文件对应 `tui/src/resume_picker.rs` 中的 `resume_table_snapshot` 测试，用于验证 Resume Picker 的表格内容渲染，包括列对齐、时间格式化、选中状态指示器等视觉元素。

该测试的核心职责包括：
- 验证表格列的正确对齐（Created at、Updated at、Conversation）
- 验证时间戳的人性化显示（"16 minutes ago"、"1 hour ago"）
- 验证选中行的视觉指示（`> ` 前缀）
- 验证不同时间跨度的正确格式化

## 功能点目的

### 表格渲染验证
此测试验证 Resume Picker 表格的以下视觉特性：

1. **列对齐**: 所有行在同一列上对齐
2. **时间格式化**: 相对时间显示（秒、分钟、小时、天前）
3. **选中指示**: 当前选中行使用 `> ` 前缀标记
4. **数据一致性**: 预览文本正确显示

### 快照内容解析
```
  Created at      Updated at      Branch  CWD  Conversation
  16 minutes ago  42 seconds ago  -       -    Fix resume picker timestamps
> 1 hour ago      35 minutes ago  -       -    Investigate lazy pagination cap
  2 hours ago     2 hours ago     -       -    Explain the codebase
```

**行解析**:
- **表头行**: `Created at`、`Updated at`、`Branch`、`CWD`、`Conversation`
- **第一行**: 16分钟前创建，42秒前更新，对话主题为 "Fix resume picker timestamps"
- **第二行（选中）**: 1小时前创建，35分钟前更新，`>` 标记为选中状态
- **第三行**: 2小时前创建和更新

**视觉元素**:
- `  `: 普通行的两空格前缀
- `> `: 选中行的前缀（`>` 加粗显示）
- `-`: 缺失的分支和 CWD 数据占位符

## 具体技术实现

### 测试数据构造

```rust
let now = Utc::now();
let rows = vec![
    Row {
        path: PathBuf::from("/tmp/a.jsonl"),
        preview: String::from("Fix resume picker timestamps"),
        thread_id: None,
        thread_name: None,
        created_at: Some(now - Duration::minutes(16)),
        updated_at: Some(now - Duration::seconds(42)),
        cwd: None,
        git_branch: None,
    },
    Row {
        path: PathBuf::from("/tmp/b.jsonl"),
        preview: String::from("Investigate lazy pagination cap"),
        thread_id: None,
        thread_name: None,
        created_at: Some(now - Duration::hours(1)),
        updated_at: Some(now - Duration::minutes(35)),
        cwd: None,
        git_branch: None,
    },
    Row {
        path: PathBuf::from("/tmp/c.jsonl"),
        preview: String::from("Explain the codebase"),
        thread_id: None,
        thread_name: None,
        created_at: Some(now - Duration::hours(2)),
        updated_at: Some(now - Duration::hours(2)),
        cwd: None,
        git_branch: None,
    },
];
state.all_rows = rows.clone();
state.filtered_rows = rows;
state.view_rows = Some(3);
state.selected = 1;  // 选中第二行
```

### 列宽计算

```rust
struct ColumnMetrics {
    max_created_width: usize,
    max_updated_width: usize,
    max_branch_width: usize,
    max_cwd_width: usize,
    labels: Vec<(String, String, String, String)>,  // (created, updated, branch, cwd)
}

fn calculate_column_metrics(rows: &[Row], include_cwd: bool) -> ColumnMetrics {
    // 计算每列的最大宽度，基于 Unicode 显示宽度
    let mut max_created_width = UnicodeWidthStr::width("Created at");
    let mut max_updated_width = UnicodeWidthStr::width("Updated at");
    // ...
    for row in rows {
        let created = format_created_label(row);
        let updated = format_updated_label(row);
        // ...
        max_created_width = max_created_width.max(UnicodeWidthStr::width(created.as_str()));
        max_updated_width = max_updated_width.max(UnicodeWidthStr::width(updated.as_str()));
        // ...
    }
}
```

### 时间格式化

```rust
fn human_time_ago(ts: DateTime<Utc>) -> String {
    let now = Utc::now();
    let delta = now - ts;
    let secs = delta.num_seconds();
    
    if secs < 60 {
        format!("{n} seconds ago", n = secs.max(0))
    } else if secs < 60 * 60 {
        let m = secs / 60;
        format!("{m} minute(s) ago")
    } else if secs < 60 * 60 * 24 {
        let h = secs / 3600;
        format!("{h} hour(s) ago")
    } else {
        let d = secs / (60 * 60 * 24);
        format!("{d} day(s) ago")
    }
}
```

### 行渲染

```rust
let marker = if is_sel { "> ".bold() } else { "  ".into() };
let created_span = Span::from(format!("{created_label:<max_created_width$}")).dim();
let updated_span = Span::from(format!("{updated_label:<max_updated_width$}")).dim();
// ...
let mut spans: Vec<Span> = vec![marker];
spans.push(created_span);
spans.push("  ".into());
spans.push(updated_span);
// ...
let line: Line = spans.into();
```

## 关键代码路径与文件引用

### 主要源文件
- `codex-rs/tui/src/resume_picker.rs` - Resume Picker 实现

### 关键函数
- `resume_table_snapshot` 测试 - 位于第 1565-1642 行
- `calculate_column_metrics` - 位于第 1230-1289 行
- `render_list` - 位于第 941-1072 行
- `human_time_ago` - 位于第 1102-1135 行
- `format_created_label` / `format_updated_label` - 位于第 1137-1150 行

### 依赖模块
- `codex-rs/tui/src/custom_terminal.rs` - 自定义 Terminal
- `codex-rs/tui/src/test_backend.rs` - VT100Backend

### 相关快照文件
- `codex_tui__resume_picker__tests__resume_picker_table.snap`（当前文件）
- `codex_tui__resume_picker__tests__resume_picker_thread_names.snap` - 会话名称显示
- `codex_tui__resume_picker__tests__resume_picker_screen.snap` - 完整界面

## 依赖与外部交互

### 时间处理
- **chrono**: 用于 `DateTime<Utc>` 和持续时间计算
- **系统时间**: `Utc::now()` 获取当前时间

### 文本处理
- **unicode-width**: 正确处理多字节字符的显示宽度
- **format!**: 使用 `{:<width$}` 语法进行左对齐填充

### 渲染框架
- **ratatui**: `Line`、`Span`、`Rect` 等渲染原语
- **自定义后端**: `VT100Backend` 用于测试中的终端模拟

## 风险、边界与改进建议

### 潜在风险

1. **时间漂移**:
   - 风险：测试中使用 `Utc::now()`，快照结果依赖于测试执行时间
   - 现状：测试中使用固定的时间偏移（`now - Duration::minutes(16)`）
   - 缓解：时间格式化输出是相对的，只要测试执行快速，结果稳定

2. **时区问题**:
   - 风险：不同时区下时间显示可能不一致
   - 现状：统一使用 UTC 时间

3. **列宽溢出**:
   - 风险：超长预览文本可能挤压其他列
   - 缓解：`truncate_text` 函数确保预览列不会超出分配宽度

### 边界情况

1. **单数/复数**: "1 minute ago" vs "2 minutes ago" 的正确处理
2. **零秒**: "0 seconds ago" 的显示
3. **未来时间**: 如果 `updated_at` > `now`，显示 "0 seconds ago"
4. **缺失时间戳**: 使用 `-` 占位符
5. **超长预览**: 超过可用宽度的预览文本被截断并添加 `…`

### 改进建议

1. **时间格式化优化**:
   ```rust
   // 添加更精细的时间显示
   if secs < 10 { "just now" }
   else if secs < 60 { "less than a minute ago" }
   ```

2. **列宽自适应**:
   - 根据终端宽度动态调整显示的列数
   - 已实现部分功能：`column_visibility` 函数

3. **排序指示器**:
   - 在表头添加 `▼` 或 `▲` 指示当前排序方向

4. **行分隔线**:
   - 在行之间添加细分隔线提高可读性

5. **颜色编码**:
   - 根据时间久远程度使用不同颜色（如：最近为绿色，较旧为灰色）

### 测试覆盖建议

1. **边界时间**: 测试 59秒、60秒、61秒、59分钟、60分钟等边界
2. **Unicode 预览**: 测试包含中文、emoji 的预览文本
3. **超长预览**: 测试超过 200 字符的预览文本
4. **多列隐藏**: 测试窄终端下列的自动隐藏
5. **空列表**: 测试零行数据时的渲染
