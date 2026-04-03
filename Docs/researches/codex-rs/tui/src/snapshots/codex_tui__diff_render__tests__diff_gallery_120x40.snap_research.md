# Diff Render - Diff 画廊 120x40 综合渲染测试

## 场景与职责

该快照测试是一个**综合性展示测试**，验证 TUI 在较大终端尺寸（120列×40行）下同时渲染多种类型文件变更的能力。它模拟了真实场景中 Codex 一次操作修改多个不同类型文件的情况，包括代码文件、文本文件、配置文件等。

这是 diff 渲染系统的集成测试，验证了整体布局、多文件展示、语法高亮、Unicode 字符处理等功能的协同工作。

## 功能点目的

1. **多文件类型展示**：同时展示 Rust、Python、纯文本等多种文件类型的变更
2. **混合变更类型**：Add、Delete、Update（含重命名）混合展示
3. **大终端适配**：验证在 120x40 终端尺寸下的布局效果
4. **Unicode 支持**：验证 Emoji、CJK 字符的正确渲染
5. **语法高亮集成**：验证多种编程语言的语法高亮效果
6. **统计汇总**：验证多文件变更的统计信息准确性

## 具体技术实现

### 测试数据构造

```rust
fn diff_gallery_changes() -> HashMap<PathBuf, FileChange> {
    let mut changes: HashMap<PathBuf, FileChange> = HashMap::new();

    // 1. Rust 文件更新（含 Emoji 和 CJK）
    let rust_original = "fn greet(name: &str) {\n    println!(\"hello\");\n    println!(\"bye\");\n}\n";
    let rust_modified = "fn greet(name: &str) {\n    println!(\"hello {name}\");\n    println!(\"emoji: 🚀✨ and CJK: 你好世界\");\n}\n";
    let rust_patch = diffy::create_patch(rust_original, rust_modified).to_string();
    changes.insert(
        PathBuf::from("src/lib.rs"),
        FileChange::Update { unified_diff: rust_patch, move_path: None },
    );

    // 2. Python 文件更新（含重命名 .txt → .py）
    let py_original = "def add(a, b):\n\treturn a + b\n\nprint(add(1, 2))\n";
    let py_modified = "def add(a, b):\n\treturn a + b + 42\n\nprint(add(1, 2))\n";
    let py_patch = diffy::create_patch(py_original, py_modified).to_string();
    changes.insert(
        PathBuf::from("scripts/calc.txt"),
        FileChange::Update { 
            unified_diff: py_patch, 
            move_path: Some(PathBuf::from("scripts/calc.py")) 
        },
    );

    // 3. 新增文件（含 Tab 和 Emoji）
    changes.insert(
        PathBuf::from("assets/banner.txt"),
        FileChange::Add { 
            content: "HEADER\tVALUE\nrocket\t🚀\ncity\t東京\n".to_string() 
        },
    );

    // 4. 新增 Rust 文件
    changes.insert(
        PathBuf::from("examples/new_sample.rs"),
        FileChange::Add { 
            content: "pub fn greet(name: &str) {\n    println!(\"Hello, {name}!\");\n}\n".to_string() 
        },
    );

    // 5. 删除文件
    changes.insert(
        PathBuf::from("tmp/obsolete.log"),
        FileChange::Delete { content: "old line 1\nold line 2\nold line 3\n".to_string() },
    );
    changes.insert(
        PathBuf::from("legacy/old_script.py"),
        FileChange::Delete { content: "def legacy(x):\n    return x + 1\nprint(legacy(3))\n".to_string() },
    );

    changes
}
```

### 渲染流程

```rust
fn snapshot_diff_gallery(name: &str, width: u16, height: u16) {
    let lines = create_diff_summary(
        &diff_gallery_changes(),
        &PathBuf::from("/"),
        usize::from(width),
    );
    snapshot_lines(name, lines, width, height);
}
```

### 关键特性验证

1. **多文件统计**：
   ```
   "• Edited 6 files (+9 -9)"
   ```

2. **逐文件统计**：
   ```
   "  └ assets/banner.txt (+3 -0)"
   "  └ examples/new_sample.rs (+3 -0)"
   "  └ legacy/old_script.py (+0 -3)"
   "  └ scripts/calc.txt → scripts/calc.py (+1 -1)"
   "  └ src/lib.rs (+2 -2)"
   "  └ tmp/obsolete.log (+0 -3)"
   ```

3. **语法高亮**：
   - Rust 文件：`pub fn`, `println!` 等关键字高亮
   - Python 文件：`def`, `return` 等关键字高亮

4. **Unicode 处理**：
   - Emoji：🚀（火箭）、✨（闪光）
   - CJK：東京、你好世界
   - 宽度计算：`[(15, " ")]` 表示被宽字符隐藏的单元格

## 关键代码路径与文件引用

| 组件 | 文件路径 | 职责 |
|------|----------|------|
| 画廊数据 | `diff_render.rs:1404-1458` | `diff_gallery_changes` 函数 |
| 画廊快照 | `diff_render.rs:1460-1467` | `snapshot_diff_gallery` 函数 |
| 测试用例 | `diff_render.rs:1759-1762` | `ui_snapshot_diff_gallery_120x40` |
| 其他尺寸 | `diff_render.rs:1749-1757` | 80x24 和 94x35 版本 |
| 统计计算 | `diff_render.rs:365-390` | `collect_rows` 函数 |

### 测试矩阵

| 测试名称 | 宽度 | 高度 | 用途 |
|----------|------|------|------|
| diff_gallery_80x24 | 80 | 24 | 标准终端尺寸 |
| diff_gallery_94x35 | 94 | 35 | 中等终端尺寸 |
| diff_gallery_120x40 | 120 | 40 | 大终端尺寸 |

## 依赖与外部交互

### 外部依赖

1. **diffy**：统一 diff 格式创建和解析
2. **ratatui**：终端 UI 渲染和测试后端
3. **syntect**：多语言语法高亮
4. **unicode-width**：Unicode 字符宽度计算

### 内部依赖

- `create_diff_summary()` - 创建 diff 汇总
- `collect_rows()` - 收集和排序文件变更
- `render_changes_block()` - 渲染变更块
- `highlight_code_to_styled_spans()` - 语法高亮

### 数据流

```
diff_gallery_changes() → HashMap<PathBuf, FileChange>
    ↓ create_diff_summary(wrap_cols=120)
Vec<RtLine>（多文件渲染结果）
    ↓ Terminal::draw()
120x40 终端缓冲区
    ↓ snapshot_lines()
快照文件
```

## 风险、边界与改进建议

### 潜在风险

1. **快照维护成本**：综合测试的快照文件较大，维护成本高
2. **平台差异**：不同平台的换行符、路径分隔符可能导致快照不匹配
3. **字体差异**：Emoji 和 CJK 字符的显示依赖于终端字体
4. **性能**：大量文件和复杂 diff 的渲染性能

### 边界情况

1. **终端尺寸变化**：不同尺寸下的布局自适应
2. **颜色深度**：不同终端颜色深度下的显示效果
3. **字符编码**：非 UTF-8 终端的字符显示
4. **超长路径**：深层嵌套路径的截断显示

### 输出分析

关键输出元素：

```
// 头部统计
"• Edited 6 files (+9 -9)"

// 文件列表（按路径排序）
"  └ assets/banner.txt (+3 -0)"
"    1 +HEADER\tVALUE"              // Tab 字符
"    2 +rocket\t🚀"                // Emoji，宽度计算提示
"    3 +city\t東京"                // CJK 字符

// 重命名展示
"  └ scripts/calc.txt → scripts/calc.py (+1 -1)"

// 语法高亮（Rust）
"  └ src/lib.rs (+2 -2)"
"    1  fn greet(name: &str) {"     // 函数定义
"    2 -    println!(\"hello\");"    // 删除行
"    3 -    println!(\"bye\");"
"    2 +    println!(\"hello {name}\");"  // 新增行
"    3 +    println!(\"emoji: 🚀✨ and CJK: 你好世界\");"  // Emoji + CJK
```

### 改进建议

1. **测试优化**：
   - 将综合测试拆分为更小的单元测试
   - 使用参数化测试减少重复代码
   - 添加更多边缘场景

2. **功能增强**：
   - 文件类型图标（根据扩展名显示不同图标）
   - 目录树折叠/展开
   - 按文件类型筛选

3. **性能优化**：
   - 虚拟滚动：只渲染可见区域
   - 延迟加载：大文件 diff 按需加载
   - 缓存：缓存语法高亮结果

4. **可访问性**：
   - 纯文本 fallback 模式
   - 屏幕阅读器优化
   - 键盘导航支持

5. **国际化**：
   - RTL 语言支持
   - 本地化统计信息
   - 区域设置感知

6. **可视化增强**：
   - 文件类型颜色编码
   - 变更热度图
   - 进度指示器

### 维护建议

1. **快照审查**：
   - 定期审查快照变化
   - 使用 `cargo insta review` 工具
   - 团队共享审查责任

2. **文档同步**：
   - 快照变化时同步更新文档
   - 记录设计决策
   - 维护变更日志

3. **自动化**：
   - CI 中运行快照测试
   - 自动检测意外的视觉变化
   - 集成代码审查工具
