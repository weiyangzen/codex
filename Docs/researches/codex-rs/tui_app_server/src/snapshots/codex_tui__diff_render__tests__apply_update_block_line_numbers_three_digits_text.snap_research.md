# 三位数行号渲染测试快照研究文档

## 场景与职责

### 测试场景
本快照测试验证当代码文件行数超过100行时，diff渲染器能够正确处理三位数行号的显示对齐问题。测试场景模拟了一个包含110行的文件，在第100行处进行修改，观察行号从两位数（99）过渡到三位数（100）时的渲染表现。

### 组件职责
- **Diff渲染器** (`diff_render.rs`): 负责将代码变更（FileChange）渲染为可视化的diff输出
- **行号宽度计算** (`line_number_width`): 动态计算所需行号列宽，确保所有行号右对齐
- **行号格式化**: 使用 Rust 的格式化宏 `{:>gutter_width$}` 实现右对齐填充

### 业务价值
在实际的代码审查场景中，大型文件（如生成的代码、配置文件、长模块）的行号显示必须保持整齐对齐。如果行号宽度计算不准确，会导致以下用户体验问题：
1. 行号列宽不一致，视觉跳跃
2. 代码缩进与行号错位
3. 在终端宽度受限时内容被意外截断

## 功能点目的

### 核心功能
1. **动态行号宽度计算**: 根据文件最大行号的位数，预留足够的显示空间
2. **右对齐格式化**: 确保短行号（如"  1"）与长行号（如"100"）的个位数对齐
3. **一致性保证**: 整个diff块使用统一的行号列宽

### 测试验证点
```rust
// 测试数据构造：生成110行代码，在第100行进行修改
let original = (1..=110).map(|i| format!("line {i}\n")).collect::<String>();
let modified = (1..=110)
    .map(|i| {
        if i == 100 {
            format!("line {i} changed\n")  // 第100行被修改
        } else {
            format!("line {i}\n")
        }
    })
    .collect::<String>();
```

### 预期输出特征
从快照可以看到：
```
     97  line 97
     98  line 98
     99  line 99
    100 -line 100      ← 删除行，行号100（三位数）
    100 +line 100 changed  ← 插入行，行号100（三位数）
    101  line 101
    102  line 102
    103  line 103
```

关键观察：
- 所有行号统一使用3列宽度（因为最大行号103是三位数）
- 短行号（97-99）左侧填充空格实现右对齐
- 删除行和插入行共享相同的行号（100），表示同一位置的替换

## 具体技术实现

### 行号宽度计算算法
```rust
pub(crate) fn line_number_width(max_line_number: usize) -> usize {
    if max_line_number == 0 {
        1
    } else {
        max_line_number.to_string().len()
    }
}
```

算法逻辑：
1. 边界处理：空文件时至少返回1，确保最小列宽
2. 数字转字符串后取长度，得到所需列数
3. 对于110行文件，`"110".len() == 3`，返回3

### 行号格式化实现
在 `push_wrapped_diff_line_inner_with_theme_and_color_level` 函数中：

```rust
let ln_str = line_number.to_string();
let gutter_width = line_number_width.max(1);
let prefix_cols = gutter_width + 1;  // +1 for sign column

// 格式化行号：右对齐，预留空格
let gutter = format!("{ln_str:>gutter_width$} ");
```

格式化说明：
- `{:>gutter_width$}`: 右对齐，总宽度为 gutter_width
- 末尾空格：分隔行号与符号列（+/-/空格）

### Update类型diff的行号计算
对于 `FileChange::Update` 类型，需要遍历所有hunk计算最大行号：

```rust
for h in patch.hunks() {
    let mut old_ln = h.old_range().start();
    let mut new_ln = h.new_range().start();
    for l in h.lines() {
        match l {
            diffy::Line::Insert(_) => {
                max_line_number = max_line_number.max(new_ln);
                new_ln += 1;
            }
            diffy::Line::Delete(_) => {
                max_line_number = max_line_number.max(old_ln);
                old_ln += 1;
            }
            diffy::Line::Context(_) => {
                max_line_number = max_line_number.max(new_ln);
                old_ln += 1;
                new_ln += 1;
            }
        }
    }
}
```

## 关键代码路径与文件引用

### 核心实现文件
| 文件路径 | 功能描述 |
|---------|---------|
| `codex-rs/tui/src/diff_render.rs` | Diff渲染主实现，包含行号计算和格式化 |
| `codex-rs/tui/src/snapshots/codex_tui__diff_render__tests__apply_update_block_line_numbers_three_digits_text.snap` | 本快照文件，记录测试输出 |

### 关键函数调用链
```
ui_snapshot_apply_update_block_line_numbers_three_digits_text (test)
  └── create_diff_summary
        ├── collect_rows
        │   └── 计算每个文件的 added/removed 统计
        └── render_changes_block
              └── render_change (for each FileChange::Update)
                    ├── 计算 max_line_number (遍历所有 hunks)
                    ├── line_number_width(max_line_number) → 3
                    └── push_wrapped_diff_line_inner_with_theme_and_color_level
                          └── format!("{ln_str:>gutter_width$} ")
```

### 相关常量定义
```rust
// 位于 diff_render.rs 顶部
const TAB_WIDTH: usize = 4;  // 制表符显示宽度，与行号计算无关但同属布局系统
```

### 样式相关代码
行号 gutter 的样式由 `style_gutter_for` 函数控制：
- Dark主题：使用 `style_gutter_dim()`（简单变暗）
- Light主题：使用饱和背景色确保可读性

## 依赖与外部交互

### 外部依赖
| 依赖包 | 用途 |
|-------|------|
| `diffy` | 解析 unified diff 格式，提供 `Patch::from_str` 和 `Hunk` 结构 |
| `ratatui` | 终端UI渲染，提供 `RtLine`、`RtSpan`、`Style` 等类型 |
| `unicode-width` | Unicode字符宽度计算（本测试未直接涉及，但同属文本布局） |

### 与 codex-core 的交互
- `codex_core::git_info::get_git_repo_root`: 用于路径相对化（本测试使用根路径"/"）
- `codex_core::terminal::terminal_info`: 获取终端信息以确定颜色级别

### 与 codex-protocol 的交互
- `codex_protocol::protocol::FileChange`: 定义变更类型（Add/Delete/Update）

### 测试框架依赖
- `insta`: 快照测试框架，通过 `assert_snapshot!` 宏捕获输出
- `pretty_assertions`: 提供美观的断言差异显示

## 风险、边界与改进建议

### 已知风险

1. **超大文件行号溢出**
   - 风险：当文件超过9999行时，行号宽度可能超过预留空间
   - 影响：行号与内容列错位
   - 缓解：当前实现动态计算，理论上支持任意位数

2. **终端宽度不足**
   - 风险：窄终端（如<40列）下，行号占用过多空间
   - 影响：实际代码内容显示区域过小
   - 现状：通过 `wrap_styled_spans` 实现内容折行，但行号列宽不减

3. **零行号文件边界**
   - 处理：`line_number_width(0)` 返回1，确保最小列宽
   - 风险：极低，实际场景极少出现

### 边界条件

| 场景 | 预期行为 | 测试覆盖 |
|-----|---------|---------|
| 1-9行 | 行号宽度=1 | 间接覆盖 |
| 10-99行 | 行号宽度=2 | 间接覆盖 |
| 100-999行 | 行号宽度=3 | **本测试直接覆盖** |
| 1000+行 | 行号宽度=4+ | 未直接测试 |
| 空文件 | 行号宽度=1 | 未测试 |

### 改进建议

1. **添加千行级测试**
   ```rust
   #[test]
   fn ui_snapshot_four_digit_line_numbers() {
       let original = (1..=2000).map(|i| format!("line {i}\n")).collect::<String>();
       // ... 测试四位数行号渲染
   }
   ```

2. **考虑终端宽度自适应**
   - 当前：固定根据最大行号计算宽度
   - 建议：在极窄终端下可考虑截断行号（如显示为 `..99`）

3. **性能优化**
   - 当前：遍历所有 hunks 计算最大行号
   - 建议：对于超大diff，可考虑从patch头信息直接解析行号范围

4. **国际化考虑**
   - 当前：行号使用ASCII数字，宽度计算简单
   - 未来：如需支持其他数字系统（如阿拉伯-印度数字），需更新宽度计算

5. **可访问性增强**
   - 建议：为色盲用户添加行号前缀标识（如 `+100` 中的 `+` 符号已部分实现）
   - 建议：支持高对比度模式下的行号样式

### 相关测试补充建议
建议添加以下边界测试：
- 单行文件（1行）的行号显示
- 恰好10行、100行、1000行的边界测试
- 多文件场景下不同文件行号宽度的统一处理（当前每个文件独立计算）
