# 006_rejects_missing_context/patch.txt 深度研究文档

## 场景与职责

### 测试场景定位

`006_rejects_missing_context` 是 `codex-apply-patch` 组件的端到端测试场景之一，属于 **错误处理/边界测试** 类别。该场景专门测试当 patch 中指定的上下文（context）在目标文件中不存在时，系统应当如何正确拒绝应用 patch。

### 目录结构

```
006_rejects_missing_context/
├── input/
│   └── modify.txt          # 初始文件内容: "line1\nline2\n"
├── expected/
│   └── modify.txt          # 期望的最终状态: "line1\nline2\n" (保持不变)
└── patch.txt               # 尝试应用但会失败的 patch
```

### 核心职责

该测试场景验证以下关键行为：

1. **拒绝无效上下文**：当 patch 中指定的 `old_lines`（以 `-` 开头的行）在目标文件中找不到时，应用必须失败
2. **原子性保证**：patch 应用失败时，目标文件应保持原状（不被修改）
3. **错误信息清晰**：系统应提供有意义的错误信息，指出哪些期望的行未找到

---

## 功能点目的

### 测试的具体功能

该场景测试 `apply_patch` 工具的 **上下文匹配失败处理** 机制：

| 功能点 | 说明 |
|--------|------|
| 上下文匹配 | Patch 中的 `-missing` 表示期望在文件中找到 "missing" 这一行 |
| 失败拒绝 | 由于实际文件内容为 "line1" 和 "line2"，不包含 "missing"，应用必须失败 |
| 文件完整性 | 失败后，文件应保持原始内容不变 |

### 业务价值

- **防止数据损坏**：确保错误的 patch 不会意外修改文件
- **开发者体验**：提供清晰的错误反馈，帮助用户修正 patch
- **自动化安全**：在 CI/CD 流程中防止错误的代码变更被应用

---

## 具体技术实现

### 1. Patch 格式解析

**patch.txt 内容：**
```
*** Begin Patch
*** Update File: modify.txt
@@
-missing
+changed
*** End Patch
```

**格式解析：**

| 行 | 含义 |
|----|------|
| `*** Begin Patch` | Patch 开始标记 |
| `*** Update File: modify.txt` | 指定要更新的文件 |
| `@@` | Hunk 开始标记（空上下文） |
| `-missing` | 期望在文件中找到并删除的行 |
| `+changed` | 要添加的替换行 |
| `*** End Patch` | Patch 结束标记 |

### 2. 关键数据结构

#### UpdateFileChunk（位于 `parser.rs`）

```rust
pub struct UpdateFileChunk {
    /// 用于定位 chunk 位置的上下文行（如 @@ class Foo）
    pub change_context: Option<String>,
    
    /// 要被替换的旧行（对应 patch 中以 `-` 开头的行）
    pub old_lines: Vec<String>,
    
    /// 新行（对应 patch 中以 `+` 开头的行）
    pub new_lines: Vec<String>,
    
    /// 是否必须在文件末尾匹配
    pub is_end_of_file: bool,
}
```

在本场景中：
- `change_context`: `None`（因为 `@@` 后没有内容）
- `old_lines`: `["missing"]`
- `new_lines`: `["changed"]`
- `is_end_of_file`: `false`

### 3. 核心匹配流程

#### 阶段 1：解析 Patch（`parser.rs`）

```rust
pub fn parse_patch(patch: &str) -> Result<ApplyPatchArgs, ParseError>
```

1. 验证 patch 边界（`*** Begin Patch` / `*** End Patch`）
2. 解析每个 hunk（本场景只有一个 UpdateFile hunk）
3. 构建 `UpdateFileChunk` 结构

#### 阶段 2：计算替换（`lib.rs: compute_replacements`）

```rust
fn compute_replacements(
    original_lines: &[String],
    path: &Path,
    chunks: &[UpdateFileChunk],
) -> Result<Vec<(usize, usize, Vec<String>)>, ApplyPatchError>
```

关键逻辑：

```rust
// 对于每个 chunk，尝试找到 old_lines
for chunk in chunks {
    // 1. 处理上下文定位（本场景无上下文）
    if let Some(ctx_line) = &chunk.change_context {
        // 使用 seek_sequence 定位上下文
    }
    
    // 2. 尝试匹配 old_lines
    let pattern: &[String] = &chunk.old_lines;
    let found = seek_sequence::seek_sequence(
        original_lines, 
        pattern, 
        line_index, 
        chunk.is_end_of_file
    );
    
    // 3. 如果找不到，返回错误
    if found.is_none() {
        return Err(ApplyPatchError::ComputeReplacements(format!(
            "Failed to find expected lines in {}:\n{}",
            path.display(),
            chunk.old_lines.join("\n"),
        )));
    }
}
```

#### 阶段 3：序列搜索（`seek_sequence.rs`）

```rust
pub(crate) fn seek_sequence(
    lines: &[String],
    pattern: &[String],
    start: usize,
    eof: bool,
) -> Option<usize>
```

搜索策略（按优先级）：

1. **精确匹配**：逐字节比较
2. **右空白忽略匹配**：忽略行尾空白
3. **全空白忽略匹配**：忽略行首和行尾空白
4. **Unicode 规范化匹配**：将特殊 Unicode 字符（如引号、破折号）映射为 ASCII 等价物

本场景中，由于 `lines = ["line1", "line2"]` 而 `pattern = ["missing"]`，所有匹配策略都会失败，返回 `None`。

### 4. 错误处理流程

```rust
// lib.rs: apply_hunks_to_files
match apply_hunks_to_files(hunks) {
    Ok(affected) => { /* 成功处理 */ }
    Err(err) => {
        let msg = err.to_string();
        writeln!(stderr, "{msg}").map_err(ApplyPatchError::from)?;
        // 返回错误，exit code 非零
        Err(ApplyPatchError::IoError(...))
    }
}
```

**错误输出示例：**
```
Failed to find expected lines in modify.txt:
missing
```

---

## 关键代码路径与文件引用

### 核心文件依赖图

```
patch.txt
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│  codex-rs/apply-patch/src/standalone_executable.rs          │
│  - main() 入口函数                                          │
│  - 从参数或 stdin 读取 patch                                │
└─────────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│  codex-rs/apply-patch/src/lib.rs                            │
│  - apply_patch()                                            │
│  - apply_hunks()                                            │
│  - apply_hunks_to_files()                                   │
│  - derive_new_contents_from_chunks()                        │
│  - compute_replacements()  <-- 错误发生地                   │
└─────────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│  codex-rs/apply-patch/src/parser.rs                         │
│  - parse_patch()                                            │
│  - parse_one_hunk()                                         │
│  - parse_update_file_chunk()                                │
└─────────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│  codex-rs/apply-patch/src/seek_sequence.rs                  │
│  - seek_sequence()  <-- 匹配失败返回 None                   │
└─────────────────────────────────────────────────────────────┘
```

### 关键代码位置

| 文件 | 行号范围 | 功能 |
|------|----------|------|
| `src/standalone_executable.rs` | 1-59 | CLI 入口，参数处理 |
| `src/lib.rs` | 183-213 | `apply_patch()` 主函数 |
| `src/lib.rs` | 215-266 | `apply_hunks()` 协调应用 |
| `src/lib.rs` | 279-339 | `apply_hunks_to_files()` 文件操作 |
| `src/lib.rs` | 346-381 | `derive_new_contents_from_chunks()` |
| `src/lib.rs` | 386-474 | `compute_replacements()` - 核心匹配逻辑 |
| `src/lib.rs` | 476-502 | `apply_replacements()` |
| `src/parser.rs` | 106-113 | `parse_patch()` 入口 |
| `src/parser.rs` | 246-341 | `parse_one_hunk()` hunk 解析 |
| `src/parser.rs` | 343-434 | `parse_update_file_chunk()` chunk 解析 |
| `src/seek_sequence.rs` | 12-110 | `seek_sequence()` 模糊匹配算法 |

### 测试相关文件

| 文件 | 说明 |
|------|------|
| `tests/suite/scenarios.rs` | 场景测试框架，`run_apply_patch_scenario()` |
| `tests/suite/tool.rs` | CLI 测试，`test_apply_patch_cli_reports_missing_context()` |
| `tests/fixtures/scenarios/006_rejects_missing_context/` | 本场景数据 |

---

## 依赖与外部交互

### 内部依赖

```rust
// Cargo.toml
dependencies:
- anyhow          // 错误处理
- similar         // 文本差异计算（TextDiff）
- thiserror       // 错误派生宏
- tree-sitter     // Bash 脚本解析（用于 heredoc 提取）
- tree-sitter-bash
```

### 外部系统交互

| 交互对象 | 类型 | 说明 |
|----------|------|------|
| 文件系统 | 读取 | 读取 `input/modify.txt` |
| 文件系统 | 无写入 | 由于匹配失败，不会写入文件 |
| stdout | 写入 | 输出 "Success..."（本场景不会执行） |
| stderr | 写入 | 输出错误信息 |
| 进程退出码 | 返回 | 失败时返回 1 |

### 与调用方的契约

```rust
// 在 codex-core 中通过 invocation.rs 调用
pub fn maybe_parse_apply_patch_verified(
    argv: &[String], 
    cwd: &Path
) -> MaybeApplyPatchVerified
```

当上下文匹配失败时，返回：
```rust
MaybeApplyPatchVerified::CorrectnessError(
    ApplyPatchError::ComputeReplacements("Failed to find expected lines...")
)
```

---

## 风险、边界与改进建议

### 当前风险

#### 1. 模糊匹配的误报风险

**问题**：`seek_sequence.rs` 实现了多级模糊匹配（空白忽略、Unicode 规范化），在某些极端情况下可能导致意外匹配。

**示例风险场景**：
```
文件内容：["foo", "bar"]
Patch 期望：["foo  ", "bar"]（带尾随空格）
结果：可能意外匹配成功
```

**缓解**：多级匹配策略按严格程度排序，优先使用最严格的匹配方式。

#### 2. 错误信息不够详细

**当前错误**：
```
Failed to find expected lines in modify.txt:
missing
```

**改进建议**：增加行号、附近内容等上下文信息：
```
Failed to find expected lines in modify.txt at line 1:
Expected: "missing"
File content around that area:
  1: line1
  2: line2
```

#### 3. 无部分应用机制

**问题**：在多 chunk 场景中，如果第一个 chunk 成功但第二个失败，第一个的修改会被回滚。但对于复杂场景，用户可能希望了解哪些部分可以成功。

### 边界情况

| 边界情况 | 当前行为 | 评估 |
|----------|----------|------|
| 空文件 + 非空 old_lines | 匹配失败 | ✅ 正确 |
| 文件存在但为空行差异 | 依赖模糊匹配 | ⚠️ 需注意 |
| 多行 old_lines 部分匹配 | 整体失败 | ✅ 正确 |
| 非常大的文件 | 线性搜索，O(n*m) | ⚠️ 性能考虑 |
| 特殊 Unicode 字符 | 规范化后匹配 | ✅ 用户友好 |

### 改进建议

#### 1. 增强错误诊断

```rust
// 建议添加
fn format_match_failure_context(
    path: &Path,
    expected: &[String],
    actual_lines: &[String],
    search_start: usize,
) -> String {
    // 显示文件内容、期望内容、最近匹配区域
}
```

#### 2. 支持交互式修复建议

当匹配失败时，可以建议可能的正确上下文：
```
Failed to find "missing" in modify.txt.
Did you mean one of these?
  - "line1" (line 1)
  - "line2" (line 2)
```

#### 3. 性能优化

对于大文件，考虑：
- 使用 Boyer-Moore 或 KMP 算法进行多模式匹配
- 建立行哈希索引加速查找
- 对频繁访问的文件进行缓存

#### 4. 更严格的模式验证

添加可选的 `--strict` 模式：
- 禁用 Unicode 规范化
- 禁用空白忽略
- 要求精确字节匹配

#### 5. 测试覆盖增强

建议添加的测试场景：
- 多 chunk 场景下第一个 chunk 匹配成功但第二个失败
- 特殊字符（制表符、零宽字符）的匹配行为
- 非常大的文件（>10MB）的性能测试
- 并发应用 patch 的测试

### 安全考虑

| 风险 | 评估 | 建议 |
|------|------|------|
| 路径遍历 | 低 | 已使用 `Path::join`，但应验证无 `..` |
| 正则表达式 DoS | 无 | 未使用正则 |
| 内存耗尽 | 低 | 文件内容一次性读入内存，应设置大小限制 |
| 竞争条件 | 中 | 文件读取和写入非原子操作，应考虑文件锁 |

---

## 总结

`006_rejects_missing_context` 场景是 `apply_patch` 工具错误处理能力的核心测试之一。它验证了当 patch 指定的内容与文件实际内容不匹配时，系统能够：

1. **正确检测** 不匹配情况（通过 `seek_sequence` 的多级匹配策略）
2. **优雅失败** 并提供清晰的错误信息
3. **保持文件完整性**（失败时不修改文件）

该实现采用了合理的模糊匹配策略来容忍常见的格式差异（如空白、Unicode 变体），但在严格性上仍有提升空间。建议未来版本增加更详细的错误诊断和可选的严格匹配模式。
