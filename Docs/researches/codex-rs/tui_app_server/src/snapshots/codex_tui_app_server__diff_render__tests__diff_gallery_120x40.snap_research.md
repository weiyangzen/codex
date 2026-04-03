# Research: Diff Gallery 120x40 Terminal Size Snapshot

## File
- **Path**: `/home/sansha/Github/codex/codex-rs/tui_app_server/src/snapshots/codex_tui_app_server__diff_render__tests__diff_gallery_120x40.snap`
- **Source**: `tui_app_server/src/diff_render.rs`
- **Test**: `ui_snapshot_diff_gallery_120x40`

---

## 场景与职责

### 应用场景
该 snapshot 测试验证 Codex TUI 在大型终端（120列 x 40行）下的 diff 渲染效果。这是"Diff Gallery"系列测试之一，用于确保在不同终端尺寸下都能正确展示：
1. 多文件变更汇总
2. 各类文件操作（Add/Delete/Update/Rename）
3. 语法高亮效果
4. Unicode 字符（emoji、CJK）的正确显示

### 职责定位
- **响应式布局**：验证宽终端下的内容布局与对齐
- **多文件展示**：同时展示 6 个不同类型文件的变更
- **语法高亮验证**：Rust、Python 等语言的语法高亮效果
- **Unicode 支持**：验证 emoji 和东亚字符的宽度计算

---

## 功能点目的

### 核心功能
1. **多文件汇总 Header**：`"• Edited 6 files (+9 -9)"`
2. **文件分类展示**：
   - Add: `assets/banner.txt`, `examples/new_sample.rs`
   - Delete: `legacy/old_script.py`, `tmp/obsolete.log`
   - Update + Rename: `scripts/calc.txt → scripts/calc.py`
   - Update: `src/lib.rs`
3. **语法高亮**：Rust 代码的语法着色
4. **宽字符处理**：emoji（🚀）和 CJK（東京、你好世界）的宽度计算

### Snapshot 内容解析
```
"• Edited 6 files (+9 -9)"                                    # 总览 Header
"  └ assets/banner.txt (+3 -0)"                              # 新增文件
"    1 +HEADER	VALUE"                                        # Tab 分隔内容
"    2 +rocket	🚀"                                           # Emoji 内容
"    3 +city	東京"                                           # CJK 内容
"  └ examples/new_sample.rs (+3 -0)"                        # Rust 新增
"    1 +pub fn greet(name: &str) {"                          # 语法高亮
"  └ legacy/old_script.py (+0 -3)"                          # Python 删除
"  └ scripts/calc.txt → scripts/calc.py (+1 -1)"            # 重命名+修改
"  └ src/lib.rs (+2 -2)"                                     # Rust 修改
"    3 +    println!("emoji: 🚀✨ and CJK: 你好世界");"      # 混合 Unicode
```

### 视觉设计特点
- **树形缩进**：使用 `└` 字符构建文件列表的树形视觉层次
- **宽终端优势**：120列宽度允许长行完整显示，无需换行
- **隐藏标记**：`Hidden by multi-width symbols` 注释标记宽字符占用的额外列

---

## 具体技术实现

### 测试数据构建（`diff_gallery_changes` 函数，line 1404-1458）
```rust
fn diff_gallery_changes() -> HashMap<PathBuf, FileChange> {
    let mut changes: HashMap<PathBuf, FileChange> = HashMap::new();
    
    // Rust 文件修改（带 emoji 和 CJK）
    let rust_original = "fn greet(name: &str) {\n    println!(\"hello\");\n    println!(\"bye\");\n}\n";
    let rust_modified = "fn greet(name: &str) {\n    println!(\"hello {name}\");\n    println!(\"emoji: 🚀✨ and CJK: 你好世界\");\n}\n";
    let rust_patch = diffy::create_patch(rust_original, rust_modified).to_string();
    changes.insert(
        PathBuf::from("src/lib.rs"),
        FileChange::Update { unified_diff: rust_patch, move_path: None },
    );
    
    // Python 文件重命名+修改
    let py_patch = diffy::create_patch(py_original, py_modified).to_string();
    changes.insert(
        PathBuf::from("scripts/calc.txt"),
        FileChange::Update {
            unified_diff: py_patch,
            move_path: Some(PathBuf::from("scripts/calc.py")),
        },
    );
    
    // 新增文件（带 Tab 和 emoji）
    changes.insert(
        PathBuf::from("assets/banner.txt"),
        FileChange::Add {
            content: "HEADER\tVALUE\nrocket\t🚀\ncity\t東京\n".to_string(),
        },
    );
    
    // 删除文件
    changes.insert(
        PathBuf::from("tmp/obsolete.log"),
        FileChange::Delete {
            content: "old line 1\nold line 2\nold line 3\n".to_string(),
        },
    );
    
    changes
}
```

### 语法高亮集成
1. **语言检测**（`detect_lang_for_path`，line 469-472）
   ```rust
   fn detect_lang_for_path(path: &Path) -> Option<String> {
       let ext = path.extension()?.to_str()?;
       Some(ext.to_string())
   }
   ```

2. **高亮调用**（`highlight_code_to_styled_spans`，`render/highlight.rs` line 664-669）
   ```rust
   pub(crate) fn highlight_code_to_styled_spans(code: &str, lang: &str) -> Option<Vec<Vec<Span<'static>>>> {
       highlight_to_line_spans(code, lang)
   }
   ```

3. **Hunk 级高亮**（`render_change` 中 Update 处理，line 607-621）
   ```rust
   // Highlight each hunk as a single block so syntect parser state is preserved
   let hunk_syntax_lines = diff_lang.and_then(|language| {
       let hunk_text: String = h.lines().iter().map(...).collect();
       let syntax_lines = highlight_code_to_styled_spans(&hunk_text, language)?;
       (syntax_lines.len() == h.lines().len()).then_some(syntax_lines)
   });
   ```

### Unicode 宽度处理
```rust
// 使用 unicode-width crate 计算显示宽度
use unicode_width::UnicodeWidthChar;

// Tab 处理（常量定义 line 51）
const TAB_WIDTH: usize = 4;

// 宽度计算（line 968）
let w = ch.width().unwrap_or(if ch == '\t' { TAB_WIDTH } else { 0 });
```

### 测试执行
```rust
#[test]
fn ui_snapshot_diff_gallery_120x40() {
    snapshot_diff_gallery("diff_gallery_120x40", 120, 40);
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

---

## 关键代码路径与文件引用

### 核心文件
| 文件 | 职责 |
|------|------|
| `tui_app_server/src/diff_render.rs` | Diff 渲染主逻辑 |
| `tui_app_server/src/render/highlight.rs` | 语法高亮引擎（基于 syntect） |
| `tui_app_server/src/render/line_utils.rs` | 行处理工具函数 |

### 关键函数
| 函数 | 位置 | 职责 |
|------|------|------|
| `diff_gallery_changes` | line 1404-1458 | 构建测试数据集 |
| `snapshot_diff_gallery` | line 1460-1467 | 执行 snapshot 测试 |
| `snapshot_lines` | line 1362-1372 | 渲染到 TestBackend 并断言 |
| `create_diff_summary` | line 345-352 | 创建 diff 汇总输出 |
| `render_changes_block` | line 402-464 | 渲染变更块 |
| `highlight_code_to_styled_spans` | `highlight.rs` line 664-669 | 语法高亮入口 |
| `exceeds_highlight_limits` | `highlight.rs` line 559-561 | 高亮性能保护 |

### 渲染数据流
```
diff_gallery_changes()
  └── create_diff_summary(rows, wrap_cols, cwd)
       └── render_changes_block(rows, wrap_cols, cwd)
            ├── render_path()           # 路径展示（含重命名箭头）
            ├── render_line_count_summary()  # 统计信息
            └── render_change()         # 单文件 diff 渲染
                 ├── FileChange::Add    # 新增文件高亮
                 ├── FileChange::Delete # 删除文件高亮
                 └── FileChange::Update # Update diff 解析+高亮
                      └── highlight_code_to_styled_spans()
```

---

## 依赖与外部交互

### 核心依赖
| 依赖 | 用途 |
|------|------|
| `diffy` | Unified diff 创建与解析 |
| `ratatui` | 终端 UI 渲染 |
| `syntect` | 语法高亮引擎 |
| `two_face` | 语法定义和主题 bundle |
| `unicode-width` | Unicode 字符显示宽度计算 |

### 语法高亮配置
- **Guardrails**：`MAX_HIGHLIGHT_BYTES = 512KB`，`MAX_HIGHLIGHT_LINES = 10,000`
- **主题**：自适应选择（Catppuccin Latte/Mocha），支持 32 种内置主题
- **语言支持**：通过 two_face 支持约 250 种语言

---

## 风险、边界与改进建议

### 潜在风险
1. **性能问题**：超大 diff（>10,000 行）会跳过语法高亮，可能影响用户体验
2. **宽字符对齐**：某些终端对 emoji 宽度处理不一致，可能导致对齐偏差
3. **主题兼容性**：不同主题的背景色可能与 diff 背景色冲突

### 边界情况
| 场景 | 当前处理 |
|------|----------|
| 超大 diff | 跳过语法高亮，仅显示 plain diff |
| 未知语言 | 回退到纯文本显示 |
| 二进制文件 | 不在 diff 渲染范围内 |
| 零宽度字符 | 依赖 unicode-width 计算 |

### 改进建议
1. **渐进式高亮**：对大文件采用渐进式/增量高亮，而非完全跳过
2. **列宽自适应**：在超宽终端（>120列）中可考虑并排 diff 视图
3. **折叠支持**：多文件场景下支持折叠/展开单个文件 diff
4. **搜索功能**：在 diff 视图中添加文本搜索能力
5. **主题预览**：在主题切换时实时预览 diff 颜色效果

### 相关测试
- `ui_snapshot_diff_gallery_80x24`：标准终端尺寸
- `ui_snapshot_diff_gallery_94x35`：中等终端尺寸
- `ui_snapshot_diff_gallery_120x40`：大终端尺寸（本测试）
- `large_update_diff_skips_highlighting`：超大 diff 高亮跳过验证
