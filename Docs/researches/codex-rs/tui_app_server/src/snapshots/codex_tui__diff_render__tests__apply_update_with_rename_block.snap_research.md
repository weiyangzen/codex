# 文件重命名与内容更新测试快照研究文档

## 场景与职责

### 测试场景
本快照测试验证当文件被重命名（移动）同时内容发生变更时的diff渲染。测试构造了一个场景：文件从 `old_name.rs` 重命名为 `new_name.rs`，同时内容从 "B" 修改为 "B changed"。

### 业务场景
在实际开发中，文件重命名伴随内容修改的常见情况：
1. **重构重命名**：类/函数重命名时，文件名同步变更
2. **语言迁移**：如 `.js` 文件改为 `.ts` 并添加类型注解
3. **目录重组**：移动文件到更合适的位置，同时修复相关问题
4. **模板生成**：从模板文件生成实际文件，内容被定制

### 组件职责
- **重命名检测** (`move_path`): 识别文件变更类型为"移动+更新"
- **路径显示** (`render_path`): 同时显示源路径和目标路径
- **语言检测** (`detect_lang_for_path`): 根据目标路径扩展名选择语法高亮
- **统计计算**: 正确统计新增/删除行数（仅计算内容变更，不包括重命名本身）

## 功能点目的

### 核心功能
1. **重命名可视化**: 使用箭头符号 `→` 清晰表示文件重命名
2. **统一diff显示**: 将重命名和内容变更整合为单一视图
3. **语言感知**: 根据新文件名确定语法高亮规则
4. **准确统计**: 仅统计实际代码变更，不包括重命名操作

### 测试验证点
```rust
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
```

### 预期输出分析
```
"• Edited old_name.rs → new_name.rs (+1 -1)                                      "
"    1  A                                                                        "
"    2 -B                                                                        "
"    2 +B changed                                                                "
"    3  C                                                                        "
```

关键观察：
- 标题行显示 `old_name.rs → new_name.rs`，明确指示重命名
- 统计 `(+1 -1)` 表示1行新增、1行删除（仅内容变更）
- 第2行被修改：删除原内容 "B"，插入新内容 "B changed"
- 行号显示：删除行和插入行都标记为第2行

## 具体技术实现

### 数据结构定义
```rust
// 来自 codex_protocol::protocol::FileChange
pub enum FileChange {
    Add { content: String },
    Delete { content: String },
    Update { 
        unified_diff: String, 
        move_path: Option<PathBuf>  // 可选的重命名目标
    },
}

// 内部使用的 Row 结构
struct Row {
    path: PathBuf,           // 源路径
    move_path: Option<PathBuf>,  // 目标路径（如有）
    added: usize,            // 新增行数
    removed: usize,          // 删除行数
    change: FileChange,
}
```

### 重命名路径提取
```rust
fn collect_rows(changes: &HashMap<PathBuf, FileChange>) -> Vec<Row> {
    for (path, change) in changes.iter() {
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
            // ...
        });
    }
}
```

### 路径渲染逻辑
```rust
fn render_path(row: &Row) -> Vec<RtSpan<'static>> {
    let mut spans = Vec::new();
    // 源路径
    spans.push(display_path_for(&row.path, cwd).into());
    
    // 如有重命名，添加箭头和目标路径
    if let Some(move_path) = &row.move_path {
        spans.push(format!(" → {}", display_path_for(move_path, cwd)).into());
    }
    spans
}
```

### 语言检测优化
```rust
fn render_changes_block(rows: Vec<Row>, wrap_cols: usize, cwd: &Path) -> Vec<RtLine<'static>> {
    for r in rows {
        // 对于重命名，使用目标路径的扩展名进行语法高亮
        // 因为diff内容反映的是新文件的状态
        let lang_path = r.move_path.as_deref().unwrap_or(&r.path);
        let lang = detect_lang_for_path(lang_path);
        
        render_change(&r.change, &mut lines, wrap_cols - 4, lang.as_deref());
    }
}

fn detect_lang_for_path(path: &Path) -> Option<String> {
    let ext = path.extension()?.to_str()?;
    Some(ext.to_string())  // 返回扩展名，如 "rs"
}
```

### 统计计算
```rust
fn calculate_add_remove_from_diff(diff: &str) -> (usize, usize) {
    if let Ok(patch) = diffy::Patch::from_str(diff) {
        patch
            .hunks()
            .iter()
            .flat_map(Hunk::lines)
            .fold((0, 0), |(a, d), l| match l {
                diffy::Line::Insert(_) => (a + 1, d),
                diffy::Line::Delete(_) => (a, d + 1),
                diffy::Line::Context(_) => (a, d),
            })
    } else {
        (0, 0)
    }
}
```

## 关键代码路径与文件引用

### 核心实现文件
| 文件路径 | 功能描述 |
|---------|---------|
| `codex-rs/tui/src/diff_render.rs` | 包含重命名处理和渲染逻辑 |
| `codex-protocol/src/protocol.rs` | `FileChange` 枚举定义（含 `move_path`） |
| `codex-rs/tui/src/snapshots/codex_tui__diff_render__tests__apply_update_with_rename_block.snap` | 本快照文件 |

### 关键函数调用链
```
ui_snapshot_apply_update_with_rename_block (test)
  └── create_diff_summary(&changes, &PathBuf::from("/"), 80)
        ├── collect_rows(&changes)
        │   └── 遍历 changes
        │       └── 提取 move_path → Row { path: "old_name.rs", move_path: Some("new_name.rs"), ... }
        └── render_changes_block(rows, 80, cwd)
            ├── render_path(&row) for header
            │   ├── display_path_for("old_name.rs", cwd) → "old_name.rs"
            │   ├── display_path_for("new_name.rs", cwd) → "new_name.rs"
            │   └── format!(" → {}", ...) → "old_name.rs → new_name.rs"
            ├── detect_lang_for_path("new_name.rs") → Some("rs")
            └── render_change(&r.change, ...)
                └── FileChange::Update 分支
                    ├── diffy::Patch::from_str(&unified_diff)
                    ├── 计算 max_line_number → 3
                    └── 逐行渲染 diff
```

### 相关数据结构关系
```
FileChange::Update
    ├── unified_diff: String  →  diffy::Patch → hunks → lines
    └── move_path: Option<PathBuf>  →  Some("new_name.rs")
            │
            ▼
Row {
    path: "old_name.rs",
    move_path: Some("new_name.rs"),
    added: 1,
    removed: 1,
    change: FileChange::Update { ... }
}
            │
            ▼
渲染输出: "old_name.rs → new_name.rs (+1 -1)"
```

## 依赖与外部交互

### 与 codex-protocol 的交互
```rust
use codex_protocol::protocol::FileChange;
```

`FileChange::Update` 的完整定义：
```rust
Update {
    unified_diff: String,        // 标准unified diff格式
    move_path: Option<PathBuf>,  // 可选：文件被移动/重命名到此路径
}
```

### 与 diffy 的交互
```rust
use diffy::{Patch, Hunk, Line};

// 解析 unified diff
let patch = diffy::Patch::from_str(&unified_diff)?;

// 遍历 hunk
for hunk in patch.hunks() {
    for line in hunk.lines() {
        match line {
            Line::Insert(text) => { /* ... */ }
            Line::Delete(text) => { /* ... */ }
            Line::Context(text) => { /* ... */ }
        }
    }
}
```

### 统计信息渲染
```rust
fn render_line_count_summary(added: usize, removed: usize) -> Vec<RtSpan<'static>> {
    let mut spans = Vec::new();
    spans.push("(".into());
    spans.push(format!("+{added}").green());  // 新增行绿色
    spans.push(" ".into());
    spans.push(format!("-{removed}").red());  // 删除行红色
    spans.push(")".into());
    spans
}
```

## 风险、边界与改进建议

### 已知风险

1. **路径冲突**
   - 风险：`move_path` 指向已存在的文件
   - 现状：渲染层不处理冲突，仅显示信息
   - 建议：添加警告标识

2. **循环重命名**
   - 风险：A→B 和 B→A 同时出现在同一变更集
   - 现状：未检测，可能导致显示混乱
   - 建议：添加冲突检测

3. **跨目录重命名显示**
   - 风险：长路径导致箭头格式溢出
   - 现状：依赖终端折行或水平滚动
   - 示例：`very/long/path/to/old_name.rs → another/very/long/path/to/new_name.rs`

4. **大小写敏感**
   - 风险：在某些文件系统（Windows）上，`file.rs` → `File.rs` 是重命名
   - 现状：按字符串比较，可能误判

### 边界条件

| 场景 | 预期行为 | 测试状态 |
|-----|---------|---------|
| move_path = None | 普通Update，无箭头 | 未测试 |
| move_path = 空路径 | 显示异常 | 未测试 |
| move_path = 源路径 | 无实际重命名 | 未测试 |
| 源路径不存在 | 仅显示，不验证 | 未测试 |
| 目标路径已存在 | 无警告 | 未测试 |
| 多次重命名链 | 仅显示直接重命名 | 未测试 |

### 改进建议

1. **添加重命名类型标识**
   ```rust
   enum RenameType {
       PureRename,      // 仅重命名，无内容变更
       RenameAndUpdate, // 重命名+内容变更（本测试场景）
       Copy,            // 复制文件（未来扩展）
   }
   ```

2. **增强路径显示**
   ```rust
   // 对于长路径，考虑显示差异部分
   src/components/old_button.tsx → src/components/new_button.tsx
   // 可简化为：
   src/components/{old_button → new_button}.tsx
   ```

3. **添加文件类型变更指示**
   ```rust
   // 当扩展名变更时，特别标注
   script.js → script.ts  [JavaScript → TypeScript]
   ```

4. **冲突检测**
   ```rust
   fn validate_renames(rows: &[Row]) -> Result<(), RenameError> {
       let mut target_paths: HashSet<&Path> = HashSet::new();
       for row in rows {
           if let Some(target) = &row.move_path {
               if !target_paths.insert(target) {
                   return Err(RenameError::DuplicateTarget(target.clone()));
               }
           }
       }
       Ok(())
   }
   ```

5. **添加更多测试场景**
   ```rust
   #[test]
   fn rename_without_content_change() {
       // 纯重命名，diff为空或仅上下文
   }
   
   #[test]
   fn rename_with_extension_change() {
       // .js → .ts 的场景
   }
   
   #[test]
   fn rename_cross_directory() {
       // 跨目录移动
   }
   
   #[test]
   fn multiple_files_one_renamed() {
       // 多文件变更中只有一个重命名
   }
   ```

6. **性能优化**
   ```rust
   // 当前：每个文件单独检测语言
   // 建议：缓存扩展名到语言的映射
   static LANG_CACHE: Lazy<Mutex<HashMap<String, Option<String>>>> = ...;
   ```

7. **可访问性增强**
   ```rust
   // 为色盲用户提供额外标识
   spans.push(" [R]".dim());  // 重命名标记
   ```

8. **国际化路径**
   ```rust
   // 确保Unicode路径正确显示
   #[test]
   fn rename_with_unicode_paths() {
       let old = "旧文件.rs";
       let new = "新文件.rs";
       // ...
   }
   ```

### 相关代码审查建议

当前 `render_changes_block` 函数较长，建议将重命名相关逻辑提取：

```rust
impl Row {
    fn display_name(&self, cwd: &Path) -> String {
        let source = display_path_for(&self.path, cwd);
        match &self.move_path {
            Some(target) => {
                let target = display_path_for(target, cwd);
                format!("{} → {}", source, target)
            }
            None => source,
        }
    }
    
    fn language_hint(&self) -> Option<String> {
        let path = self.move_path.as_ref().unwrap_or(&self.path);
        detect_lang_for_path(path)
    }
}
```

这样可以简化 `render_changes_block` 的主逻辑：
```rust
for r in rows {
    let display_name = r.display_name(cwd);
    let lang = r.language_hint();
    // ...
}
```
