# cli.rs 研究文档

## 场景与职责

`cli.rs` 是 `codex-apply-patch` crate 的集成测试文件，负责测试 `apply_patch` 二进制命令行接口 (CLI) 的核心功能。该测试模块验证 CLI 通过命令行参数或标准输入接收 patch 并正确应用到文件系统的能力。

### 文件位置
- **源文件**: `codex-rs/apply-patch/tests/suite/cli.rs`
- **所属 crate**: `codex-apply-patch`
- **测试类型**: 集成测试（通过 `assert_cmd` 调用实际二进制文件）

---

## 功能点目的

### 1. CLI 参数传递测试
验证 `apply_patch` 二进制文件能够通过两种输入方式接收 patch：
- **命令行参数**: `apply_patch '<patch_content>'`
- **标准输入**: `echo '<patch_content>' | apply_patch`

### 2. 基本操作验证
测试覆盖三种核心文件操作：
- **Add File**: 创建新文件并写入内容
- **Update File**: 更新现有文件内容（基于上下文匹配）
- **Delete File**: 删除现有文件

### 3. 输出格式验证
验证成功执行后的标准输出格式符合 git-style 规范：
```
Success. Updated the following files:
A <file_path>    # Added
M <file_path>    # Modified
D <file_path>    # Deleted
```

---

## 具体技术实现

### 关键流程

#### 1. 二进制文件定位
```rust
fn apply_patch_command() -> anyhow::Result<Command> {
    Ok(Command::new(codex_utils_cargo_bin::cargo_bin(
        "apply_patch",
    )?))
}
```
- 使用 `codex_utils_cargo_bin::cargo_bin` 解析二进制文件路径
- 支持 Cargo 和 Bazel 两种构建环境

#### 2. 测试执行流程（以 `test_apply_patch_cli_add_and_update` 为例）

```
1. 创建临时目录 (tempfile::tempdir)
2. 构造 patch 字符串（使用原始字符串字面量 r#"..."#）
3. 执行 apply_patch 命令并传入 patch 参数
4. 验证退出码为 success (0)
5. 验证 stdout 输出包含预期的文件操作标记
6. 验证文件系统状态（文件内容、存在性）
7. 重复测试 Update 操作
```

#### 3. 标准输入测试流程（`test_apply_patch_cli_stdin_add_and_update`）
```rust
apply_patch_command()?
    .current_dir(tmp.path())
    .write_stdin(add_patch)  // 通过 stdin 传递 patch
    .assert()
    .success()
```

### 数据结构

#### Patch 格式规范
测试使用的 patch 遵循以下格式：
```
*** Begin Patch
*** Add File: {filename}
+{line_content}
*** Update File: {filename}
@@
-{old_line}
+{new_line}
*** Delete File: {filename}
*** End Patch
```

#### 行前缀语义
- `+`: 添加行（在 Add File 中表示文件内容，在 Update File 中表示新增内容）
- `-`: 删除行（仅在 Update File 中有效）
- ` `（空格）: 上下文行（用于定位变更位置）
- `@@`: 变更上下文标记（可选，用于定位代码位置）

### 依赖与外部交互

#### 外部依赖
| 依赖 | 用途 |
|------|------|
| `assert_cmd::Command` | 执行和断言外部命令行为 |
| `tempfile::tempdir` | 创建隔离的临时测试目录 |
| `std::fs` | 文件系统断言验证 |
| `codex_utils_cargo_bin::cargo_bin` | 跨构建系统二进制定位 |

#### 被测二进制接口
- **入口**: `codex-rs/apply-patch/src/main.rs` → `codex_apply_patch::main()`
- **实现**: `codex-rs/apply-patch/src/standalone_executable.rs`
- **核心逻辑**: `codex-rs/apply-patch/src/lib.rs` → `apply_patch()`

---

## 关键代码路径与文件引用

### 调用链
```
cli.rs 测试
    ↓ (调用)
apply_patch 二进制 (src/main.rs)
    ↓ (调用)
standalone_executable::run_main()
    ↓ (调用)
lib::apply_patch()
    ↓ (调用)
parser::parse_patch()     // 解析 patch 格式
    ↓ (调用)
lib::apply_hunks()        // 应用变更
    ↓ (调用)
lib::apply_hunks_to_files() // 文件系统操作
```

### 相关文件
| 文件 | 职责 |
|------|------|
| `src/main.rs` | 二进制入口，委托给 lib |
| `src/standalone_executable.rs` | CLI 参数解析、stdin 读取、进程退出码 |
| `src/lib.rs` | 核心 patch 应用逻辑 |
| `src/parser.rs` | Patch 格式解析器 |
| `src/seek_sequence.rs` | 上下文行匹配算法 |

---

## 风险、边界与改进建议

### 当前风险与边界

1. **平台兼容性**
   - 测试使用 `tempfile` 创建临时目录，在 Windows 上路径处理可能有差异
   - 换行符假设为 `\n`，在 Windows 上可能需要特殊处理

2. **测试覆盖范围**
   - 当前仅测试基本 Add/Update 操作
   - 未覆盖错误场景（如无效 patch 格式、权限不足等）
   - 未覆盖并发/竞态条件场景

3. **路径处理**
   - 测试使用相对路径，依赖 `current_dir()` 设置
   - 未显式测试绝对路径场景

### 改进建议

1. **增强错误场景测试**
   ```rust
   // 建议添加：
   - test_apply_patch_cli_invalid_patch_format
   - test_apply_patch_cli_nonexistent_file_update
   - test_apply_patch_cli_permission_denied
   ```

2. **跨平台测试**
   - 添加 Windows 特定的路径测试
   - 验证 CRLF/LF 换行符处理

3. **性能测试**
   - 添加大文件 patch 应用性能基准
   - 测试多文件批量操作

4. **测试可读性**
   - 当前 patch 字符串使用 format! 内联，建议提取为 fixture 文件
   - 可考虑使用 `indoc` crate 改善多行字符串可读性

### 与 scenarios.rs 的关系

`cli.rs` 与 `scenarios.rs` 形成互补测试策略：
- **cli.rs**: 快速验证 CLI 接口的基本功能（参数传递、stdin、输出格式）
- **scenarios.rs**: 基于 fixture 目录的综合场景测试（见 scenarios.rs_research.md）

两者共同确保 `apply_patch` 二进制在接口层和功能层的正确性。
