# 研究文档: codex_tui__chatwidget__tests__chatwidget_markdown_code_blocks_vt100_snapshot.snap

## 场景与职责

本快照文件验证 **Markdown 代码块** 的 VT100 终端渲染输出。

测试 TUI 对 Markdown 格式代码块的语法高亮和布局渲染。

## 功能点目的

1. **代码高亮**: 验证代码块的语法高亮渲染
2. **格式保持**: 验证缩进和换行的正确保持
3. **多种代码块**: 测试不同风格的代码块（缩进、围栏）

## 具体技术实现

### 快照内容结构
```
•     -- Indented code block (4 spaces)
      SELECT *
      FROM "users"
      WHERE "email" LIKE '%@example.com';

  ```sh
  printf 'fenced within fenced\n'
  ```

  {
    // comment allowed in jsonc
    "path": "C:\\Program Files\\App",
    "regex": "^foo.*(bar)?$"
  }
```

### 代码块类型

| 类型 | 示例 | 说明 |
|------|------|------|
| 缩进代码块 | 4 空格缩进 | 传统 Markdown |
| 围栏代码块 | ```sh | 带语言标识 |
| JSONC | ``` | 带注释的 JSON |

### 语法高亮元素
- **SQL 关键字**: `SELECT`, `FROM`, `WHERE`
- **Shell 命令**: `printf`
- **JSON 键**: `"path"`, `"regex"`
- **注释**: `// comment`
- **转义**: `\\` 在 Windows 路径中

## 关键代码路径与文件引用

### 测试定义
```rust
expression: visual
```

### 渲染模块
- `markdown_render.rs` - Markdown 渲染核心
- `markdown_stream.rs` - 流式 Markdown 处理
- `syntax_highlight.rs` (可能) - 语法高亮

### 代码块解析
```rust
enum CodeBlockKind {
    Indented,        // 4 空格缩进
    Fenced(String),  // ```lang
}
```

## 依赖与外部交互

### Markdown 解析
- `pulldown-cmark` (可能) - Markdown 解析器
- `syntect` (可能) - 语法高亮引擎

### 样式定义
- `style.rs` - 颜色主题定义
- `terminal_palette.rs` - 终端调色板

## 风险、边界与改进建议

### 渲染风险
1. **长代码行**: 超出窗口宽度的处理
2. **嵌套代码块**: 围栏代码块内的代码块
3. **未知语言**: 不支持的语言标识处理

### 改进建议
1. **行号显示**: 添加可选的行号
2. **复制功能**: 支持复制代码块
3. **折叠展开**: 长代码块可折叠
4. **主题切换**: 支持多种语法高亮主题
5. **语言检测**: 自动检测语言（无标识时）

### 相关测试
- `markdown_render_tests.rs` - Markdown 渲染单元测试
- `binary_size_ideal_response.snap` - 包含代码片段的完整对话
