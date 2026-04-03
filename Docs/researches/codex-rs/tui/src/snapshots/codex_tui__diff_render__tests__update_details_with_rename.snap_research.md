# Update Details With Rename Snapshot 研究文档

## 场景与职责

此快照测试验证了**文件重命名（Rename/Move）场景下的 diff 渲染**。当文件被重命名同时内容也发生变更时，系统需要正确显示：
1. 源文件路径和目标文件路径
2. 文件内容的变更详情
3. 正确的行号和变更统计

这是代码重构中常见的场景，如将 `lib.rs` 重构为 `lib_new.rs` 并同时进行代码修改。

## 功能点目的

### 重命名场景展示

```
• Proposed Change src/lib.rs → src/lib_new.rs (+1 -1)
    1      line one
    2     -line two
    2     +line two changed
    3      line three
```

关键信息：
- Header 显示 `src/lib.rs → src/lib_new.rs`（带箭头）
- 统计 `(+1 -1)` 表示内容变更
- 行号对齐显示（删除行和新增行都显示行号 2）

### FileChange::Update 结构

```rust
pub enum FileChange {
    Update {
        unified_diff: String,       // unified diff 内容
        move_path: Option<PathBuf>, // 重命名目标路径（如果有）
    },
    // ...
}
```

## 具体技术实现

### 路径渲染

```rust
fn render_path(row: &Row) -> Vec<RtSpan<'static>> {
    let mut spans = Vec::new();
    spans.push(display_path_for(&row.path, cwd).into());
    if let Some(move_path) = &row.move_path {
        spans.push(format!(" → {}", display_path_for(move_path, cwd)).into());
    }
    spans
}
```

### 行数据收集

```rust
fn collect_rows(changes: &HashMap<PathBuf, FileChange>) -> Vec<Row> {
    let mut rows: Vec<Row> = Vec::new();
    for (path, change) in changes.iter() {
        // ...
        let move_path = match change {
            FileChange::Update {
                move_path: Some(new),
                ..
            } => Some(new.clone()),
            _ => None,
        };
        rows.push(Row {
            path: path.clone(),
            move_path,
            added,
            removed,
            change: change.clone(),
        });
    }
    rows.sort_by_key(|r| r.path.clone());
    rows
}
```

### 语法高亮语言检测

对于重命名文件，使用**目标文件**的扩展名进行语法高亮：

```rust
// 对于重命名，使用目标扩展名进行高亮
// diff 内容反映的是新文件的内容
let lang_path = r.move_path.as_deref().unwrap_or(&r.path);
let lang = detect_lang_for_path(lang_path);
```

这确保了：
- `foo.txt → foo.rs` 会使用 Rust 语法高亮
- 即使源文件扩展名未知，也能正确高亮

### Diff 解析与渲染

```rust
FileChange::Update { unified_diff, .. } => {
    if let Ok(patch) = diffy::Patch::from_str(unified_diff) {
        for h in patch.hunks() {
            let mut old_ln = h.old_range().start();
            let mut new_ln = h.new_range().start();
            for l in h.lines() {
                match l {
                    diffy::Line::Insert(text) => {
                        // 渲染新增行，使用 new_ln
                        new_ln += 1;
                    }
                    diffy::Line::Delete(text) => {
                        // 渲染删除行，使用 old_ln
                        old_ln += 1;
                    }
                    diffy::Line::Context(text) => {
                        // 渲染上下文行
                        old_ln += 1;
                        new_ln += 1;
                    }
                }
            }
        }
    }
}
```

## 关键代码路径与文件引用

### 核心函数

| 函数 | 文件 | 行号 | 职责 |
|------|------|------|------|
| `collect_rows` | `diff_render.rs` | 365-390 | 收集变更数据，提取 move_path |
| `render_path` | `diff_render.rs` | 405-412 | 渲染路径（含重命名箭头） |
| `render_changes_block` | `diff_render.rs` | 402-464 | 渲染变更块 |
| `render_change` | `diff_render.rs` | 547-734 | 渲染 Update 类型变更 |

### 测试代码

```rust
#[test]
fn ui_snapshot_apply_update_with_rename_block() {
    let mut changes: HashMap<PathBuf, FileChange> = HashMap::new();
    let original = "A\nB\nC\n";
    let modified = "A\nB changed\nC\n";
    let patch = diffy::create_patch(original, modified).to_string();

    changes.insert(
        PathBuf::from("old_name.rs"),
        FileChange::Update {
            unified_diff: patch,
            move_path: Some(PathBuf::from("new_name.rs")),
        },
    );

    let lines = diff_summary_for_tests(&changes);
    snapshot_lines("apply_update_with_rename_block", lines, 80, 12);
}
```

### 相关测试

| 测试名 | 说明 |
|--------|------|
| `ui_snapshot_apply_update_with_rename_block` | 重命名场景快照 |
| `rename_diff_uses_destination_extension_for_highlighting` | 验证使用目标扩展名高亮 |

## 依赖与外部交互

### Diff 解析

- `diffy::Patch::from_str`：解析 unified diff
- `diffy::Hunk`：Diff hunk 信息
  - `old_range()`：旧文件行范围
  - `new_range()`：新文件行范围
  - `lines()`：Hunk 中的行列表

### 路径处理

- `display_path_for`：将绝对路径转换为相对路径显示
- 支持 Git 仓库根目录检测
- 支持 home 目录简写（`~`）

## 风险、边界与改进建议

### 边界情况

1. **纯重命名（无内容变更）**：
   - 如果 `move_path` 存在但 diff 为空
   - 统计显示 `(+0 -0)`，可能应该显示 "Renamed"

2. **多次重命名**：
   - 当前只支持单次重命名记录
   - 复杂重构历史可能丢失

3. **跨目录重命名**：
   - `src/a/b/c.rs → src/x/y/z.rs`
   - 路径显示可能过长，需要截断

4. **大小写变更**（Windows）：
   - `File.rs → file.rs`
   - 在某些文件系统上可能被视为同一文件

### 潜在风险

1. **路径显示长度**：
   ```rust
   spans.push(format!(" → {}", display_path_for(move_path, cwd)).into());
   ```
   长路径可能导致 header 溢出，需要截断处理

2. **语言检测错误**：
   - 如果目标扩展名未知（如 `.xyzzy`）
   - 回退到无语法高亮

3. **Diff 解析失败**：
   ```rust
   if let Ok(patch) = diffy::Patch::from_str(unified_diff) {
       // ...
   }
   ```
   解析失败时静默跳过，可能导致无内容显示

### 改进建议

1. **纯重命名优化**：
   - 检测 `move_path` 存在且 diff 为空的情况
   - 显示 "Renamed src/old.rs → src/new.rs"
   - 不显示 `(+0 -0)` 统计

2. **路径截断**：
   - 长路径使用 `...` 截断中间部分
   - 保持文件名完整可见
   - 示例：`src/.../utils/helpers.rs → src/.../new/helpers.rs`

3. **交互增强**：
   - 点击路径在编辑器中打开文件
   - 悬停显示完整路径

4. **统计细化**：
   - 显示重命名统计和内容变更统计
   - 示例：`Renamed (+3 -2 lines changed)`

5. **测试覆盖**：
   - 添加纯重命名测试
   - 添加跨目录重命名测试
   - 添加长路径截断测试
