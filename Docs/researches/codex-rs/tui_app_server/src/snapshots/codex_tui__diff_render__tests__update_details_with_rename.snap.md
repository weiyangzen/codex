# Update Details With Rename 快照研究文档

## 场景与职责

此快照测试展示了**文件更新伴随重命名**的渲染效果。这是代码审查中常见的场景：文件内容被修改，同时文件路径也发生变化（重命名或移动）。

### 测试场景
- **源文件**: `src/lib.rs`
- **目标文件**: `src/lib_new.rs`
- **变更类型**: Update（内容修改）+ Move（路径变更）
- **内容变更**: 第 2 行从 `line two` 改为 `line two changed`
- **统计**: `(+1 -1)`

### 核心验证点
1. 文件重命名箭头符号 (`→`) 正确显示
2. 语法高亮基于目标文件扩展名（`.rs`）
3. 行号正确对齐（删除行和插入行都显示为第 2 行）
4. 上下文行（第 1、3 行）正确显示

## 功能点目的

### 1. 重命名路径展示
- 使用 `→` (U+2192) 箭头连接源路径和目标路径
- 格式：`src/lib.rs → src/lib_new.rs`

### 2. 语法高亮语言检测
- 重命名时使用**目标路径**的扩展名检测语言
- 原因：diff 内容反映的是新文件状态
- 实现：`let lang_path = r.move_path.as_deref().unwrap_or(&r.path);`

### 3. 统一差异渲染
- 展示删除行（`-line two`）和插入行（`+line two changed`）
- 上下文行（无符号前缀）提供变更周围信息
- 行号右对齐，确保多位行号时依然整齐

## 具体技术实现

### FileChange 数据结构

```rust
// codex_protocol::protocol::FileChange
pub enum FileChange {
    Add { content: String },
    Delete { content: String },
    Update {
        unified_diff: String,
        move_path: Option<PathBuf>,  // 重命名目标路径
    },
}
```

### 行数据收集

```rust
fn collect_rows(changes: &HashMap<PathBuf, FileChange>) -> Vec<Row> {
    let mut rows: Vec<Row> = Vec::new();
    for (path, change) in changes.iter() {
        // ... 计算增删行数 ...
        
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

### 路径渲染

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

### 语言检测（重命名优化）

```rust
// 对于重命名，使用目标扩展名进行语法高亮
let lang_path = r.move_path.as_deref().unwrap_or(&r.path);
let lang = detect_lang_for_path(lang_path);

fn detect_lang_for_path(path: &Path) -> Option<String> {
    let ext = path.extension()?.to_str()?;
    Some(ext.to_string())
}
```

### 差异渲染

```rust
FileChange::Update { unified_diff, .. } => {
    if let Ok(patch) = diffy::Patch::from_str(unified_diff) {
        for h in patch.hunks() {
            let mut old_ln = h.old_range().start();
            let mut new_ln = h.new_range().start();
            
            for (line_idx, l) in h.lines().iter().enumerate() {
                match l {
                    diffy::Line::Insert(text) => {
                        // 渲染插入行，使用 new_ln
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

| 函数名 | 位置 | 职责 |
|--------|------|------|
| `collect_rows` | diff_render.rs:365 | 收集变更数据，提取 move_path |
| `render_changes_block` | diff_render.rs:402 | 渲染变更块，处理路径展示 |
| `render_path` | diff_render.rs:405 | 闭包函数，渲染带箭头的路径 |
| `detect_lang_for_path` | diff_render.rs:469 | 根据路径扩展名检测语言 |
| `render_change` | diff_render.rs:474 | 根据变更类型渲染内容 |

### 相关测试

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
            move_path: Some(PathBuf::from("new_name.rs")),  // 设置重命名目标
        },
    );

    let lines = diff_summary_for_tests(&changes);
    snapshot_lines("apply_update_with_rename_block", lines, 80, 12);
}
```

## 依赖与外部交互

### diffy crate

```rust
use diffy::Patch;
use diffy::Hunk;
use diffy::Line;

// 创建测试用的 patch
let patch = diffy::create_patch(original, modified).to_string();
```

### 路径处理

```rust
use std::path::PathBuf;

// 路径展示优化
pub(crate) fn display_path_for(path: &Path, cwd: &Path) -> String {
    // 优先使用相对路径
    // 同一 git 仓库内使用相对路径
    // 否则使用 ~/home 缩写或绝对路径
}
```

## 风险、边界与改进建议

### 边界情况

1. **仅重命名无内容变更**
   - 如果 `move_path` 设置但 `unified_diff` 为空
   - 当前实现可能不显示任何内容行
   - 应该显示为纯重命名操作

2. **跨目录移动**
   - `src/lib.rs → lib/src/lib.rs`
   - 路径展示可能很长，需要考虑截断

3. **扩展名变更**
   - `script.txt → script.py`
   - 语法高亮使用 `.py`，但 diff 可能包含旧格式内容
   - 可能导致高亮不准确

### 潜在风险

1. **路径注入**
   - 如果路径包含控制字符或换行符
   - 可能破坏终端布局
   - 需要路径清理

2. **非常长路径**
   - 深层嵌套路径可能超出终端宽度
   - 需要智能截断或换行

3. **特殊字符**
   - 路径中的 Unicode 字符（如 Emoji）
   - 宽字符计算错误可能导致对齐问题

### 改进建议

1. **纯重命名检测**
   - 检测仅重命名无内容变更的情况
   - 显示简化的 "Renamed" 消息，不显示空 diff

2. **路径截断**
   - 长路径使用中间截断（如 `src/.../lib.rs`）
   - 保留文件名和关键目录信息

3. **扩展名变更提示**
   - 当扩展名变更时添加视觉提示
   - 帮助审查者注意格式变化

4. **目录变更高亮**
   - 高亮显示路径中变更的部分
   - 如 `src/lib.rs` → `**lib**/src/lib.rs`

5. **批量重命名**
   - 支持多个文件同时重命名的展示优化
   - 如 "Renamed 5 files from `old_dir/` to `new_dir/`"
