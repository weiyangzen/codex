# Diff Render - 多文件变更块渲染测试

## 场景与职责

该快照测试验证 TUI 中**多文件同时变更**的 diff 渲染效果。当 Codex 在一次操作中修改多个文件时，需要在一个统一的视图中展示所有变更，提供汇总统计和逐文件详情，帮助用户快速理解整体变更范围。

此组件是 Codex TUI 的核心 diff 展示功能，支持混合展示添加、删除、更新等多种变更类型。

## 功能点目的

1. **汇总统计**：顶部显示编辑文件总数和整体变更统计（`Edited 2 files (+2 -1)`）
2. **逐文件展示**：每个文件独立展示，包含文件名和单独统计
3. **层级结构**：使用树形结构（`└`）展示文件层级关系
4. **变更类型区分**：
   - 更新操作：显示删除行（`-`）和新增行（`+`）
   - 添加操作：仅显示新增行（`+`）
5. **路径相对化**：将绝对路径转换为相对于工作目录的相对路径

## 具体技术实现

### 核心数据结构

```rust
// Row 结构：内部使用的文件变更行表示
struct Row {
    path: PathBuf,           // 文件路径
    move_path: Option<PathBuf>, // 重命名目标路径
    added: usize,            // 新增行数
    removed: usize,          // 删除行数
    change: FileChange,      // 变更详情
}

// FileChange 枚举
pub enum FileChange {
    Add { content: String },
    Delete { content: String },
    Update { unified_diff: String, move_path: Option<PathBuf> },
}
```

### 渲染流程

1. **数据收集**（`collect_rows`）：
   - 遍历所有变更，计算每个文件的 added/removed 统计
   - 按路径排序确保稳定输出

2. **头部渲染**（`render_changes_block`）：
   ```rust
   if let [row] = &rows[..] {
       // 单文件：显示 "Added/Deleted/Edited <path> (+x -y)"
   } else {
       // 多文件：显示 "Edited N files (+total_add -total_del)"
   }
   ```

3. **逐文件渲染**：
   - 文件路径 + 统计（`└ a.txt (+1 -1)`）
   - 缩进后的 diff 内容（4空格缩进）

### 统计计算

```rust
fn calculate_add_remove_from_diff(diff: &str) -> (usize, usize) {
    // 解析统一 diff 格式，统计 Insert/Delete 行数
    patch.hunks().iter().flat_map(Hunk::lines).fold((0, 0), |(a, d), l| match l {
        diffy::Line::Insert(_) => (a + 1, d),
        diffy::Line::Delete(_) => (a, d + 1),
        diffy::Line::Context(_) => (a, d),
    })
}
```

### 关键代码路径

```rust
// diff_render.rs:402-464
fn render_changes_block(rows: Vec<Row>, wrap_cols: usize, cwd: &Path) -> Vec<RtLine<'static>> {
    // 1. 计算总计统计
    let total_added: usize = rows.iter().map(|r| r.added).sum();
    let total_removed: usize = rows.iter().map(|r| r.removed).sum();
    
    // 2. 渲染头部
    let mut header_spans: Vec<RtSpan<'static>> = vec!["• ".dim()];
    header_spans.push("Edited".bold());
    header_spans.push(format!(" {file_count} {noun} ").into());
    header_spans.extend(render_line_count_summary(total_added, total_removed));
    
    // 3. 逐文件渲染
    for (idx, r) in rows.into_iter().enumerate() {
        // 文件头："  └ a.txt (+1 -1)"
        // diff 内容（缩进）
    }
}
```

## 关键代码路径与文件引用

| 组件 | 文件路径 | 职责 |
|------|----------|------|
| Diff 渲染主模块 | `codex-rs/tui/src/diff_render.rs` | 完整的 diff 渲染实现 |
| 统计计算 | `diff_render.rs:764-779` | `calculate_add_remove_from_diff` |
| 行收集 | `diff_render.rs:365-390` | `collect_rows` 函数 |
| 块渲染 | `diff_render.rs:402-464` | `render_changes_block` 函数 |
| 测试用例 | `diff_render.rs:1548-1574` | `ui_snapshot_apply_multiple_files_block` |

### 相关函数

- `collect_rows()` - 收集并排序文件变更
- `render_changes_block()` - 渲染多文件变更块
- `render_line_count_summary()` - 渲染 (+x -y) 统计
- `display_path_for()` - 路径相对化显示

## 依赖与外部交互

### 外部依赖

1. **diffy**：统一 diff 格式解析和创建
2. **ratatui**：终端 UI 渲染框架
3. **pathdiff**：路径差异计算

### 内部依赖

- `codex_core::git_info::get_git_repo_root` - Git 仓库根目录检测
- `crate::render::line_utils::prefix_lines` - 行前缀添加工具

### 数据流

```
HashMap<PathBuf, FileChange>
    ↓ collect_rows()
Vec<Row> (sorted by path)
    ↓ render_changes_block()
Vec<RtLine<'static>> (ratatui 行数据)
    ↓ Terminal::draw()
终端输出
```

## 风险、边界与改进建议

### 潜在风险

1. **大量文件性能**：当同时修改数百个文件时，渲染可能变慢
2. **路径排序**：当前按路径字符串排序，可能不符合用户预期
3. **长路径截断**：深层嵌套路径可能超出终端宽度

### 边界情况

1. **空变更集**：`changes` 为空 HashMap 时的处理
2. **单文件 vs 多文件**：头部格式根据文件数量变化
3. **混合变更类型**：Add/Delete/Update 混合时的统一展示
4. **文件重命名**：`move_path` 存在时的路径显示（`old → new`）

### 改进建议

1. **分页/折叠**：
   - 当文件数量超过阈值时，提供折叠功能
   - 支持展开/收起单个文件的 diff

2. **交互增强**：
   - 支持按文件名搜索过滤
   - 支持按变更类型筛选
   - 文件跳转快捷键

3. **可视化优化**：
   - 添加文件图标（根据扩展名）
   - 使用不同颜色区分 Add/Delete/Update
   - 进度条显示整体审查进度

4. **性能优化**：
   - 虚拟滚动：只渲染可见区域的文件
   - 延迟加载：大文件 diff 按需加载

5. **配置选项**：
   - 自定义排序方式（按路径、按变更大小、按类型）
   - 最大显示文件数限制
   - 是否显示未变更的上下文行

### 测试覆盖

当前测试用例验证了：
- 两文件混合场景（Update + Add）
- 汇总统计正确性（+2 -1）
- 逐文件统计正确性（a.txt: +1 -1, b.txt: +1 -0）
- 树形缩进格式

建议补充：
- 大量文件（100+）性能测试
- 深层嵌套路径显示测试
- 混合 Add/Delete/Update 的复杂场景
