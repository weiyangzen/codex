# Diff Render - 文件更新带重命名渲染测试

## 场景与职责

该快照测试验证 TUI 中**文件更新伴随重命名**的 diff 渲染效果。当 Codex 在修改文件内容的同时将文件重命名（移动）时，需要在 UI 中同时展示内容变更和路径变更，帮助用户理解这是一次"移动并编辑"的操作。

这是 `FileChange::Update` 的特殊场景，利用了 `move_path` 字段来标识重命名操作。

## 功能点目的

1. **重命名可视化**：使用箭头符号（`→`）清晰展示旧路径到新路径的映射
2. **内容变更展示**：同时展示文件的统一 diff 内容变更
3. **统计信息**：汇总显示新增和删除的行数
4. **语法高亮**：根据目标文件扩展名进行语法高亮（而非源文件）
5. **路径相对化**：将绝对路径转换为相对路径显示

## 具体技术实现

### 核心数据结构

```rust
pub enum FileChange {
    Update {
        unified_diff: String,           // 统一 diff 内容
        move_path: Option<PathBuf>,     // 重命名目标路径（可选）
    },
    // ... Add, Delete
}

// 内部使用的 Row 结构
struct Row {
    path: PathBuf,
    move_path: Option<PathBuf>,  // 从重命名的 Update 中提取
    added: usize,
    removed: usize,
    change: FileChange,
}
```

### 重命名信息提取

```rust
// diff_render.rs:373-379
let move_path = match change {
    FileChange::Update {
        move_path: Some(new),
        ..
    } => Some(new.clone()),
    _ => None,
};
```

### 路径渲染

```rust
// diff_render.rs:405-412
let render_path = |row: &Row| -> Vec<RtSpan<'static>> {
    let mut spans = Vec::new();
    // 源路径
    spans.push(display_path_for(&row.path, cwd).into());
    // 重命名箭头 + 目标路径
    if let Some(move_path) = &row.move_path {
        spans.push(format!(" → {}", display_path_for(move_path, cwd)).into());
    }
    spans
};
```

### 语法高亮策略

```rust
// diff_render.rs:454-457
// 对于重命名，使用目标扩展名进行高亮
// 因为 diff 内容反映的是新文件的内容
let lang_path = r.move_path.as_deref().unwrap_or(&r.path);
let lang = detect_lang_for_path(lang_path);
```

### 关键代码路径

```rust
// diff_render.rs:1528-1546
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
            move_path: Some(PathBuf::from("new_name.rs")),  // 重命名目标
        },
    );

    let lines = diff_summary_for_tests(&changes);
    snapshot_lines("apply_update_with_rename_block", lines, 80, 12);
}
```

### 渲染输出格式

```
• Edited old_name.rs → new_name.rs (+1 -1)
    1  A
    2 -B
    2 +B changed
    3  C
```

## 关键代码路径与文件引用

| 组件 | 文件路径 | 职责 |
|------|----------|------|
| 重命名渲染 | `diff_render.rs:405-412` | `render_path` 闭包 |
| 语法高亮选择 | `diff_render.rs:454-457` | 目标路径扩展名检测 |
| 路径显示 | `diff_render.rs:738-762` | `display_path_for` 函数 |
| 测试用例 | `diff_render.rs:1528-1546` | `ui_snapshot_apply_update_with_rename_block` |
| 扩展名检测 | `diff_render.rs:469-472` | `detect_lang_for_path` 函数 |

### 相关函数

- `collect_rows()` - 收集变更并提取重命名信息
- `render_changes_block()` - 渲染变更块（包含重命名路径）
- `detect_lang_for_path()` - 根据路径检测语言
- `display_path_for()` - 路径格式化

## 依赖与外部交互

### 外部依赖

1. **diffy**：统一 diff 格式创建和解析
2. **ratatui**：终端 UI 渲染

### 内部依赖

- `codex_protocol::protocol::FileChange` - 文件变更类型定义
- `crate::render::highlight::highlight_code_to_styled_spans` - 语法高亮

### 数据流

```
old_name.rs + new_name.rs + unified_diff
    ↓ FileChange::Update { move_path: Some(new_name.rs) }
Row { path: old_name.rs, move_path: Some(new_name.rs), ... }
    ↓ render_path()
"old_name.rs → new_name.rs"
    ↓ 渲染到终端
"• Edited old_name.rs → new_name.rs (+1 -1)"
```

## 风险、边界与改进建议

### 潜在风险

1. **路径混淆**：用户可能误解箭头方向（是重命名到还是重命名从）
2. **循环重命名**：A→B 和 B→A 同时发生时的显示
3. **目录移动**：整个目录重命名时的路径显示
4. **大小写敏感**：不同文件系统的大小写敏感差异

### 边界情况

1. **仅重命名无内容变更**：`unified_diff` 为空时的处理
2. **跨文件系统重命名**：可能实际是复制+删除
3. **权限变更**：重命名伴随权限变更的显示
4. **符号链接**：重命名符号链接 vs 目标文件

### 测试场景分析

当前测试用例：
- 源文件：`old_name.rs`
- 目标文件：`new_name.rs`
- 内容变更：1 行删除 + 1 行新增

验证点：
- 箭头符号正确显示
- 路径正确相对化
- 内容 diff 正确渲染
- 统计信息正确（+1 -1）
- 语法高亮使用 `.rs` 扩展名

### 改进建议

1. **可视化增强**：
   - 使用不同颜色区分旧路径和新路径
   - 添加重命名图标或符号
   - 显示重命名类型（移动、复制、重命名）

2. **交互功能**：
   - 点击路径跳转
   - 撤销重命名操作
   - 分别接受/拒绝重命名和内容变更

3. **信息补充**：
   - 显示重命名的原因（如果有）
   - 显示文件系统层面的操作类型
   - 检测并警告潜在的冲突

4. **配置选项**：
   - 自定义箭头符号样式
   - 是否显示完整路径
   - 重命名操作的默认行为

5. **边界处理**：
   - 更好的空 diff 处理
   - 目录重命名的特殊展示
   - 批量重命名的优化显示

6. **可访问性**：
   - 屏幕阅读器友好的重命名描述
   - 高对比度模式下的路径区分

### 相关测试

```rust
// diff_render.rs:2359-2387
#[test]
fn rename_diff_uses_destination_extension_for_highlighting() {
    // 验证重命名时使用目标扩展名进行语法高亮
    let original = "fn main() {}\n";
    let modified = "fn main() { println!(\"hi\"); }\n";
    let patch = diffy::create_patch(original, modified).to_string();

    let mut changes: HashMap<PathBuf, FileChange> = HashMap::new();
    changes.insert(
        PathBuf::from("foo.xyzzy"),  // 未知扩展名
        FileChange::Update {
            unified_diff: patch,
            move_path: Some(PathBuf::from("foo.rs")),  // 目标为 Rust 文件
        },
    );
    // 验证使用了 Rust 语法高亮
}
```

此测试验证了关键行为：即使源文件扩展名未知，只要目标文件有已知扩展名，就应该使用目标扩展名进行语法高亮。
