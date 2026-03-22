# codex-rs/utils/cargo-bin 深度研究文档

## 1. 场景与职责

### 1.1 核心定位

`codex-utils-cargo-bin` 是一个底层工具 crate，专门解决 **Cargo 与 Bazel 双构建系统共存** 下的测试二进制文件定位问题。它是 Codex CLI 项目测试基础设施的关键组成部分。

### 1.2 解决的问题场景

在大型 Rust 项目中，测试代码经常需要：
1. **启动其他二进制文件**：如测试 `codex-exec` 沙盒功能时需要启动 `codex-exec` 二进制
2. **访问测试资源文件**：如加载 fixtures、schema 文件、模型配置等
3. **跨构建系统兼容**：同一份测试代码需要在 Cargo 和 Bazel 两种构建系统下都能正常运行

### 1.3 使用场景分布

| 使用场景 | 调用方 | 功能 |
|---------|--------|------|
| 启动被测二进制 | `exec/tests/suite/sandbox.rs` | 启动 `codex-exec` 进行沙盒测试 |
| 启动 App Server | `app-server/tests/common/mcp_process.rs` | 启动 `codex-app-server` 进行集成测试 |
| 启动 MCP Server | `mcp-server/tests/common/mcp_process.rs` | 启动 `codex-mcp-server` 进行协议测试 |
| 启动 Exec Server | `exec-server/tests/common/exec_server.rs` | 启动 `codex-exec-server` 进行测试 |
| 定位 execve wrapper | `core/tests/common/zsh_fork.rs` | 定位 `codex-execve-wrapper` 二进制 |
| 加载测试 fixtures | `core/tests/common/test_codex.rs` | 加载 `models.json` 等配置文件 |
| 获取仓库根目录 | `core/tests/common/zsh_fork.rs` | 通过 `repo_root()` 定位 DotSlash 文件 |

---

## 2. 功能点目的

### 2.1 `cargo_bin(name: &str)` - 二进制文件定位

**目的**：在测试运行时找到已构建的二进制文件的绝对路径。

**关键设计决策**：
- 优先读取 `CARGO_BIN_EXE_*` 环境变量（Cargo 和 Bazel 都会设置）
- 处理 Bazel 的 runfiles 路径解析（通过 `rlocation`）
- 处理 Cargo 的绝对路径直接返回
- 支持名称中连字符 `-` 到下划线 `_` 的自动转换（Cargo 的命名规则）

### 2.2 `find_resource!` 宏 - 测试资源定位

**目的**：在测试中定位 fixtures、配置文件等资源。

**关键设计决策**：
- 编译时捕获 `BAZEL_PACKAGE`（Bazel 构建时注入）
- 运行时检测 `RUNFILES_MANIFEST_ONLY` 环境变量判断构建系统
- Bazel 模式下使用 `rlocation` 解析 runfile 路径
- Cargo 模式下使用 `CARGO_MANIFEST_DIR` 拼接相对路径

### 2.3 `repo_root()` - 仓库根目录定位

**目的**：获取项目仓库的根目录路径。

**实现机制**：
- 通过 `repo_root.marker` 空文件作为锚点
- 从 marker 文件位置向上回溯 4 层目录到达仓库根
- 同时支持 Bazel runfiles 和 Cargo 直接运行两种模式

### 2.4 `runfiles_available()` - 构建系统检测

**目的**：检测当前是否在 Bazel runfiles 环境下运行。

**检测依据**：检查 `RUNFILES_MANIFEST_ONLY` 环境变量是否存在（Bazel 设置）。

---

## 3. 具体技术实现

### 3.1 关键数据结构

```rust
/// 错误类型定义
#[derive(Debug, thiserror::Error)]
pub enum CargoBinError {
    #[error("failed to read current exe")]
    CurrentExe { source: std::io::Error },
    
    #[error("failed to read current directory")]
    CurrentDir { source: std::io::Error },
    
    #[error("CARGO_BIN_EXE env var {key} resolved to {path:?}, but it does not exist")]
    ResolvedPathDoesNotExist { key: String, path: PathBuf },
    
    #[error("could not locate binary {name:?}; tried env vars {env_keys:?}; {fallback}")]
    NotFound { name: String, env_keys: Vec<String>, fallback: String },
}
```

### 3.2 核心流程：`cargo_bin()` 函数

```
输入: binary_name (如 "codex-exec")
│
├─ 步骤1: 生成候选环境变量名
│   ├─ CARGO_BIN_EXE_codex-exec
│   └─ CARGO_BIN_EXE_codex_exec (下划线版本)
│
├─ 步骤2: 遍历检查环境变量
│   └─ 如果存在 → 调用 resolve_bin_from_env()
│
├─ 步骤3: 环境变量未设置时的 fallback
│   └─ 使用 assert_cmd::Command::cargo_bin() 尝试定位
│
└─ 步骤4: 验证路径存在性并返回
```

**`resolve_bin_from_env()` 详细逻辑**：

```rust
fn resolve_bin_from_env(key: &str, value: OsString) -> Result<PathBuf, CargoBinError> {
    let raw = PathBuf::from(&value);
    
    if runfiles_available() {
        // Bazel 模式：使用 runfiles crate 解析 rlocationpath
        let runfiles = runfiles::Runfiles::create()?;
        if let Some(resolved) = runfiles::rlocation!(runfiles, &raw) {
            if resolved.exists() {
                return Ok(resolved);
            }
        }
    } else if raw.is_absolute() && raw.exists() {
        // Cargo 模式：直接使用绝对路径
        return Ok(raw);
    }
    
    Err(CargoBinError::ResolvedPathDoesNotExist { ... })
}
```

### 3.3 `find_resource!` 宏实现

```rust
#[macro_export]
macro_rules! find_resource {
    ($resource:expr) => {{
        let resource = std::path::Path::new(&$resource);
        if $crate::runfiles_available() {
            // Bazel 模式：使用编译时注入的 BAZEL_PACKAGE
            $crate::resolve_bazel_runfile(option_env!("BAZEL_PACKAGE"), resource)
        } else {
            // Cargo 模式：使用编译时的 CARGO_MANIFEST_DIR
            let manifest_dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
            Ok(manifest_dir.join(resource))
        }
    }};
}
```

**Bazel 路径构造规则**：
```rust
let runfile_path = match bazel_package {
    Some(bazel_package) => PathBuf::from("_main").join(bazel_package).join(resource),
    None => /* 错误：BAZEL_PACKAGE 未设置 */
};
```

路径格式：`_main/<bazel_package>/<resource>`
- `_main` 是 Bazel 仓库的 runfiles 前缀
- `bazel_package` 如 `codex-rs/core/tests/common`

### 3.4 Runfile 路径规范化

```rust
fn normalize_runfile_path(path: &Path) -> PathBuf {
    // 处理 . 和 .. 路径组件
    // 保持非 Normal 组件（如 Prefix、RootDir）
    // 对 Normal 组件执行 .. 的弹出操作
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 本 crate 文件结构

| 文件 | 用途 |
|------|------|
| `src/lib.rs` | 主实现，包含所有公共 API |
| `Cargo.toml` | 依赖声明：assert_cmd, runfiles, thiserror |
| `BUILD.bazel` | Bazel 构建规则，导出 repo_root.marker |
| `repo_root.marker` | 空文件，作为仓库根目录定位的锚点 |
| `README.md` | 设计文档和背景链接 |

### 4.2 关键代码行引用

**`cargo_bin()` 主函数**：`src/lib.rs:39-69`
- 环境变量名生成：`src/lib.rs:71-82`
- Bazel runfiles 检测：`src/lib.rs:84-86`
- 环境变量解析：`src/lib.rs:88-107`

**`find_resource!` 宏**：`src/lib.rs:118-133`
- Bazel runfile 解析：`src/lib.rs:135-161`
- Cargo 资源解析：`src/lib.rs:163-166`

**`repo_root()` 实现**：`src/lib.rs:168-202`
- 使用 `CODEX_REPO_ROOT_MARKER` 编译时环境变量
- 从 marker 文件向上回溯 4 层：`src/lib.rs:190-200`

### 4.3 Bazel 集成配置

**`defs.bzl` 中的关键配置**（`codex_rust_crate` 宏）：

```bzl
# 编译时注入 BAZEL_PACKAGE
rustc_env = {
    "BAZEL_PACKAGE": native.package_name(),
}

# 为每个二进制生成 CARGO_BIN_EXE_* 环境变量
cargo_env["CARGO_BIN_EXE_" + binary] = "$(rlocationpath :%s)" % binary

# workspace_root_test 规则使用 repo_root.marker
workspace_root_marker = "//codex-rs/utils/cargo-bin:repo_root.marker"
```

**`BUILD.bazel` 中的特殊配置**：

```bzl
codex_rust_crate(
    name = "cargo-bin",
    crate_name = "codex_utils_cargo_bin",
    compile_data = ["repo_root.marker"],
    lib_data_extra = ["repo_root.marker"],
    test_data_extra = ["repo_root.marker"],
    rustc_env = {
        "CODEX_REPO_ROOT_MARKER": "$(rlocationpath :repo_root.marker)",
    },
)
```

---

## 5. 依赖与外部交互

### 5.1 外部依赖

| 依赖 | 版本 | 用途 |
|------|------|------|
| `assert_cmd` | workspace | Fallback 二进制定位 |
| `runfiles` | git (rules_rust fork) | Bazel runfiles 解析 |
| `thiserror` | workspace | 错误类型定义 |

### 5.2 环境变量交互

**读取的环境变量**：

| 变量名 | 设置方 | 用途 |
|--------|--------|------|
| `CARGO_BIN_EXE_<name>` | Cargo/Bazel | 二进制文件路径 |
| `RUNFILES_MANIFEST_ONLY` | Bazel | 检测 Bazel runfiles 模式 |
| `RUNFILES_MANIFEST_FILE` | Bazel | runfiles 清单文件路径（由 runfiles crate 使用） |

**编译时环境变量**（由 Bazel 注入）：

| 变量名 | 注入位置 | 用途 |
|--------|----------|------|
| `BAZEL_PACKAGE` | `defs.bzl:149` | 当前 Bazel 包名 |
| `CODEX_REPO_ROOT_MARKER` | `BUILD.bazel:15` | repo_root.marker 的 rlocationpath |

### 5.3 调用方 crate 列表

根据 `Cargo.toml` 依赖声明，以下 crate 使用 `codex-utils-cargo-bin`：

- `core_test_support` (`codex-rs/core/tests/common`)
- `app_test_support` (`codex-rs/app-server/tests/common`)
- `mcp_test_support` (`codex-rs/mcp-server/tests/common`)
- `chatgpt` 测试
- `apply-patch` 测试
- `cli` 测试
- `codex-client` 测试
- `stdio-to-uds` 测试
- `rmcp-client` 测试
- `exec` 测试
- `tui_app_server` 测试
- `tui` 测试
- `core` 测试
- `app-server-protocol` 测试
- `exec-server` 测试

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 路径回溯硬编码风险

```rust
// src/lib.rs:190-200
for _ in 0..4 {
    root = root.parent().ok_or_else(|| ...)?;
}
```

**风险**：`repo_root()` 假设 marker 文件位于仓库根下 4 层目录（`codex-rs/utils/cargo-bin/repo_root.marker`）。如果目录结构变化，此逻辑将失效。

**缓解**：目录结构稳定，且 marker 文件位置由 Bazel 规则严格控制。

#### 6.1.2 Runfiles 模式检测依赖特定环境变量

```rust
const RUNFILES_MANIFEST_ONLY_ENV: &str = "RUNFILES_MANIFEST_ONLY";
```

**风险**：如果 Bazel 改变环境变量命名或行为，检测将失效。

**缓解**：这是 Bazel 的标准做法，且 rules_rust 也依赖此变量。

#### 6.1.3 `assert_cmd` Fallback 的潜在问题

```rust
match assert_cmd::Command::cargo_bin(name) {
    Ok(cmd) => { ... }
    Err(err) => Err(CargoBinError::NotFound { ... }),
}
```

**风险**：`assert_cmd` 在 Bazel 环境下可能返回相对路径，代码中需要转换为绝对路径。

**缓解**：代码已处理相对路径转换（`src/lib.rs:49-53`）。

### 6.2 边界情况

#### 6.2.1 二进制名称中的连字符处理

Cargo 在环境变量名中将连字符替换为下划线。crate 自动处理：

```rust
let underscore_name = name.replace('-', "_");
if underscore_name != name {
    keys.push(format!("CARGO_BIN_EXE_{underscore_name}"));
}
```

#### 6.2.2 Runfile 路径规范化

`normalize_runfile_path` 处理 `..` 和 `.` 组件，但保留非 Normal 组件（如 Windows 的 Prefix）。

### 6.3 改进建议

#### 6.3.1 增加目录结构变更检测

为 `repo_root()` 增加验证逻辑：

```rust
pub fn repo_root() -> io::Result<PathBuf> {
    let root = /* 现有逻辑 */;
    // 验证：检查根目录是否包含预期的子目录或文件
    if !root.join("codex-rs").is_dir() || !root.join("MODULE.bazel").is_file() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            "resolved path does not appear to be the repository root",
        ));
    }
    Ok(root)
}
```

#### 6.3.2 增加调试日志

在关键路径增加 `tracing` 或 `log` 输出，便于排查路径解析问题：

```rust
tracing::debug!(?env_key, ?resolved_path, "resolved binary path");
```

#### 6.3.3 统一错误类型

当前 `find_resource!` 返回 `std::io::Result`，而 `cargo_bin()` 返回自定义 `Result`。考虑统一错误类型或提供转换方法。

#### 6.3.4 文档改进

- 增加架构图说明 Cargo vs Bazel 路径解析流程
- 增加故障排查指南（如 "Binary not found" 错误的常见原因）

#### 6.3.5 测试覆盖

当前 crate 本身没有单元测试。建议增加：

- `cargo_bin_env_keys()` 的单元测试
- `normalize_runfile_path()` 的边界测试
- Mock 环境下的 `runfiles_available()` 测试

### 6.4 相关背景链接

- Bazel Runfiles 文档：https://bazel.build/docs/runfiles
- Runfiles Manifest：https://bazel.build/docs/runfiles#runfiles-manifest
- rules_rust runfiles crate：https://github.com/dzbarsky/rules_rust

---

## 7. 总结

`codex-utils-cargo-bin` 是 Codex CLI 项目测试基础设施的核心组件，通过抽象 Cargo 和 Bazel 的路径差异，实现了测试代码的构建系统无关性。其设计简洁，通过环境变量检测和条件编译实现了双构建系统的透明支持。

关键成功因素：
1. **单一职责**：专注于路径解析，不做其他事情
2. **最小依赖**：仅依赖 `assert_cmd`、`runfiles` 和 `thiserror`
3. **透明 fallback**：优先使用原生机制（`CARGO_BIN_EXE_*`），仅在必要时使用 runfiles
4. **宏与函数配合**：`find_resource!` 宏捕获编译时信息，函数处理运行时逻辑
