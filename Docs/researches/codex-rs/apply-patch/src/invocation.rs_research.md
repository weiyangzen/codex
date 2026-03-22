# invocation.rs 深度研究文档

## 场景与职责

`invocation.rs` 是 `codex-apply-patch` crate 的核心模块之一，负责**解析和识别** `apply_patch` 命令的调用形式。该模块的主要使用场景包括：

1. **多平台 Shell 脚本解析**：支持从 bash、zsh、PowerShell、Cmd 等 shell 脚本中提取 heredoc 形式的 patch 内容
2. **命令行参数解析**：处理直接调用 `apply_patch <patch>` 和通过 shell heredoc 调用两种形式
3. **安全验证**：防止隐式 patch 调用（implicit invocation）导致的安全问题
4. **工作目录解析**：支持 `cd <path> && apply_patch <<'EOF'` 形式的工作目录切换

该模块在 Codex CLI 的 arg0 分发机制中被调用（`codex-rs/arg0/src/lib.rs`），用于判断用户输入是否为 apply_patch 调用。

## 功能点目的

### 1. Shell 类型识别与分类
- **目的**：识别不同操作系统和 shell 的调用模式
- **支持类型**：Unix (bash/zsh/sh)、PowerShell、Cmd
- **关键函数**：`classify_shell()`、`classify_shell_name()`

### 2. Heredoc 内容提取
- **目的**：从 shell 脚本中提取 `apply_patch <<'EOF' ... EOF` 格式的 patch 内容
- **技术方案**：使用 Tree-sitter Bash 解析器进行 AST 级解析
- **关键函数**：`extract_apply_patch_from_bash()`

### 3. 隐式调用防护
- **目的**：防止 raw patch body 被错误地直接应用
- **机制**：`maybe_parse_apply_patch_verified()` 检测并拒绝隐式调用
- **错误类型**：`ApplyPatchError::ImplicitInvocation`

### 4. 路径解析与工作目录处理
- **目的**：正确处理相对路径和绝对路径，支持 `cd` 前缀
- **功能**：将 patch 中的相对路径解析为基于 effective_cwd 的绝对路径

## 具体技术实现

### 核心数据结构

```rust
// Shell 类型枚举
enum ApplyPatchShell {
    Unix,
    PowerShell,
    Cmd,
}

// 解析结果枚举
pub enum MaybeApplyPatch {
    Body(ApplyPatchArgs),           // 成功解析
    ShellParseError(ExtractHeredocError),  // Shell 解析错误
    PatchParseError(ParseError),    // Patch 内容解析错误
    NotApplyPatch,                  // 非 apply_patch 调用
}

// 带验证的解析结果
pub enum MaybeApplyPatchVerified {
    Body(ApplyPatchAction),
    ShellParseError(ExtractHeredocError),
    CorrectnessError(ApplyPatchError),  // 包含 ImplicitInvocation
    NotApplyPatch,
}

// Heredoc 提取错误类型
pub enum ExtractHeredocError {
    CommandDidNotStartWithApplyPatch,
    FailedToLoadBashGrammar(LanguageError),
    HeredocNotUtf8(Utf8Error),
    FailedToParsePatchIntoAst,
    FailedToFindHeredocBody,
}
```

### Tree-sitter Query 详解

模块使用复杂的 Tree-sitter Query 来匹配两种 shell 形式：

```rust
// 形式 1: 直接 heredoc
// apply_patch <<'EOF'\n...\nEOF
(
  program
    . (redirected_statement
        body: (command
                name: (command_name (word) @apply_name) .)
        (#any-of? @apply_name "apply_patch" "applypatch")
        redirect: (heredoc_redirect
                    . (heredoc_start)
                    . (heredoc_body) @heredoc
                    . (heredoc_end)
                    .))
    .)

// 形式 2: 带 cd 前缀的 heredoc
// cd <path> && apply_patch <<'EOF'\n...\nEOF
(
  program
    . (redirected_statement
        body: (list
                . (command
                    name: (command_name (word) @cd_name) .
                    argument: [
                      (word) @cd_path
                      (string (string_content) @cd_path)
                      (raw_string) @cd_raw_string
                    ] .)
                "&&"
                . (command
                    name: (command_name (word) @apply_name))
                .)
        (#eq? @cd_name "cd")
        (#any-of? @apply_name "apply_patch" "applypatch")
        redirect: (heredoc_redirect
                    . (heredoc_start)
                    . (heredoc_body) @heredoc
                    . (heredoc_end)
                    .))
    .)
```

**Query 设计要点**：
- 使用 `.` 锚点确保匹配是唯一的顶层语句
- 使用 `#any-of?` 和 `#eq?` 谓词进行精确匹配
- 支持三种 cd 路径格式：普通 word、双引号字符串、单引号 raw_string

### 关键流程

#### 1. 命令解析流程 (`maybe_parse_apply_patch`)
```
argv 输入
    │
    ├──► 直接调用形式？
    │    [cmd, body] where cmd ∈ ["apply_patch", "applypatch"]
    │    └──► 直接解析 patch body
    │
    └──► Shell heredoc 形式？
         └──► parse_shell_script()
              └──► classify_shell() 识别 shell 类型
              └──► extract_apply_patch_from_shell()
                   └──► extract_apply_patch_from_bash()
                        └──► Tree-sitter 解析
                             └──► 返回 (heredoc_body, workdir)
```

#### 2. 验证流程 (`maybe_parse_apply_patch_verified`)
```
argv + cwd 输入
    │
    ├──► 隐式调用检查（直接 patch body 或 patch body 作为 shell 脚本）
    │    └──► 拒绝并返回 ImplicitInvocation 错误
    │
    └──► 调用 maybe_parse_apply_patch()
         └──► 成功解析后，处理每个 hunk
              ├──► AddFile: 记录添加操作
              ├──► DeleteFile: 读取原文件内容，记录删除操作
              └──► UpdateFile: 
                   └──► unified_diff_from_chunks() 生成统一 diff
                   └──► 记录更新操作（含可选 move_path）
```

### 路径解析逻辑

```rust
let effective_cwd = workdir
    .as_ref()
    .map(|dir| {
        let path = Path::new(dir);
        if path.is_absolute() {
            path.to_path_buf()
        } else {
            cwd.join(path)  // 相对路径基于传入的 cwd 解析
        }
    })
    .unwrap_or_else(|| cwd.to_path_buf());
```

## 关键代码路径与文件引用

### 内部依赖
| 模块 | 用途 |
|------|------|
| `parser::parse_patch` | 解析 patch 文本为结构化 hunks |
| `parser::Hunk` | Hunk 类型定义（AddFile/DeleteFile/UpdateFile）|
| `unified_diff_from_chunks` | 从 chunks 生成统一 diff 格式 |
| `ApplyPatchArgs` | 解析后的 patch 参数结构 |
| `ApplyPatchAction` | 验证后的可执行动作 |
| `ApplyPatchFileChange` | 文件变更类型（Add/Delete/Update）|

### 外部依赖
| Crate | 用途 |
|-------|------|
| `tree-sitter` | Bash 脚本 AST 解析 |
| `tree-sitter-bash` | Bash 语法定义 |

### 调用方
| 文件 | 调用点 |
|------|--------|
| `codex-rs/arg0/src/lib.rs` | `arg0_dispatch()` 中检测 `apply_patch` 别名调用 |
| `codex-rs/core/src/lib.rs` | `maybe_parse_apply_patch_verified()` 用于验证工具调用 |

## 依赖与外部交互

### 与 arg0 模块的交互

```rust
// codex-rs/arg0/src/lib.rs
if exe_name == APPLY_PATCH_ARG0 || exe_name == MISSPELLED_APPLY_PATCH_ARG0 {
    codex_apply_patch::main();  // 直接执行 apply_patch
}

// 或通过 --codex-run-as-apply-patch 标志调用
if argv1 == CODEX_CORE_APPLY_PATCH_ARG1 {
    codex_apply_patch::apply_patch(&patch_arg, &mut stdout, &mut stderr);
}
```

### 与 core 模块的交互

`codex-rs/core/src/lib.rs` 中的 `convert_apply_patch_to_protocol()` 函数将 `ApplyPatchAction` 转换为协议层的 `FileChange` 类型。

## 风险、边界与改进建议

### 已知风险

1. **Tree-sitter 解析失败**
   - 风险：复杂的 bash 脚本可能无法被 Tree-sitter 正确解析
   - 缓解：保守的 Query 设计，仅匹配明确的形式

2. **隐式调用攻击**
   - 风险：恶意构造的输入可能被误认为 patch
   - 缓解：`maybe_parse_apply_patch_verified()` 显式检测并拒绝

3. **路径遍历风险**
   - 风险：`cd` 路径可能包含 `../` 等遍历序列
   - 现状：当前实现直接拼接路径，依赖调用方验证

### 边界情况

| 场景 | 行为 |
|------|------|
| `cd foo; apply_patch <<EOF` | 拒绝（必须用 `&&` 连接）|
| `cd foo \|\| apply_patch <<EOF` | 拒绝（必须用 `&&` 连接）|
| `echo foo && apply_patch <<EOF` | 拒绝（cd 前缀必须）|
| `cd foo && cd bar && apply_patch <<EOF` | 拒绝（仅支持单级 cd）|
| `apply_patch foo <<EOF` | 拒绝（不接受位置参数）|
| PowerShell `-NoProfile` 标志 | 自动跳过并继续解析 |

### 改进建议

1. **增强路径验证**
   - 对 `cd_path` 进行规范化处理，防止路径遍历攻击
   - 验证最终路径是否在允许的工作目录范围内

2. **扩展 Shell 支持**
   - 当前 Cmd/PowerShell 实际使用相同的 Bash 解析逻辑
   - 可考虑添加 PowerShell 原生解析支持

3. **错误信息改进**
   - 当前 `CommandDidNotStartWithApplyPatch` 错误较笼统
   - 可提供更详细的匹配失败原因

4. **性能优化**
   - `APPLY_PATCH_QUERY` 使用 `LazyLock` 已优化
   - 考虑缓存 Parser 实例以减少重复创建开销

5. **测试覆盖**
   - 当前测试覆盖主要场景
   - 建议增加畸形输入的模糊测试
