# Research: codex_tui_app_server__diff_render__tests__apply_update_block_line_numbers_three_digits_text.snap

## 场景与职责

此快照测试文件专门验证 Codex TUI 应用服务器在处理大文件（超过 100 行）时的行号对齐功能。当文件行数达到三位数时，行号列的宽度需要动态调整以确保所有行号右对齐，差异标记（+/-/ ）和内容保持一致的缩进。

**应用场景：**
- 大型源代码文件的差异展示
- 确保行号从个位数过渡到三位数时的视觉对齐
- 验证行号宽度计算的准确性

**测试特点：**
- 生成包含 110 行的测试数据
- 在第 100 行进行修改，触发三位数行号的显示
- 验证行号宽度从 2 位（99）到 3 位（100）的过渡

## 功能点目的

### 1. 动态行号宽度计算
```
     97  line 97
     98  line 98
     99  line 99
    100 -line 100
    100 +line 100 changed
    101  line 101
    102  line 102
    103  line 103
```

**观察要点：**
- 97-99 行：行号前 5 个空格（右对齐到宽度 3）
- 100-103 行：行号前 4 个空格（右对齐到宽度 3）
- 所有行号统一使用 3 字符宽度，确保对齐

### 2. 行号宽度算法
测试验证了 `line_number_width` 函数的正确性：
```rust
pub(crate) fn line_number_width(max_line_number: usize) -> usize {
    if max_line_number == 0 {
        1
    } else {
        max_line_number.to_string().len()
    }
}
```

对于最大行号 110，返回 `3`（"110".len() = 3）。

### 3. 差异标记对齐
- 删除行（`-`）：显示旧文件行号（100）
- 新增行（`+`）：显示新文件行号（100）
- 上下文行（` `）：显示新文件行号

## 具体技术实现

### 测试数据构造
```rust
#[test]
fn ui_snapshot_apply_update_block_line_numbers_three_digits_text() {
    let original = (1..=110).map(|i| format!("line {i}\n")).collect::<String>();
    let modified = (1..=110)
        .map(|i| {
            if i == 100 {
                format!("line {i} changed\n")
            } else {
                format!("line {i}\n")
            }
        })
        .collect::<String>();
    let patch = diffy::create_patch(&original, &modified).to_string();

    let mut changes: HashMap<PathBuf, FileChange> = HashMap::new();
    changes.insert(
        PathBuf::from("hundreds.txt"),
        FileChange::Update {
            unified_diff: patch,
            move_path: None,
        },
    );

    let lines = create_diff_summary(&changes, &PathBuf::from("/"), 80);
    snapshot_lines_text("apply_update_block_line_numbers_three_digits_text", &lines);
}
```

### 行号渲染实现
在 `push_wrapped_diff_line_inner_with_theme_and_color_level` 函数（第 838-938 行）：

```rust
let ln_str = line_number.to_string();
let gutter_width = line_number_width.max(1);
let prefix_cols = gutter_width + 1;

// 格式化行号，右对齐
let gutter = format!("{ln_str:>gutter_width$} ");
```

**格式化说明：**
- `{ln_str:>gutter_width$}`：右对齐，宽度为 `gutter_width`
- 尾随空格：分隔行号和符号列

### 行号列样式
```rust
fn style_gutter_for(kind: DiffLineType, theme: DiffTheme, color_level: DiffColorLevel) -> Style {
    match (theme, kind, RichDiffColorLevel::from_diff_color_level(color_level)) {
        // Light 主题：使用饱和背景确保可读性
        (DiffTheme::Light, DiffLineType::Insert, Some(level)) => Style::default()
            .fg(light_gutter_fg(color_level))
            .bg(light_add_num_bg(level)),
        (DiffTheme::Light, DiffLineType::Delete, Some(level)) => Style::default()
            .fg(light_gutter_fg(color_level))
            .bg(light_del_num_bg(level)),
        // Dark 主题：使用 DIM 修饰符
        _ => style_gutter_dim(),
    }
}
```

## 关键代码路径与文件引用

### 主要源文件
- **`codex-rs/tui_app_server/src/diff_render.rs`**
  - 第 1648-1673 行：`ui_snapshot_apply_update_block_line_numbers_three_digits_text` 测试函数
  - 第 1022-1028 行：`line_number_width` 函数
  - 第 838-938 行：`push_wrapped_diff_line_inner_with_theme_and_color_level` 核心渲染函数
  - 第 1199-1219 行：`style_gutter_for` 行号列样式函数

### 关键调用链
```
ui_snapshot_apply_update_block_line_numbers_three_digits_text
  └── create_diff_summary(&changes, &PathBuf::from("/"), 80)
        └── render_changes_block(rows, wrap_cols, cwd)
              └── render_change(&r.change, &mut lines, wrap_cols - 4, lang.as_deref())
                    └── push_wrapped_diff_line_inner_with_theme_and_color_level
                          ├── line_number_width(max_line_number)  // 计算宽度
                          └── style_gutter_for(...)               // 应用样式
```

### 辅助函数
- `snapshot_lines_text`（第 1387-1402 行）：将行转换为纯文本并生成快照

## 依赖与外部交互

### 核心依赖
| 组件 | 用途 |
|------|------|
| `diffy::create_patch` | 生成统一差异格式 |
| `ratatui::text::Line` | 文本行表示 |
| `insta::assert_snapshot` | 快照断言 |

### 样式常量
```rust
// Light 主题行号背景色
const LIGHT_TC_ADD_NUM_BG_RGB: (u8, u8, u8) = (172, 238, 187); // #aceebb
const LIGHT_TC_DEL_NUM_BG_RGB: (u8, u8, u8) = (255, 206, 203); // #ffcecb
const LIGHT_TC_GUTTER_FG_RGB: (u8, u8, u8) = (31, 35, 40);     // #1f2328
```

## 风险、边界与改进建议

### 潜在风险

1. **行号溢出**
   - 当文件超过 9999 行时，行号宽度变为 4 位
   - 当前实现支持任意宽度，但需要验证超大文件的性能

2. **内存使用**
   - 测试生成 110 行数据，实际文件可能有数万行
   - `create_diff_summary` 需要存储所有行数据

3. **性能瓶颈**
   - 大文件的行号宽度计算需要遍历所有 hunks 找最大行号
   - 代码位置：`render_change` 函数第 549-579 行

### 边界情况

1. **零行文件**
   ```rust
   // line_number_width(0) 返回 1
   // 确保至少有 1 字符宽度
   ```

2. **行号对齐与换行**
   - 当长行需要换行时，续行使用空 gutter 保持对齐
   ```rust
   let cont_gutter = format!("{:gutter_width$}  ", "");
   ```

3. **多字节字符**
   - 行号计算使用字符数，不是字节数
   - Unicode 行号（如阿拉伯数字）可能产生意外结果

### 改进建议

1. **添加更多位数测试**
   ```rust
   // 建议添加：
   #[test]
   fn ui_snapshot_four_digit_line_numbers() {
       // 测试 1000+ 行的文件
   }
   
   #[test]
   fn ui_snapshot_mixed_digit_widths() {
       // 测试包含 9, 10, 99, 100, 999, 1000 行的边界
   }
   ```

2. **性能优化**
   ```rust
   // 当前：两次遍历（计算最大行号 + 渲染）
   // 优化：单次遍历，使用 Vec 收集，最后确定宽度
   ```

3. **可配置行号显示**
   ```rust
   // 建议添加配置选项：
   pub struct DiffRenderConfig {
       show_line_numbers: bool,
       line_number_padding: usize,
       relative_line_numbers: bool,  // 相对行号模式
   }
   ```

4. **行号分隔符自定义**
   - 当前使用空格分隔行号和符号
   - 支持自定义分隔符（如 `|`）以提高可读性

5. **行号颜色可配置**
   - 当前 Light 主题使用固定颜色
   - 允许用户自定义行号前景/背景色

### 相关测试文件
- `codex_tui_app_server__diff_render__tests__apply_update_block.snap` - 基础差异渲染测试
- `codex_tui_app_server__diff_render__tests__apply_update_block_wraps_long_lines.snap` - 长行换行与行号对齐测试
