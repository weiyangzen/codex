# Vertical Ellipsis Between Hunks 快照研究文档

## 场景与职责

此快照测试展示了**多 hunk（差异块）之间的垂直省略号**渲染。当文件的变更是分散的多个独立区域时，统一 diff 会生成多个 hunk，此功能在这些 hunk 之间显示省略号以指示内容的省略。

### 测试场景
- **文件**: `example.txt`
- **变更**: 两处独立的修改
  - 第 2 行：`line 2` → `line two changed`
  - 第 9 行：`line 9` → `line nine changed`
- **统计**: `(+2 -2)`
- **hunk 分隔**: 使用 `⋮` (U+22EE) 垂直省略号

### 核心验证点
1. 多个 hunk 正确识别和渲染
2. hunk 之间显示 `⋮` 分隔符
3. 上下文行（第 1-5 行，第 6-10 行）正确显示
4. 行号在两处变更处正确对齐

## 功能点目的

### 1. 多 Hunk 识别
- diffy 解析统一差异，识别多个 hunk
- 每个 hunk 包含独立的变更区域和上下文

### 2. 视觉分隔
- 使用 `⋮` 符号指示中间有省略的内容
- 帮助用户理解文件结构，区分不相关的变更区域

### 3. 上下文保持
- 每个 hunk 显示变更前后的上下文行（默认 3 行）
- 行号连续，便于定位

## 具体技术实现

### Hunk 遍历与分隔

```rust
FileChange::Update { unified_diff, .. } => {
    if let Ok(patch) = diffy::Patch::from_str(unified_diff) {
        let line_number_width = line_number_width(max_line_number);
        let mut is_first_hunk = true;
        
        for h in patch.hunks() {
            // 在非首个 hunk 前添加分隔符
            if !is_first_hunk {
                let spacer = format!("{:width$} ", "", width = line_number_width.max(1));
                let spacer_span = RtSpan::styled(
                    spacer,
                    style_gutter_for(
                        DiffLineType::Context,
                        style_context.theme,
                        style_context.color_level,
                    ),
                );
                out.push(RtLine::from(vec![spacer_span, "⋮".dim()]));
            }
            is_first_hunk = false;
            
            // 渲染 hunk 内容...
        }
    }
}
```

### 分隔符样式

```rust
// 分隔符使用 Context 类型的 gutter 样式
// 在深色主题下为 dim 样式
// 在浅色主题下有特定的背景色

let spacer = format!("{:width$} ", "", width = line_number_width.max(1));
// 例如，行号宽度为 2 时，spacer = "   "（3 空格）

out.push(RtLine::from(vec![
    RtSpan::styled(spacer, gutter_style),  // 空白 gutter
    "⋮".dim()                               // 垂直省略号，dim 样式
]));
```

### 测试数据生成

```rust
// 创建包含两个独立变更的 diff
let original = "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\n";
let modified = "line 1\nline two changed\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline nine changed\nline 10\n";
```

生成的统一差异类似：
```diff
--- a/example.txt
+++ b/example.txt
@@ -1,5 +1,5 @@
 line 1
-line 2
+line two changed
 line 3
 line 4
 line 5
@@ -7,5 +7,5 @@
 line 7
 line 8
-line 9
+line nine changed
 line 10
```

注意两个 `@@` 开头的 hunk 头，表示两个独立的变更区域。

## 关键代码路径与文件引用

### 核心代码

| 代码段 | 位置 | 职责 |
|--------|------|------|
| hunk 分隔逻辑 | diff_render.rs:592-604 | 检测非首个 hunk 并添加分隔符 |
| 分隔符渲染 | diff_render.rs:603 | 创建 `⋮` 分隔行 |
| hunk 遍历 | diff_render.rs:592 | 遍历所有 hunk 进行渲染 |

### 相关类型

```rust
// diffy::Hunk 结构
pub struct Hunk<'a> {
    old_range: Range,
    new_range: Range,
    lines: Vec<Line<'a>>,
}

pub struct Range {
    start: usize,  // 起始行号
    count: usize,  // 行数
}
```

### 样式上下文

```rust
// 分隔符使用 Context 类型的样式
fn style_gutter_for(kind: DiffLineType, theme: DiffTheme, color_level: DiffColorLevel) -> Style {
    match (theme, kind, RichDiffColorLevel::from_diff_color_level(color_level)) {
        // ...
        _ => style_gutter_dim(),  // 默认使用 dim 样式
    }
}

fn style_gutter_dim() -> Style {
    Style::default().add_modifier(Modifier::DIM)
}
```

## 依赖与外部交互

### diffy Hunk 处理

```rust
use diffy::Patch;

let patch = diffy::Patch::from_str(unified_diff)?;
for hunk in patch.hunks() {
    let old_start = hunk.old_range().start();
    let new_start = hunk.new_range().start();
    // ...
}
```

### 行号追踪

```rust
let mut old_ln = h.old_range().start();
let mut new_ln = h.new_range().start();

for l in h.lines() {
    match l {
        diffy::Line::Insert(_) => {
            // 使用 new_ln 渲染
            new_ln += 1;
        }
        diffy::Line::Delete(_) => {
            // 使用 old_ln 渲染
            old_ln += 1;
        }
        diffy::Line::Context(_) => {
            // 使用 new_ln（或 old_ln）渲染
            old_ln += 1;
            new_ln += 1;
        }
    }
}
```

## 风险、边界与改进建议

### 边界情况

1. **相邻 Hunk**
   - 如果两个 hunk 的上下文区域重叠或相邻
   - 可能不需要显示分隔符
   - 当前实现始终在非首个 hunk 前添加分隔符

2. **大量 Hunk**
   - 文件有大量分散的小变更时
   - 多个 `⋮` 可能影响可读性
   - 考虑折叠或分组展示

3. **Hunk 大小**
   - 单个 hunk 可能很大（包含多行变更）
   - 分隔符只表示 hunk 边界，不表示内容多少

### 潜在风险

1. **分隔符样式不一致**
   - 使用 `DiffLineType::Context` 的 gutter 样式
   - 在不同主题下可能不够明显

2. **行号对齐**
   - 分隔符行的 gutter 宽度必须与内容行一致
   - 行号宽度计算错误会导致分隔符错位

3. **可访问性**
   - `⋮` 符号在某些字体中可能显示异常
   - 色盲用户可能难以区分分隔符和上下文行

### 改进建议

1. **智能分隔**
   - 检测 hunk 之间的距离
   - 距离很近时不显示分隔符
   - 距离很远时显示更多信息（如 "跳过 100 行"）

2. **可折叠 Hunk**
   - 允许用户折叠/展开特定 hunk
   - 交互式浏览大型 diff

3. **分隔符增强**
   - 添加水平线或边框增强视觉分隔
   - 使用颜色或背景色区分

4. **行号范围显示**
   - 在分隔符旁显示省略的行号范围
   - 如 `⋮ (lines 6-20)`

5. **配置选项**
   - 允许用户禁用 hunk 分隔符
   - 或选择不同的分隔符样式

6. **性能优化**
   - 对超多 hunk 的文件进行虚拟化渲染
   - 避免一次性渲染所有 hunk
