# README.md 研究文档

## 场景与职责

`README.md` 文件位于 `codex-rs/apply-patch/tests/fixtures/scenarios/` 目录下，是 **apply-patch 端到端测试场景的规范文档**。它定义了测试夹具（test fixtures）的目录结构、命名约定和语义，确保测试用例的可移植性和一致性。

该文档服务于以下目标：
1. **规范定义**：为测试场景提供统一的结构标准
2. **跨平台可移植性**：设计易于移植到其他语言或平台的测试格式
3. **简化测试编写**：每个测试只验证一个补丁操作，保持简单性
4. **文档即契约**：通过示例说明期望的测试结构

## 功能点目的

### 核心设计原则

文档明确提出了以下设计决策：

| 原则 | 说明 |
|------|------|
| 单一职责 | 每个测试用例只测试一个补丁操作 |
| 声明式 | 通过目录结构声明输入和期望输出 |
| 隔离性 | 输入（`input/`）和期望输出（`expected/`）分离 |
| 自包含 | 每个测试目录包含完整的测试数据 |

### 目录结构规范

```
<test_case_name>/
├── input/           # 初始文件状态（可选，某些测试可能无输入）
│   └── <files...>
├── expected/        # 期望的最终文件状态
│   └── <files...>
└── patch.txt        # 要应用的补丁内容
```

### 命名约定

测试用例目录使用编号前缀 + 描述性名称：
- `001_add`：添加文件的基础测试
- `002_multiple_operations`：多个操作的组合测试
- `005_rejects_empty_patch`：错误处理测试（期望失败场景）

编号前缀确保：
1. 文件系统按顺序列出测试
2. 新测试可以插入到合适的位置
3. 避免名称冲突

## 具体技术实现

### 测试执行机制

测试执行代码位于 `codex-rs/apply-patch/tests/suite/scenarios.rs`：

```rust
#[test]
fn test_apply_patch_scenarios() -> anyhow::Result<()> {
    let scenarios_dir = repo_root()?
        .join("codex-rs")
        .join("apply-patch")
        .join("tests")
        .join("fixtures")
        .join("scenarios");
    
    // 遍历所有子目录作为测试场景
    for scenario in fs::read_dir(scenarios_dir)? {
        let scenario = scenario?;
        let path = scenario.path();
        if path.is_dir() {
            run_apply_patch_scenario(&path)?;
        }
    }
    Ok(())
}
```

### 单个场景执行流程

```rust
fn run_apply_patch_scenario(dir: &Path) -> anyhow::Result<()> {
    let tmp = tempdir()?;
    
    // 1. 复制输入文件到临时目录
    let input_dir = dir.join("input");
    if input_dir.is_dir() {
        copy_dir_recursive(&input_dir, tmp.path())?;
    }
    
    // 2. 读取 patch.txt
    let patch = fs::read_to_string(dir.join("patch.txt"))?;
    
    // 3. 执行 apply_patch（不检查退出码）
    Command::new(cargo_bin("apply_patch")?)
        .arg(patch)
        .current_dir(tmp.path())
        .output()?;
    
    // 4. 比较实际输出与期望状态
    let expected_snapshot = snapshot_dir(&dir.join("expected"))?;
    let actual_snapshot = snapshot_dir(tmp.path())?;
    assert_eq!(actual_snapshot, expected_snapshot, "...");
    
    Ok(())
}
```

### 快照比较机制

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
enum Entry {
    File(Vec<u8>),  // 文件内容（字节级）
    Dir,            // 目录标记
}

fn snapshot_dir(root: &Path) -> anyhow::Result<BTreeMap<PathBuf, Entry>> {
    // 递归遍历目录，构建路径 -> 内容/类型的映射
    // 使用 BTreeMap 确保确定性排序
}
```

**关键特性**：
- 字节级比较：确保文件内容完全一致
- 目录结构验证：验证文件是否存在/不存在
- 排序确定性：使用 `BTreeMap` 保证输出顺序一致

### 补丁格式

`patch.txt` 使用自定义的 apply-patch 格式，由 `parser.rs` 解析：

```
*** Begin Patch
*** Add File: bar.md
+This is a new file
*** End Patch
```

支持的 hunk 类型：
- `*** Add File: <path>`：添加新文件
- `*** Delete File: <path>`：删除文件
- `*** Update File: <path>`：更新文件内容（支持移动）

## 关键代码路径与文件引用

### 测试框架文件

| 文件 | 职责 |
|------|------|
| `tests/suite/scenarios.rs` | 场景测试执行器 |
| `tests/all.rs` | 测试入口，聚合所有子模块 |
| `tests/suite/mod.rs` | 测试套件模块定义 |
| `tests/suite/cli.rs` | CLI 测试 |
| `tests/suite/tool.rs` | 工具函数测试 |

### 被测代码文件

| 文件 | 职责 |
|------|------|
| `src/lib.rs` | 补丁应用核心逻辑（`apply_patch`, `apply_hunks`） |
| `src/parser.rs` | 补丁解析器（`parse_patch`, `Hunk` 类型） |
| `src/seek_sequence.rs` | 行序列匹配算法 |
| `src/main.rs` | CLI 入口 |
| `src/invocation.rs` | 调用解析（heredoc 处理等） |
| `src/standalone_executable.rs` | 独立可执行文件支持 |

### 当前测试场景列表（22个）

| 编号 | 场景 | 测试目的 |
|------|------|---------|
| 001 | add_file | 基础文件添加 |
| 002 | multiple_operations | 多操作组合 |
| 003 | multiple_chunks | 多 chunk 更新 |
| 004 | move_to_new_directory | 移动到新目录 |
| 005 | rejects_empty_patch | 空补丁拒绝 |
| 006 | rejects_missing_context | 缺失上下文拒绝 |
| 007 | rejects_missing_file_delete | 删除不存在的文件 |
| 008 | rejects_empty_update_hunk | 空更新 hunk 拒绝 |
| 009 | requires_existing_file_for_update | 更新必须文件存在 |
| 010 | move_overwrites_existing_destination | 移动覆盖目标 |
| 011 | add_overwrites_existing_file | 添加覆盖已存在文件 |
| 012 | delete_directory_fails | 删除目录失败 |
| 013 | rejects_invalid_hunk_header | 无效 hunk 头拒绝 |
| 014 | update_file_appends_trailing_newline | 自动追加换行 |
| 015 | failure_after_partial_success_leaves_changes | 部分成功保留更改 |
| 016 | pure_addition_update_chunk | 纯添加更新 chunk |
| 017 | whitespace_padded_hunk_header | 空白填充 hunk 头 |
| 018 | whitespace_padded_patch_markers | 空白填充补丁标记 |
| 019 | unicode_simple | Unicode 简单测试 |
| 020 | delete_file_success | 删除文件成功 |
| 020 | whitespace_padded_patch_marker_lines | 空白填充标记行 |
| 021 | update_file_deletion_only | 仅删除更新 |
| 022 | update_file_end_of_file_marker | EOF 标记测试 |

## 依赖与外部交互

### 外部依赖

1. **文件系统**：
   - 使用 `tempfile` crate 创建临时目录
   - 使用标准库 `fs` 进行文件操作

2. **进程执行**：
   - 使用 `std::process::Command` 执行 `apply_patch` 二进制
   - 通过 `codex_utils_cargo_bin` 解析二进制路径

3. **断言库**：
   - `pretty_assertions`：提供清晰的差异输出
   - `anyhow`：错误处理

### 与 Bazel 构建系统的兼容性

代码中特别处理了 Bazel 的符号链接树：

```rust
// 在 snapshot_dir_recursive 和 copy_dir_recursive 中
// 使用 metadata() 而非 symlink_metadata()
// 以正确跟随符号链接
let metadata = fs::metadata(&path)?;
```

注释说明：
> Under Buck2, files in `__srcs` are often materialized as symlinks.
> Use `metadata()` (follows symlinks) so our fixture snapshots work
> under both Cargo and Buck2.

## 风险、边界与改进建议

### 当前局限性

1. **不验证退出码**：
   ```rust
   // 注意：有意不在这里断言退出状态
   Command::new(...).output()?;
   ```
   测试仅通过文件系统状态验证结果，不验证进程退出码。这意味着即使 `apply_patch` 返回错误码但文件状态正确，测试也会通过。

2. **无 stderr 验证**：
   错误消息和警告未被验证，可能遗漏重要的用户体验回归。

3. **测试名称冲突**：
   观察到 `020` 编号被两个测试共享（`delete_file_success` 和 `whitespace_padded_patch_marker_lines`），这可能导致混淆。

### 边界情况

| 场景 | 当前行为 |
|------|---------|
| `input/` 目录不存在 | 视为空输入，从空目录开始 |
| `expected/` 目录为空 | 验证最终状态为空 |
| 二进制文件 | 通过字节级比较支持 |
| 符号链接 | 跟随链接，比较目标内容 |
| 特殊字符文件名 | 依赖 `PathBuf` 处理 |

### 改进建议

1. **添加退出码验证**：
   ```rust
   let output = Command::new(...).output()?;
   let expect_success = !dir.file_name().unwrap().to_str().unwrap().contains("rejects");
   if expect_success {
       assert!(output.status.success(), "...");
   } else {
       assert!(!output.status.success(), "...");
   }
   ```

2. **添加 stderr 快照测试**：
   ```rust
   // 添加 expected/stderr.txt 可选文件
   if let Ok(expected_stderr) = fs::read_to_string(dir.join("expected_stderr.txt")) {
       assert_eq!(String::from_utf8_lossy(&output.stderr), expected_stderr);
   }
   ```

3. **修复编号冲突**：
   将 `020_whitespace_padded_patch_marker_lines` 重命名为 `023_...`

4. **添加元数据文件**：
   每个场景添加 `meta.toml` 描述：
   ```toml
   name = "add_file"
   description = "测试基础文件添加功能"
   expected_exit_code = 0
   tags = ["basic", "add"]
   ```

5. **支持部分匹配**：
   某些测试可能只需要验证特定文件存在，而非完整目录快照。

6. **添加性能测试**：
   大型文件的补丁应用性能测试。

### 可移植性考虑

README 提到测试设计为 "easily portable to other languages or platforms"。要实现这一目标：

1. **文档化补丁格式**：
   当前格式仅在代码中定义，应提供独立的规范文档。

2. **提供参考实现**：
   提供 Python/JavaScript 等语言的解析器示例。

3. **标准化测试运行器接口**：
   定义测试运行器的输入/输出接口，便于其他语言实现。

4. **分离测试数据与代码**：
   考虑将测试场景发布为独立的 npm/pip 包。
