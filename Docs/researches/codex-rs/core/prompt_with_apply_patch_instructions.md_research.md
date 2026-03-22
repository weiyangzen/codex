# prompt_with_apply_patch_instructions.md 研究文档

## 场景与职责

`codex-rs/core/prompt_with_apply_patch_instructions.md` 是 Codex CLI 的扩展系统提示词文件，在基础 `prompt.md` 的基础上增加了 `apply_patch` 工具的详细使用说明。该文件用于需要向模型提供完整补丁应用指令的场景，特别是针对某些需要显式指导如何使用代码编辑工具的模型。

该文件主要用于测试和特定模型配置场景，确保模型理解 `apply_patch` 工具的语法、格式和最佳实践。

## 功能点目的

### 1. 基础指令继承
- 完整包含 `prompt.md` 的所有内容
- 保持与基础提示词一致的行为规范和个性设定

### 2. apply_patch 工具详细说明

#### 2.1 工具定位
- 使用 `apply_patch` shell 命令编辑文件
- 补丁语言是简化版、面向文件的 diff 格式
- 设计目标：易于解析、安全应用

#### 2.2 补丁格式规范

**信封结构**：
```
*** Begin Patch
[ one or more file sections ]
*** End Patch
```

**文件操作类型**：
1. **Add File**：创建新文件
   ```
   *** Add File: <path>
   +<line content>
   ```
   
2. **Delete File**：删除现有文件
   ```
   *** Delete File: <path>
   ```
   
3. **Update File**：更新现有文件（支持重命名）
   ```
   *** Update File: <path>
   *** Move to: <new path>  (可选)
   @@ <context header>
   - <old line>
   + <new line>
   ```

#### 2.3 上下文规范
- **默认上下文**：3 行代码（修改前后）
- **上下文去重**：如果修改位置接近，不重复上下文行
- **精确定位**：使用 `@@` 指定类或函数名辅助定位
- **多级定位**：支持多个 `@@` 语句进行嵌套定位

#### 2.4 完整语法定义（EBNF 风格）
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

#### 2.5 重要提醒
- 必须包含操作头（Add/Delete/Update）
- 创建新文件时也必须用 `+` 前缀行内容
- 文件路径必须是相对路径，**禁止使用绝对路径**

#### 2.6 调用示例
```json
shell {"command":["apply_patch","*** Begin Patch\n*** Add File: hello.txt\n+Hello, world!\n*** End Patch\n"]}
```

## 具体技术实现

### 文件使用方式

#### 测试场景使用
```rust
// codex-rs/core/src/codex_tests.rs:500-503
#[tokio::test]
async fn get_base_instructions_no_user_content() {
    let prompt_with_apply_patch_instructions =
        include_str!("../prompt_with_apply_patch_instructions.md");
    // 测试逻辑...
}
```

#### 测试用例设计
测试验证以下模型是否按预期处理 apply_patch 指令：
- `gpt-5`：不期望 apply_patch 指令
- `gpt-5.1`：不期望 apply_patch 指令  
- `gpt-5.1-codex`：不期望 apply_patch 指令
- `gpt-5.1-codex-max`：不期望 apply_patch 指令

### 与 apply_patch 模块的关系

#### 独立 crate 实现
```rust
// codex-rs/apply-patch/src/lib.rs:26
pub const APPLY_PATCH_TOOL_INSTRUCTIONS: &str = include_str!("../apply_patch_tool_instructions.md");
```

`codex-apply-patch` crate 包含独立的 `apply_patch_tool_instructions.md`，内容与 `prompt_with_apply_patch_instructions.md` 中的 apply_patch 部分基本一致。

#### 工具处理器实现
```rust
// codex-rs/core/src/tools/handlers/apply_patch.rs:360-370
pub(crate) fn create_apply_patch_freeform_tool() -> ToolSpec {
    ToolSpec::Freeform(FreeformTool {
        name: "apply_patch".to_string(),
        description: "Use the `apply_patch` tool to edit files...".to_string(),
        format: FreeformToolFormat {
            r#type: "grammar".to_string(),
            syntax: "lark".to_string(),
            definition: APPLY_PATCH_LARK_GRAMMAR.to_string(),
        },
    })
}
```

#### Lark 语法定义
```lark
// codex-rs/core/src/tools/handlers/tool_apply_patch.lark
start: begin_patch hunk+ end_patch
begin_patch: "*** Begin Patch" LF
end_patch: "*** End Patch" LF?

hunk: add_hunk | delete_hunk | update_hunk
add_hunk: "*** Add File: " filename LF add_line+
delete_hunk: "*** Delete File: " filename LF
update_hunk: "*** Update File: " filename LF change_move? change?

filename: /(.+)/
add_line: "+" /(.*)/ LF -> line

change_move: "*** Move to: " filename LF
change: (change_context | change_line)+ eof_line?
change_context: ("@@" | "@@ " /(.+)/) LF
change_line: ("+" | "-" | " ") /(.*)/ LF
eof_line: "*** End of File" LF

%import common.LF
```

## 关键代码路径与文件引用

### 主要引用点
| 文件 | 行号 | 用途 |
|------|------|------|
| `codex-rs/core/src/codex_tests.rs` | 502-503 | 测试中加载完整 prompt |
| `codex-rs/apply-patch/src/lib.rs` | 26 | 独立 crate 的指令定义 |
| `codex-rs/core/src/tools/handlers/apply_patch.rs` | 44 | Lark 语法文件引用 |

### 相关工具文件
| 文件 | 描述 |
|------|------|
| `codex-rs/core/src/tools/handlers/tool_apply_patch.lark` | Lark 语法定义 |
| `codex-rs/apply-patch/apply_patch_tool_instructions.md` | 独立 crate 的指令文档 |
| `codex-rs/core/src/apply_patch.rs` | 补丁应用核心逻辑 |

### 测试覆盖
- `codex-rs/core/src/codex_tests.rs`：`get_base_instructions_no_user_content` 测试
- `codex-rs/core/tests/suite/apply_patch_cli.rs`：CLI 集成测试
- `codex-rs/apply-patch/tests/`：独立 crate 的测试套件

## 依赖与外部交互

### 内部依赖
- `codex-apply-patch` crate：补丁解析和应用逻辑
- `codex_protocol::models::FileChange`：文件变更协议类型
- `similar::TextDiff`：文本差异计算

### 工具系统集成
```
prompt_with_apply_patch_instructions.md
    -> model_info/base_instructions
    -> ModelClient::prompt()
    -> OpenAI Responses API
    -> model generates apply_patch call
    -> ApplyPatchHandler::handle()
    -> ApplyPatchRuntime::run()
    -> codex_apply_patch::parse_patch()
    -> file system changes
```

### 配置交互
- `ModelInfo::apply_patch_tool_type`：决定使用 Freeform 还是 JSON 格式的 apply_patch 工具
- `Config::base_instructions`：可覆盖默认指令

## 风险、边界与改进建议

### 风险点
1. **指令重复**：`prompt.md` 和 `prompt_with_apply_patch_instructions.md` 内容重复，维护成本高
2. **模型特定性**：不同模型对 apply_patch 的理解能力不同，需要差异化处理
3. **格式严格性**：补丁格式要求严格，模型生成的补丁可能有语法错误

### 边界条件
1. **路径限制**：必须使用相对路径，绝对路径会被拒绝
2. **上下文长度**：3 行默认上下文可能不足以唯一确定修改位置
3. **文件大小**：大文件的补丁处理可能受 Token 限制

### 改进建议
1. **单一数据源**：考虑使用代码生成或 include 机制，避免两个文件内容重复
2. **模型自适应**：根据模型能力动态决定是否包含 apply_patch 详细说明
3. **交互式修复**：当补丁解析失败时，提供交互式修复建议
4. **语法高亮**：在 TUI 中提供补丁语法高亮，帮助用户验证
5. **增量验证**：支持补丁的部分应用和验证，提高容错性

### 相关监控点
- 补丁解析失败率
- 模型生成无效补丁的频率
- 用户对补丁应用的撤销率
