# README.md 研究文档

## 场景与职责

该 README.md 文件是 `codex-utils-cargo-bin` crate 的文档，位于 `codex-rs/utils/cargo-bin/` 目录。它解释了该 crate 的核心设计决策：为何以及如何使用 runfiles manifest 策略来支持 Bazel 和 Cargo 双构建系统。

核心职责：
1. 说明 runfiles 策略的选择原因（禁用目录策略，统一使用 manifest 策略）
2. 解释主要 API 的行为（`cargo_bin` 和 `find_resource!`）
3. 提供 Bazel runfiles 的背景链接

## 功能点目的

### 1. Runfiles 策略说明

```markdown
We disable the directory-based runfiles strategy and rely on the manifest
strategy across all platforms. This avoids Windows path length issues and keeps
behavior consistent in local and remote builds on all platforms.
```

**目的**：明确声明项目使用 runfiles manifest 策略而非目录策略。

**技术背景**：
- Bazel 支持两种 runfiles 策略：
  1. **目录策略（directory-based）**：创建一个符号链接树（runfiles 目录）
  2. **Manifest 策略（manifest-based）**：生成一个 manifest 文件，列出所有 runfiles 的映射关系

**选择 manifest 策略的原因**：
1. **Windows 路径长度限制**：Windows 有 260 字符的路径长度限制（MAX_PATH），符号链接树容易超出
2. **远程构建一致性**：远程执行环境可能没有符号链接支持
3. **跨平台一致性**：所有平台使用相同机制，减少平台相关 bug

### 2. cargo_bin 函数行为

```markdown
- `cargo_bin`: reads `CARGO_BIN_EXE_*` environment variables (set by Cargo or
  Bazel) and resolves them via the runfiles manifest when `RUNFILES_MANIFEST_FILE`
  is present. When not under runfiles, it only accepts absolute paths from
  `CARGO_BIN_EXE_*` and returns an error otherwise.
```

**目的**：解释 `cargo_bin` 函数如何在不同构建系统中工作。

**工作流程**：
1. 读取 `CARGO_BIN_EXE_<binary>` 环境变量（Cargo 设置）或 `CARGO_BIN_EXE_<binary>`（Bazel 通过 `defs.bzl` 设置）
2. 如果 `RUNFILES_MANIFEST_FILE` 存在（Bazel 构建），使用 runfiles manifest 解析路径
3. 如果不存在（Cargo 构建），要求路径必须是绝对路径

**关键区别**：
| 构建系统 | 环境变量值 | 解析方式 |
|----------|-----------|----------|
| Cargo | 绝对路径 | 直接使用 |
| Bazel | rlocation 路径（如 `_main/codex-rs/...`） | 通过 runfiles crate 解析 |

### 3. find_resource! 宏行为

```markdown
- `find_resource!`: used by tests to locate fixtures. It chooses the Bazel
  runfiles resolution path when `RUNFILES_MANIFEST_FILE` is set, otherwise it
  falls back to a `CARGO_MANIFEST_DIR`-relative path for Cargo runs.
```

**目的**：解释 `find_resource!` 宏如何帮助测试代码定位 fixture 文件。

**工作流程**：
1. 检查 `RUNFILES_MANIFEST_FILE` 环境变量
2. 如果存在：使用 Bazel runfiles 解析（通过 `BAZEL_PACKAGE` 编译期变量构建完整路径）
3. 如果不存在：使用 `CARGO_MANIFEST_DIR` 相对路径

**路径构建示例**：
```
Bazel: _main/codex-rs/core/tests/fixtures/test.json
Cargo: <CARGO_MANIFEST_DIR>/tests/fixtures/test.json
```

### 4. 背景链接

```markdown
Background:
- https://bazel.build/docs/runfiles
- https://bazel.build/docs/runfiles#runfiles-manifest
```

**目的**：提供官方文档链接，供开发者深入了解 runfiles 机制。

## 具体技术实现

### 环境变量交互

README 中提到的关键环境变量：

| 环境变量 | 设置者 | 用途 |
|----------|--------|------|
| `RUNFILES_MANIFEST_FILE` | Bazel | 指示 manifest 文件位置，标志当前在 Bazel runfiles 环境中 |
| `RUNFILES_MANIFEST_ONLY` | Bazel（项目配置） | 指示只使用 manifest 策略，禁用目录策略 |
| `CARGO_BIN_EXE_*` | Cargo / Bazel defs.bzl | 指向二进制文件的路径 |
| `CARGO_MANIFEST_DIR` | Cargo | crate 根目录，用于相对路径解析 |
| `BAZEL_PACKAGE` | defs.bzl（编译期） | Bazel 包名称，用于构建 runfiles 路径 |

### 与代码的对应关系

README 中的描述与 `src/lib.rs` 的实现完全对应：

```rust
// cargo_bin 函数（对应 README 描述）
pub fn cargo_bin(name: &str) -> Result<PathBuf, CargoBinError> {
    let env_keys = cargo_bin_env_keys(name);
    for key in &env_keys {
        if let Some(value) = std::env::var_os(key) {
            return resolve_bin_from_env(key, value);  // 解析环境变量
        }
    }
    // ... fallback 到 assert_cmd
}

// find_resource! 宏（对应 README 描述）
macro_rules! find_resource {
    ($resource:expr) => {{
        let resource = std::path::Path::new(&$resource);
        if $crate::runfiles_available() {  // 检查 RUNFILES_MANIFEST_FILE
            // Bazel 路径
        } else {
            // Cargo 路径：CARGO_MANIFEST_DIR 相对
        }
    }};
}
```

## 关键代码路径与文件引用

### 文档中引用的实现文件
- `src/lib.rs` - 包含 `cargo_bin` 函数和 `find_resource!` 宏的实现

### 相关配置文件
- `BUILD.bazel` - 配置 `RUNFILES_MANIFEST_ONLY` 和 `CARGO_BIN_EXE_*` 环境变量
- `defs.bzl` - 定义 `codex_rust_crate` 宏，设置编译期环境变量

### 使用方
- 所有需要定位二进制文件或 fixture 的测试代码，如：
  - `codex-rs/apply-patch/tests/suite/cli.rs`
  - `codex-rs/chatgpt/tests/suite/apply_command_e2e.rs`
  - `codex-rs/exec/tests/suite/*.rs`

## 依赖与外部交互

### Bazel 构建系统
README 中描述的行为依赖于 Bazel 的以下特性：
1. `--enable_runfiles` 和 `--experimental_enable_runfiles` 标志
2. `RUNFILES_MANIFEST_FILE` 环境变量自动设置
3. `rlocationpath` 模板变量

### runfiles crate
文档中提到的功能依赖于 `runfiles` crate：
- `Runfiles::create()` - 解析 manifest 文件
- `rlocation!` 宏 - 将逻辑路径转换为绝对路径

### assert_cmd crate
作为 fallback 机制使用，当环境变量方法失败时尝试使用。

## 风险、边界与改进建议

### 风险

1. **文档与代码不同步**：README 是高层描述，如果 `src/lib.rs` 的实现变化，文档可能过时。
   - 当前状态：文档与代码一致
   - 建议：在代码关键函数上添加 doc comment，引用 README

2. **假设的隐式性**：README 提到 "avoids Windows path length issues"，但没有说明具体限制（260 字符 MAX_PATH）。

3. **缺少示例代码**：纯文本描述，没有代码示例展示如何使用 `cargo_bin` 和 `find_resource!`。

### 边界情况

1. **Manifest 文件缺失**：如果 `RUNFILES_MANIFEST_FILE` 指向的文件不存在，行为未在文档中说明。

2. **路径解析失败**：当 runfiles 解析失败时，错误信息可能不够清晰。

3. **跨 crate 二进制依赖**：README 没有讨论如何定位其他 crate 的二进制文件（通过 `extra_binaries`）。

### 改进建议

1. **添加使用示例**：
   ```markdown
   ## 使用示例

   ### 在测试中定位二进制文件
   ```rust
   use codex_utils_cargo_bin::cargo_bin;
   use std::process::Command;

   let bin_path = cargo_bin("apply_patch")?;
   let output = Command::new(&bin_path).arg("--help").output()?;
   ```

   ### 在测试中定位 fixture
   ```rust
   use codex_utils_cargo_bin::find_resource;

   let fixture_path = find_resource!("tests/fixtures/data.json")?;
   let data = std::fs::read_to_string(&fixture_path)?;
   ```
   ```

2. **添加故障排除部分**：
   ```markdown
   ## 故障排除

   ### "could not locate binary" 错误
   - 确保二进制在 Cargo.toml 的 `[[bin]]` 段声明
   - 对于 Bazel 构建，确保在 `defs.bzl` 的 `binaries` 中列出

   ### "runfile does not exist" 错误
   - 检查 fixture 文件是否在 `tests/**` 目录中
   - 对于 Bazel，确保文件在 `data` 属性中列出
   ```

3. **解释设计权衡**：
   - 为什么选择 manifest 策略（优点）
   - 可能的缺点（如性能开销，需要解析 manifest 文件）

4. **添加架构图**：
   使用 ASCII 图或 mermaid 图展示路径解析流程：
   ```
   cargo_bin("apply_patch")
       ↓
   检查 CARGO_BIN_EXE_apply_patch
       ↓
   RUNFILES_MANIFEST_FILE 存在?
       ├── 是 → runfiles::rlocation → 绝对路径
       └── 否 → 要求绝对路径 → 验证存在性
   ```

5. **链接到 AGENTS.md**：
   在 README 中添加引用到项目级的 `AGENTS.md`，说明测试最佳实践。
