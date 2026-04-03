# Research: File Rename Diff Rendering Snapshot

## File
- **Path**: `/home/sansha/Github/codex/codex-rs/tui_app_server/src/snapshots/codex_tui_app_server__diff_render__tests__apply_update_with_rename_block.snap`
- **Source**: `tui_app_server/src/diff_render.rs`
- **Test**: `ui_snapshot_apply_update_with_rename_block`

---

## 场景与职责

### 应用场景
该 snapshot 测试验证 Codex TUI 应用服务器在渲染文件重命名（rename/move）操作时的 diff 显示效果。当用户通过 Codex 工具执行文件重命名并伴随内容修改时，系统需要清晰地展示：
1. 源文件路径到目标文件路径的映射关系
2. 文件内容的变更（增加/删除行）
3. 变更统计信息（+N -M）

### 职责定位
- **UI 渲染层**：负责将内部 `FileChange::Update` 数据结构转换为可视化的 diff 输出
- **路径展示**：处理重命名场景下的路径显示逻辑（`old_name.rs → new_name.rs`）
- **变更汇总**：计算并展示文件变更的统计信息

---

## 功能点目的

### 核心功能
1. **重命名路径展示**：在 diff 头部使用箭头符号（→）清晰标识文件重命名操作
2. **统一 Diff 渲染**：展示 unified diff 格式，包含行号、变更标记（+/-）、上下文行
3. **变更统计**：在头部显示 `(+1 -1)` 格式的增删行数统计

### Snapshot 内容解析
```
"• Edited old_name.rs → new_name.rs (+1 -1)"
"    1  A"               # 上下文行（无变更）
"    2 -B"               # 删除行
"    2 +B changed"       # 插入行（替换原第2行）
"    3  C"               # 上下文行（无变更）
```

### 视觉设计
- **Header 前缀**：`•` 符号 + 操作类型（Edited）+ 路径箭头 + 统计
- **缩进层次**：4空格缩进区分 header 与 diff 内容
- **行号对齐**：右对齐行号，保持视觉一致性
- **变更标记**：`-` 表示删除，`+` 表示插入，空格表示上下文

---

## 具体技术实现

### 数据结构
```rust
// FileChange::Update 定义（protocol/src/protocol.rs）
pub enum FileChange {
    Update {
        unified_diff: String,      // Unified diff 文本
        move_path: Option<PathBuf>, // 重命名目标路径（Some 表示重命名）
    },
    // ...
}
```

### 渲染流程
1. **路径渲染**（`render_changes_block` 函数，line 402-464）
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

2. **Header 生成**（line 419-436）
   - 单文件场景：显示 `"Edited"` + 路径箭头 + 统计
   - 多文件场景：显示 `"Edited N files"` + 总统计

3. **行号宽度计算**（`line_number_width` 函数，line 1022-1028）
   ```rust
   pub(crate) fn line_number_width(max_line_number: usize) -> usize {
       if max_line_number == 0 { 1 } else { max_line_number.to_string().len() }
   }
   ```

4. **Diff 内容渲染**（`render_change` 函数，line 474-736）
   - 使用 `diffy::Patch::from_str` 解析 unified diff
   - 遍历 hunk，为每行生成带行号、标记、内容的输出行

### 测试实现
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
            move_path: Some(PathBuf::from("new_name.rs")), // 关键：设置重命名路径
        },
    );

    let lines = diff_summary_for_tests(&changes);
    snapshot_lines("apply_update_with_rename_block", lines, 80, 12);
}
```

---

## 关键代码路径与文件引用

### 核心文件
| 文件 | 职责 |
|------|------|
| `tui_app_server/src/diff_render.rs` | Diff 渲染主逻辑，包含 `render_changes_block`、`render_change` 等函数 |
| `protocol/src/protocol.rs` | `FileChange` 枚举定义 |
| `tui_app_server/src/render/line_utils.rs` | `prefix_lines` 工具函数，用于添加行前缀 |

### 关键函数
| 函数 | 位置 | 职责 |
|------|------|------|
| `render_changes_block` | line 402-464 | 渲染变更块，处理 header 和文件列表 |
| `render_change` | line 474-736 | 渲染单个文件变更的 diff 内容 |
| `display_path_for` | line 741-762 | 路径显示格式化（相对路径、home 目录缩写等） |
| `push_wrapped_diff_line_inner_with_theme_and_color_level` | line 838-938 | 核心行渲染，处理行号、标记、内容、换行 |
| `line_number_width` | line 1022-1028 | 计算行号列宽度 |

### 渲染调用链
```
create_diff_summary
  └── render_changes_block
       ├── render_path (处理重命名箭头)
       ├── render_line_count_summary (统计信息)
       └── render_change (diff 内容)
            └── push_wrapped_diff_line_inner_with_theme_and_color_level
```

---

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|------|------|
| `diffy` | Unified diff 解析与生成 |
| `ratatui` | 终端 UI 渲染框架（`Line`, `Span`, `Paragraph` 等） |
| `unicode-width` | Unicode 字符宽度计算 |
| `pathdiff` | 路径差异计算（用于相对路径显示） |

### 内部模块依赖
```rust
use crate::color::is_light;
use crate::color::perceptual_distance;
use crate::exec_command::relativize_to_home;
use crate::render::Insets;
use crate::render::highlight::{DiffScopeBackgroundRgbs, diff_scope_background_rgbs, ...};
use crate::render::line_utils::prefix_lines;
use crate::render::renderable::{ColumnRenderable, InsetRenderable, Renderable};
use crate::terminal_palette::{StdoutColorLevel, XTERM_COLORS, ...};
use codex_core::git_info::get_git_repo_root;
use codex_core::terminal::{TerminalName, terminal_info};
use codex_protocol::protocol::FileChange;
```

---

## 风险、边界与改进建议

### 潜在风险
1. **路径长度溢出**：当源路径和目标路径都很长时，header 行可能超出终端宽度
2. **特殊字符处理**：文件名包含特殊字符（如箭头符号 → 本身）可能导致显示混淆
3. **多字节字符对齐**：CJK 字符、emoji 等宽字符可能影响行号对齐

### 边界情况
| 场景 | 当前行为 |
|------|----------|
| 仅重命名无内容变更 | 仍显示 `(+0 -0)` 统计 |
| 路径包含空格 | 正常显示，无引号包裹 |
| 跨目录重命名 | 显示完整相对路径箭头 |
| 绝对路径输入 | 通过 `display_path_for` 转换为相对路径或 `~/` 形式 |

### 改进建议
1. **路径截断**：当路径组合过长时，考虑中间截断（如 `src/.../old.rs → src/.../new.rs`）
2. **语法高亮**：重命名文件时，使用目标路径的扩展名决定语法高亮语言（已实现，见 `detect_lang_for_path`）
3. **颜色区分**：为重命名箭头（→）添加独立颜色，增强视觉识别
4. **统计优化**：当变更行为 0 时，可考虑隐藏统计或显示更友好的信息

### 相关测试覆盖
- `ui_snapshot_apply_update_with_rename_block`：重命名场景（本 snapshot）
- `rename_diff_uses_destination_extension_for_highlighting`：验证重命名后使用目标扩展名高亮
- `ui_snapshot_apply_update_block_relativizes_path`：路径相对化显示
