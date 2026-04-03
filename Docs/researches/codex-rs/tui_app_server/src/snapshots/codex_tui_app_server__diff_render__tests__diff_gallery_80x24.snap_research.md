# Diff Gallery 80x24 Terminal Size - Technical Research Document

## Snapshot File
`codex_tui_app_server__diff_render__tests__diff_gallery_80x24.snap`

## Snapshot Content
```
"• Edited 6 files (+9 -9)                                                        "
"  └ assets/banner.txt (+3 -0)                                                   "
"    1 +HEADER	VALUE                                                             "
"    2 +rocket	🚀                                                                "
"    3 +city	東京                                                                "
"  └ examples/new_sample.rs (+3 -0)                                              "
"    1 +pub fn greet(name: &str) {                                               "
"    2 +    println!("Hello, {name}!");                                          "
"    3 +}                                                                        "
"  └ legacy/old_script.py (+0 -3)                                                "
"    1 -def legacy(x):                                                           "
"    2 -    return x + 1                                                         "
"    3 -print(legacy(3))                                                         "
```

---

## 1. 场景与职责 (Scenario & Responsibilities)

### 1.1 功能场景
此快照测试验证 **标准终端尺寸（80列 x 24行）下的差异渲染效果**。这是 "Diff Gallery" 系列测试之一，模拟最常见的终端尺寸。

### 1.2 业务职责
- **标准尺寸验证**: 确保在 80x24 终端上正确渲染
- **内容截断**: 验证长内容在窄终端上的处理
- **布局适配**: 验证布局在标准尺寸下的表现

### 1.3 与 120x40 的区别
| 尺寸 | 适用场景 | 特点 |
|------|---------|------|
| 80x24 | 标准终端、笔记本电脑 | 内容可能需要截断或换行 |
| 94x35 | 中等尺寸、外接显示器 | 更多内容可见 |
| 120x40 | 大屏、宽屏显示器 | 完整显示大多数内容 |

---

## 2. 功能点目的 (Feature Purpose)

### 2.1 核心功能
与 `diff_gallery_120x40` 相同的数据集，但在 80 列宽度下渲染：
1. **多文件汇总**: "Edited 6 files (+9 -9)"
2. **各类操作**: Add/Delete/Update/Rename
3. **Unicode 支持**: emoji 和 CJK 字符

### 2.2 窄终端适配
在 80 列宽度下：
- 长行内容可能被截断或换行
- 文件路径可能显示为相对路径
- emoji 和 CJK 字符占用更多显示空间

---

## 3. 具体技术实现 (Technical Implementation)

### 3.1 测试实现
```rust
// diff_render.rs:1469-1476
#[test]
fn ui_snapshot_diff_gallery_80x24() {
    snapshot_diff_gallery("diff_gallery_80x24", 80, 24);
}

fn snapshot_diff_gallery(name: &str, width: u16, height: u16) {
    let lines = create_diff_summary(
        &diff_gallery_changes(),
        &PathBuf::from("/"),
        usize::from(width),
    );
    snapshot_lines(name, lines, width, height);
}
```

### 3.2 与 120x40 使用相同数据集
```rust
// diff_render.rs:1404-1458
fn diff_gallery_changes() -> HashMap<PathBuf, FileChange> {
    // 与 diff_gallery_120x40 相同的数据集
    // ...
}
```

---

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 4.1 主要文件
| 文件路径 | 职责 |
|---------|------|
| `tui_app_server/src/diff_render.rs` | Diff 渲染和测试 |

### 4.2 相关测试
| 测试 | 尺寸 | 用途 |
|------|------|------|
| `ui_snapshot_diff_gallery_80x24` | 80x24 | 标准终端（本测试）|
| `ui_snapshot_diff_gallery_94x35` | 94x35 | 中等终端 |
| `ui_snapshot_diff_gallery_120x40` | 120x40 | 大终端 |

---

## 5. 依赖与外部交互 (Dependencies & External Interactions)

### 5.1 外部依赖
| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染 |

---

## 6. 风险、边界与改进建议 (Risks, Edge Cases & Improvements)

### 6.1 窄终端风险
| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| 内容截断 | 80 列可能截断重要信息 | 智能换行，保留关键部分 |
| 路径显示 | 长路径可能无法完整显示 | 使用相对路径或缩写 |

### 6.2 改进建议
1. **响应式布局**: 根据终端宽度调整显示策略
2. **路径缩写**: 长路径中间部分使用 ... 省略
3. **折叠默认**: 窄终端下默认折叠大文件

---

## 7. 相关文档链接

- [Diff Gallery 120x40](../codex_tui_app_server__diff_render__tests__diff_gallery_120x40.snap_research.md)
