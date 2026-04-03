# 研究文档: update_details_with_rename

## 场景与职责

该测试验证 **TUI 差异渲染器在处理文件重命名（move/rename）操作时的正确显示**。当用户重命名文件并同时修改其内容时，界面需要清晰地展示：
1. 原始文件名和新文件名
2. 变更的统计信息（新增/删除行数）
3. 具体的代码差异

这是代码审查中常见的场景，特别是在重构操作（如将 `lib.rs` 重命名为 `lib_new.rs` 并修改内容）时。

## 功能点目的

1. **重命名路径显示**: 以 `src/lib.rs → src/lib_new.rs` 格式展示文件重命名
2. **变更统计**: 显示新增和删除的行数 `(+1 -1)`
3. **差异内容渲染**: 正确显示统一差异格式（unified diff）的内容
4. **视觉层次**: 通过缩进和符号区分标题、行号、gutter 符号和代码内容

测试场景：
- 原始文件: `src/lib.rs`
- 新文件名: `src/lib_new.rs`
- 变更: 第 2 行从 "line two" 改为 "line two changed"

## 具体技术实现

### 测试数据准备

```rust
let mut changes: HashMap<PathBuf, FileChange> = HashMap::new();
let original = "line one\nline two\nline three\n";
let modified = "line one\nline two changed\nline three\n";
let patch = diffy::create_patch(original, modified).to_string();

changes.insert(
    PathBuf::from("src/lib.rs"),
    FileChange::Update {
        unified_diff: patch,
        move_path: Some(PathBuf::from("src/lib_new.rs")),  // 重命名目标
    },
);
```

### 渲染流程

1. **创建差异摘要** (`create_diff_summary`, 行 345-352):
   ```rust
   let lines = create_diff_summary(&changes, &PathBuf::from("/"), 80);
   ```

2. **收集行数据** (`collect_rows`, 行 365-390):
   - 提取 `move_path` 字段
   - 计算新增/删除行数

3. **渲染路径** (`render_path`, 行 405-412):
   ```rust
   let render_path = |row: &Row| -> Vec<RtSpan<'static>> {
       let mut spans = Vec::new();
       spans.push(display_path_for(&row.path, cwd).into());
       if let Some(move_path) = &row.move_path {
           spans.push(format!(" → {}", display_path_for(move_path, cwd)).into());
       }
       spans
   };
   ```

4. **渲染头部** (行 419-436):
   ```rust
   let mut header_spans: Vec<RtSpan<'static>> = vec!["• ".dim()];
   header_spans.push(verb.bold());  // "Proposed Change"
   header_spans.push(" ".into());
   header_spans.extend(render_path(row));  // "src/lib.rs → src/lib_new.rs"
   header_spans.push(" ".into());
   header_spans.extend(render_line_count_summary(row.added, row.removed));  // "(+1 -1)"
   ```

### 输出格式解析

```
"• Proposed Change src/lib.rs → src/lib_new.rs (+1 -1)                           "
"    1      line one                                                             "
"    2     -line two                                                             "
"    2     +line two changed                                                     "
"    3      line three                                                           "
```

格式说明：
- `•`: 项目符号（dim 样式）
- `Proposed Change`: 操作类型（bold 样式）
- `src/lib.rs → src/lib_new.rs`: 重命名路径
- `(+1 -1)`: 变更统计（绿色 +，红色 -）
- `1`, `2`, `3`: 行号（右对齐）
- `-`: 删除行标记（红色背景）
- `+`: 插入行标记（绿色背景）
- ` `: 上下文行标记（无背景）

## 关键代码路径与文件引用

### 主要文件

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/diff_render.rs` | 差异渲染核心实现 |

### 关键函数

| 函数 | 行号 | 职责 |
|------|------|------|
| `ui_snapshot_apply_update_block` | 1508-1526 | 类似测试（无重命名）|
| `ui_snapshot_apply_update_with_rename_block` | 1528-1546 | 带重命名的测试 |
| `create_diff_summary` | 345-352 | 差异摘要生成入口 |
| `collect_rows` | 365-390 | 收集文件变更数据 |
| `render_changes_block` | 402-464 | 渲染变更块 |
| `render_path` | 405-412 | 渲染路径（含重命名箭头）|
| `display_path_for` | 741-762 | 路径显示格式化 |

### 相关数据结构

```rust
// FileChange::Update 变体
FileChange::Update {
    unified_diff: String,       // 统一差异文本
    move_path: Option<PathBuf>, // 可选的重命名目标路径
}

// 内部行数据结构
struct Row {
    path: PathBuf,              // 原始路径
    move_path: Option<PathBuf>, // 重命名目标（从 FileChange 提取）
    added: usize,               // 新增行数
    removed: usize,             // 删除行数
    change: FileChange,         // 原始变更数据
}
```

### 重命名检测逻辑

在 `collect_rows` 函数中（行 373-379）：
```rust
let move_path = match change {
    FileChange::Update {
        move_path: Some(new),
        ..
    } => Some(new.clone()),
    _ => None,
};
```

### 路径显示规则

`display_path_for` 函数（行 741-762）处理路径显示：
1. 相对路径：直接显示
2. 绝对路径（在当前工作目录下）：转为相对路径
3. 同 Git 仓库内的路径：使用相对路径
4. 其他情况：使用 `~/` 简化的家目录路径

## 依赖与外部交互

### 外部 crate

| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染框架 |
| `diffy` | 统一差异格式解析和生成 |

### 内部模块依赖

```rust
use codex_protocol::protocol::FileChange;
use crate::exec_command::relativize_to_home;
use codex_core::git_info::get_git_repo_root;
```

### 相关协议定义

`FileChange` 定义在 `codex-protocol` crate 中：
```rust
pub enum FileChange {
    Add { content: String },
    Delete { content: String },
    Update {
        unified_diff: String,
        move_path: Option<PathBuf>,  // 重命名支持
    },
}
```

## 风险、边界与改进建议

### 潜在风险

1. **路径长度溢出**: 如果路径非常长，可能超出终端宽度
   - 当前实现会截断或换行，但可能影响可读性
   - 长路径应考虑使用 `...` 缩写

2. **特殊字符处理**: 路径中包含控制字符或不可打印字符
   - 当前未对路径进行转义处理
   - 可能导致终端显示异常

3. **跨平台路径分隔符**: Windows 使用 `\`，Unix 使用 `/`
   - 当前显示使用系统默认分隔符
   - 在混合环境中可能不一致

### 边界情况

| 场景 | 当前处理 |
|------|----------|
| 仅重命名无内容变更 | 显示 `(+0 -0)`，无差异内容 |
| 重命名且大量变更 | 正常显示，行号宽度自适应 |
| 路径包含空格 | 直接显示，无引号包裹 |
| 多级目录重命名 | 完整显示，如 `a/b/c → x/y/z` |

### 改进建议

1. **路径缩写**: 对于超长路径，实现智能缩写
   ```rust
   fn abbreviate_path(path: &str, max_len: usize) -> String {
       // "very/long/path/to/file.rs" → "very/.../to/file.rs"
   }
   ```

2. **添加引号**: 路径包含空格时添加引号
   ```rust
   "src/my file.rs" → "\"src/my file.rs\""
   ```

3. **统一路径分隔符**: 始终使用 `/` 显示，提高跨平台一致性
   ```rust
   path.replace('\\', "/")
   ```

4. **视觉增强**: 为重命名箭头添加颜色
   ```rust
   spans.push(" → ".cyan());  // 或使用 dim 样式
   ```

5. **添加测试场景**:
   ```rust
   // 仅重命名无内容变更
   #[test]
   fn ui_snapshot_rename_only_no_content_change() { ... }
   
   // 多级目录重命名
   #[test]
   fn ui_snapshot_deep_path_rename() { ... }
   
   // 路径包含特殊字符
   #[test]
   fn ui_snapshot_path_with_spaces() { ... }
   ```

6. **国际化准备**: 当前 "Proposed Change" 是硬编码英文
   - 考虑使用本地化字符串
   - 或允许主题/配置自定义

### 相关测试

| 测试 | 描述 |
|------|------|
| `apply_update_block` | 基本更新操作（无重命名）|
| `apply_update_with_rename_block` | 更新 + 重命名 |
| `apply_update_block_relativizes_path` | 路径相对化 |
| `rename_diff_uses_destination_extension` | 重命名后使用目标扩展名高亮 |
