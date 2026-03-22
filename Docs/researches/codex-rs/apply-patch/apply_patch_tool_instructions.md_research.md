# apply_patch_tool_instructions.md 研究文档

## 场景与职责

此 Markdown 文件是 Codex CLI 提供给 AI 模型的工具使用说明文档。它定义了 `apply_patch` 工具的补丁语言格式、语法规则和调用方式。该文档在编译时被嵌入到二进制中，作为系统提示（system prompt）的一部分提供给 AI 模型，指导模型如何正确地生成文件修改补丁。

## 功能点目的

### 1. 工具介绍
文档首先明确 `apply_patch` 是一个用于编辑文件的 shell 命令，其补丁语言是一种简化、面向文件的 diff 格式，设计目标是易于解析且安全应用。

### 2. 补丁格式规范

#### 基本结构
```
*** Begin Patch
[ one or more file sections ]
*** End Patch
```

#### 三种文件操作
| 操作 | 语法 | 说明 |
|------|------|------|
| 添加文件 | `*** Add File: <path>` | 后续所有 `+` 行构成文件内容 |
| 删除文件 | `*** Delete File: <path>` | 无后续内容 |
| 更新文件 | `*** Update File: <path>` | 可包含 `*** Move to:` 和多个 hunk |

#### 文件移动
```
*** Update File: <path>
*** Move to: <new path>  # 可选的重命名操作
```

#### Hunk 格式
```
@@ [context header]      # 可选的上下文标识
[context_before]         # 3 行上文（空格开头）
- [old_code]             # 删除行（减号开头）
+ [new_code]             # 添加行（加号开头）
[context_after]          # 3 行下文（空格开头）
```

### 3. 上下文规则

#### 默认上下文
- 默认显示修改位置前后各 3 行代码
- 如果两次修改距离小于 3 行，避免上下文行重复

#### 显式上下文（@@ 标记）
当 3 行上下文不足以唯一标识代码位置时，使用 `@@` 指定类或函数：
```
@@ class BaseClass
[3 lines of pre-context]
- [old_code]
+ [new_code]
[3 lines of post-context]
```

#### 多级上下文
对于重复多次的代码块，可使用多个 `@@` 逐级定位：
```
@@ class BaseClass
@@ 	 def method():
[3 lines of pre-context]
- [old_code]
+ [new_code]
[3 lines of post-context]
```

### 4. 完整语法定义（类 Lark 语法）
```
Patch := Begin { FileOp } End
Begin := "*** Begin Patch" NEWLINE
End := "*** End Patch" NEWLINE
FileOp := AddFile | DeleteFile | UpdateFile
AddFile := "*** Add File: " path NEWLINE { "+" line NEWLINE }
DeleteFile := "*** Delete File: " path NEWLINE
UpdateFile := "*** Update File: " path NEWLINE [ MoveTo ] { Hunk }
MoveTo := "*** Move to: " newPath NEWLINE
Hunk := "@@" [ header ] NEWLINE { HunkLine } [ "*** End of File" NEWLINE ]
HunkLine := (" " | "-" | "+") text NEWLINE
```

### 5. 调用示例
```
shell {"command":["apply_patch","*** Begin Patch\n*** Add File: hello.txt\n+Hello, world!\n*** End Patch\n"]}
```

## 具体技术实现

### 编译时嵌入
在 `src/lib.rs` 中，文档内容通过 `include_str!` 宏嵌入：
```rust
pub const APPLY_PATCH_TOOL_INSTRUCTIONS: &str = include_str!("../apply_patch_tool_instructions.md");
```

### 使用场景
1. **系统提示组装**：`codex-core` 将此内容注入到模型的系统提示中
2. **工具描述**：作为 `apply_patch` 工具的 description 字段

### 解析实现
文档描述的格式由 `src/parser.rs` 实现：

| 语法元素 | 实现函数/结构 |
|----------|---------------|
| `*** Begin/End Patch` | `check_patch_boundaries_strict()` |
| `*** Add File` | `parse_one_hunk()` 中的 `AddFile` 分支 |
| `*** Delete File` | `parse_one_hunk()` 中的 `DeleteFile` 分支 |
| `*** Update File` | `parse_one_hunk()` 中的 `UpdateFile` 分支 |
| `@@` 上下文 | `parse_update_file_chunk()` |
| Hunk 行解析 | `UpdateFileChunk` 结构体 |

### 宽松解析模式
针对 GPT-4.1 模型的特殊行为，解析器实现了 Lenient 模式：
```rust
const PARSE_IN_STRICT_MODE: bool = false;
```

Lenient 模式处理 heredoc 包装：
```
<<'EOF'
*** Begin Patch
...
*** End Patch
EOF
```

## 关键代码路径与文件引用

### 文档本身
```
codex-rs/apply-patch/
└── apply_patch_tool_instructions.md    # 本文件
```

### 引用此文档的代码
```
codex-rs/apply-patch/src/lib.rs         # include_str! 嵌入点
codex-rs/core/src/apply_patch.rs        # 使用说明作为工具描述
codex-rs/core/src/tools/handlers/apply_patch.rs  # 工具处理逻辑
```

### 解析实现
```
codex-rs/apply-patch/src/parser.rs      # 补丁格式解析器
├── parse_patch()                       # 主解析入口
├── parse_one_hunk()                    # 解析单个文件操作
└── parse_update_file_chunk()           # 解析 update hunk
```

### 应用实现
```
codex-rs/apply-patch/src/lib.rs
├── apply_patch()                       # 应用补丁主函数
├── apply_hunks()                       # 应用多个 hunk
├── apply_hunks_to_files()              # 文件系统操作
├── compute_replacements()              # 计算替换位置
└── seek_sequence::seek_sequence()      # 文本匹配算法
```

## 依赖与外部交互

### 模型交互
- **输入**：AI 模型根据此文档生成补丁文本
- **约束**：模型必须遵循文档中的格式规范

### 代码生成
- 文档内容被包含在 `codex-core` 生成的工具描述中
- 通过 `APPLY_PATCH_TOOL_INSTRUCTIONS` 常量暴露

### 与其他组件的关系
```
apply_patch_tool_instructions.md
    ↓ (include_str!)
codex_apply_patch::APPLY_PATCH_TOOL_INSTRUCTIONS
    ↓ (使用)
codex-core (系统提示组装)
    ↓ (API 调用)
OpenAI API (模型生成补丁)
    ↓ (返回)
apply_patch 调用
    ↓ (解析应用)
文件系统修改
```

## 风险、边界与改进建议

### 风险
1. **格式漂移**：如果文档描述与解析器实现不一致，会导致模型生成的补丁无法解析
2. **模型理解**：某些模型可能无法完全理解复杂的语法规则（如多级 @@ 上下文）
3. **Heredoc 混淆**：GPT-4.1 曾错误地将 heredoc 语法直接放入 `command` 数组而非通过 shell 调用

### 边界
1. **路径限制**：文件路径必须是相对路径，不能使用绝对路径
2. **编码限制**：假设文件内容为 UTF-8 编码
3. **上下文长度**：虽然文档建议 3 行上下文，但解析器实际支持更灵活的匹配

### 改进建议

#### 1. 文档改进
- 添加更多复杂场景的示例（如多文件修改、跨行修改等）
- 明确说明 Unicode 处理规则（目前解析器支持 Unicode 标点的模糊匹配）
- 添加常见错误示例及正确写法

#### 2. 格式扩展
- 考虑支持二进制文件的 base64 编码补丁
- 添加文件权限修改的支持
- 考虑添加批量重命名操作

#### 3. 验证增强
- 添加文档与解析器的自动化一致性检查
- 使用文档中的示例作为解析器的测试用例
- 考虑使用类似 JSON Schema 的方式形式化验证规则

#### 4. 模型适配
- 针对不同模型版本优化说明文档（如 GPT-4.1 需要 heredoc 宽松解析）
- 考虑添加模型特定的提示工程技巧
- 添加关于如何处理大文件（超过上下文限制）的指导

### 测试覆盖
文档中提到的所有场景都应在 `tests/fixtures/scenarios/` 中有对应的测试用例：
- `001_add_file` - 添加文件
- `002_multiple_operations` - 多操作组合
- `003_multiple_chunks` - 多 hunk 更新
- `004_move_to_new_directory` - 文件移动
- ...（共 22+ 个场景）
