# parser.rs 深度研究文档

## 场景与职责

`parser.rs` 是 `codex-apply-patch` crate 的解析模块，负责将文本格式的 patch 解析为结构化的 `Hunk` 列表。核心职责包括：

1. **Patch 格式解析**：解析 `*** Begin Patch` 到 `*** End Patch` 之间的内容
2. **Hunk 类型识别**：识别并解析三种 hunk 类型（AddFile、DeleteFile、UpdateFile）
3. **Lenient 模式支持**：兼容 GPT-4.1 等模型可能产生的 heredoc 包装格式
4. **错误报告**：提供详细的解析错误信息，包含行号定位

该模块是 patch 处理流程的第一阶段，为后续的 `apply_hunks` 提供结构化输入。

## 功能点目的

### 1. Patch 边界检测
- **目的**：验证 patch 文本以正确的标记开始和结束
- **严格模式**：要求精确的 `*** Begin Patch` 和 `*** End Patch`
- **宽松模式**：自动去除 `<<EOF` / `EOF` 等 heredoc 包装

### 2. Hunk 解析
- **AddFile**：解析文件路径和以 `+` 开头的行内容
- **DeleteFile**：仅解析文件路径
- **UpdateFile**：解析文件路径、可选的 MoveTo 目标、以及多个 change chunks

### 3. UpdateFile Chunk 解析
- **Change Context**：可选的 `@@` 或 `@@ context` 上下文标记
- **Change Lines**：以 ` `（空格）、`+`、`-` 开头的 diff 行
- **End of File**：`*** End of File` 标记表示变更在文件末尾

### 4. 错误处理
- **行号追踪**：所有错误都包含准确的行号信息
- **详细消息**：提供人类可读的错误描述

## 具体技术实现

### 核心数据结构

```rust
/// Hunk 类型（文件操作单元）
#[derive(Debug, PartialEq, Clone)]
#[allow(clippy::enum_variant_names)]
pub enum Hunk {
    AddFile {
        path: PathBuf,
        contents: String,
    },
    DeleteFile {
        path: PathBuf,
    },
    UpdateFile {
        path: PathBuf,
        move_path: Option<PathBuf>,
        chunks: Vec<UpdateFileChunk>,
    },
}

/// UpdateFile 的变更块
#[derive(Debug, PartialEq, Clone)]
pub struct UpdateFileChunk {
    /// 上下文定位标记（如函数名、类名）
    pub change_context: Option<String>,
    /// 需要被替换的旧行
    pub old_lines: Vec<String>,
    /// 新行内容
    pub new_lines: Vec<String>,
    /// 是否必须在文件末尾匹配
    pub is_end_of_file: bool,
}

/// 解析错误类型
#[derive(Debug, PartialEq, Error, Clone)]
pub enum ParseError {
    #[error("invalid patch: {0}")]
    InvalidPatchError(String),
    #[error("invalid hunk at line {line_number}, {message}")]
    InvalidHunkError { message: String, line_number: usize },
}

/// 解析结果（包含原始 patch 文本和解析后的 hunks）
#[derive(Debug, PartialEq)]
pub struct ApplyPatchArgs {
    pub patch: String,
    pub hunks: Vec<Hunk>,
    pub workdir: Option<String>,
}
```

### 解析模式

```rust
enum ParseMode {
    /// 严格模式：按原始文本解析
    Strict,
    
    /// 宽松模式：处理 GPT-4.1 等模型产生的 heredoc 包装
    /// 自动识别并去除以下包装：
    /// - <<EOF\n...\nEOF
    /// - <<'EOF'\n...\nEOF
    /// - <<"EOF"\n...\nEOF
    Lenient,
}

// 当前配置：始终使用宽松模式
const PARSE_IN_STRICT_MODE: bool = false;
```

### 标记常量

```rust
const BEGIN_PATCH_MARKER: &str = "*** Begin Patch";
const END_PATCH_MARKER: &str = "*** End Patch";
const ADD_FILE_MARKER: &str = "*** Add File: ";
const DELETE_FILE_MARKER: &str = "*** Delete File: ";
const UPDATE_FILE_MARKER: &str = "*** Update File: ";
const MOVE_TO_MARKER: &str = "*** Move to: ";
const EOF_MARKER: &str = "*** End of File";
const CHANGE_CONTEXT_MARKER: &str = "@@ ";
const EMPTY_CHANGE_CONTEXT_MARKER: &str = "@@";
```

### 解析流程

```
parse_patch(patch_text)
    │
    └──► parse_patch_text(patch_text, ParseMode::Lenient)
         │
         ├──► 文本预处理：lines().collect()
         │
         ├──► 边界检查：check_patch_boundaries_strict()
         │    └──► 失败且宽松模式？
         │         └──► check_patch_boundaries_lenient()  // 尝试去除 heredoc
         │
         ├──► 遍历 hunk 行（跳过首尾的 Begin/End 标记）
         │    └──► parse_one_hunk(remaining_lines, line_number)
         │         │
         │         ├──► "*** Add File: " 前缀？
         │         │    └──► 解析所有以 '+' 开头的行
         │         │
         │         ├──► "*** Delete File: " 前缀？
         │         │    └──► 返回 DeleteFile hunk
         │         │
         │         └──► "*** Update File: " 前缀？
         │              ├──► 可选：解析 "*** Move to: "
         │              └──► 循环解析 chunks
         │                   └──► parse_update_file_chunk()
         │                        ├──► 解析 @@ 上下文
         │                        ├──► 解析 diff 行 (+/-/space)
         │                        └──► 检测 *** End of File
         │
         └──► 返回 ApplyPatchArgs { patch, hunks, workdir: None }
```

### UpdateFile Chunk 解析详解

```rust
fn parse_update_file_chunk(
    lines: &[&str],
    line_number: usize,
    allow_missing_context: bool,  // 第一个 chunk 允许省略 @@
) -> Result<(UpdateFileChunk, usize), ParseError> {
    // 1. 解析 change_context
    let (change_context, start_index) = match lines[0] {
        "@@" => (None, 1),
        line if line.starts_with("@@ ") => (Some(line[3..].to_string()), 1),
        _ if allow_missing_context => (None, 0),  // 第一个 chunk 可省略
        _ => return Err(InvalidHunkError { ... }),
    };

    // 2. 解析 diff 行
    let mut chunk = UpdateFileChunk {
        change_context,
        old_lines: Vec::new(),
        new_lines: Vec::new(),
        is_end_of_file: false,
    };

    for line in &lines[start_index..] {
        match *line {
            "*** End of File" => {
                chunk.is_end_of_file = true;
                break;
            }
            line_contents => {
                match line_contents.chars().next() {
                    None => {  // 空行
                        chunk.old_lines.push(String::new());
                        chunk.new_lines.push(String::new());
                    }
                    Some(' ') => {  // 上下文行
                        chunk.old_lines.push(line_contents[1..].to_string());
                        chunk.new_lines.push(line_contents[1..].to_string());
                    }
                    Some('+') => {  // 新增行
                        chunk.new_lines.push(line_contents[1..].to_string());
                    }
                    Some('-') => {  // 删除行
                        chunk.old_lines.push(line_contents[1..].to_string());
                    }
                    _ => break,  // 遇到下一个 hunk 或结束标记
                }
            }
        }
    }

    Ok((chunk, parsed_lines + start_index))
}
```

### 宽松模式边界检查

```rust
fn check_patch_boundaries_lenient<'a>(
    original_lines: &'a [&'a str],
    original_parse_error: ParseError,
) -> Result<&'a [&'a str], ParseError> {
    match original_lines {
        [first, .., last] => {
            // 检查是否为 heredoc 格式
            if (first == &"<<EOF" || first == &"<<'EOF'" || first == &"<<\"EOF\"")
                && last.ends_with("EOF")
                && original_lines.len() >= 4  // 至少需要 heredoc 标记 + Begin + End
            {
                let inner_lines = &original_lines[1..original_lines.len() - 1];
                // 递归检查内部内容
                check_patch_boundaries_strict(inner_lines)
            } else {
                Err(original_parse_error)
            }
        }
        _ => Err(original_parse_error),
    }
}
```

## 关键代码路径与文件引用

### 内部依赖

| 模块 | 用途 |
|------|------|
| `lib.rs` | 使用 `ApplyPatchArgs` 作为解析结果类型 |
| `invocation.rs` | 调用 `parse_patch()` 解析提取的 patch 文本 |

### 对外暴露 API

| 函数/类型 | 用途 |
|-----------|------|
| `parse_patch()` | 主解析入口 |
| `Hunk` | Hunk 类型定义 |
| `ParseError` | 解析错误类型 |
| `UpdateFileChunk` | Chunk 结构定义 |

### 调用方

| 文件 | 调用点 |
|------|--------|
| `lib.rs` | `apply_patch()` 调用 `parse_patch()` |
| `invocation.rs` | `maybe_parse_apply_patch()` 调用 `parse_patch()` |

## 依赖与外部交互

### 外部依赖

| Crate | 用途 |
|-------|------|
| `thiserror` | 错误类型派生宏 |
| `std::path` | PathBuf 处理 |

### Patch 格式规范

模块顶部注释详细定义了 Lark 语法：

```
start: begin_patch hunk+ end_patch
begin_patch: "*** Begin Patch" LF
end_patch: "*** End Patch" LF?

hunk: add_hunk | delete_hunk | update_hunk
add_hunk: "*** Add File: " filename LF add_line+
delete_hunk: "*** Delete File: " filename LF
update_hunk: "*** Update File: " filename LF change_move? change?

change_move: "*** Move to: " filename LF
change: (change_context | change_line)+ eof_line?
change_context: ("@@" | "@@ " /(.+)/) LF
change_line: ("+" | "-" | " ") /(.+)/ LF
eof_line: "*** End of File" LF
```

### 与工具指令的关联

`apply_patch_tool_instructions.md` 向 AI 模型描述了该格式：

```markdown
*** Begin Patch
*** Add File: <path>
+line content
*** Update File: <path>
@@ context
-old line
+new line
*** Delete File: <path>
*** End Patch
```

## 风险、边界与改进建议

### 已知风险

1. **Lenient 模式过度宽松**
   - 风险：可能错误地解析非 heredoc 内容
   - 现状：要求严格的 `<<EOF` / `EOF` 格式，风险较低
   - 建议：考虑添加更多验证（如 EOF 必须单独一行）

2. **路径注入风险**
   - 风险：文件路径可能包含 `../` 等遍历序列
   - 现状：模块仅负责解析，路径验证由调用方处理
   - 建议：在解析层添加路径规范化验证

3. **内存消耗**
   - 风险：大文件 patch 可能导致大量内存分配
   - 现状：使用 `Vec<String>` 存储所有行
   - 建议：对于超大 patch，考虑流式解析

### 边界情况处理

| 场景 | 处理 |
|------|------|
| 空 patch（仅有 Begin/End）| 返回空 hunks 列表（在 apply 阶段被拒绝）|
| 空白字符包围的标记 | `trim()` 处理后识别 |
| 缺少 @@ 的第一个 chunk | 允许（`allow_missing_context=true`）|
| 后续 chunk 缺少 @@ | 返回错误 |
| 空 update hunk | 返回 "Update file hunk for path 'x' is empty" 错误 |
| 不合法的 hunk header | 返回详细错误，列出合法格式 |

### 改进建议

1. **严格模式恢复**
   - 当前 `PARSE_IN_STRICT_MODE = false` 是硬编码
   - 建议：通过参数或环境变量控制，便于调试

2. **路径验证增强**
   - 添加路径规范化检查
   - 拒绝绝对路径（根据设计，patch 中应使用相对路径）

3. **错误信息改进**
   - 添加建议修复提示
   - 提供上下文片段（出错位置的前后几行）

4. **性能优化**
   - 考虑使用 `&str` 而非 `String` 减少分配
   - 对于大文件，使用迭代器而非收集到 Vec

5. **测试覆盖**
   - 增加畸形输入的模糊测试
   - 增加 Unicode 路径测试
   - 增加超长行测试
