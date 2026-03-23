# codex-rs/exec/BUILD.bazel 研究文档

## 场景与职责

`BUILD.bazel` 是 Bazel 构建系统对 `codex-exec` crate 的构建配置声明文件。它定义了如何将这个 Rust crate 编译成库和二进制文件，以及相关的测试配置。

该文件位于 `codex-rs/exec/` 目录下，与 `Cargo.toml` 共同构成该 crate 的完整构建描述。Cargo 用于 Rust 生态的标准构建，而 Bazel 用于大规模构建和跨平台发布。

## 功能点目的

### 1. 引入构建规则

```bazel
load("//:defs.bzl", "codex_rust_crate")
```

从项目根目录的 `defs.bzl` 加载自定义宏 `codex_rust_crate`，这是项目统一的 Rust crate 构建抽象。

### 2. 声明 crate 构建

```bazel
codex_rust_crate(
    name = "exec",
    crate_name = "codex_exec",
    test_tags = ["no-sandbox"],
)
```

| 参数 | 值 | 说明 |
|------|-----|------|
| `name` | `"exec"` | Bazel 目标名称，也是目录名 |
| `crate_name` | `"codex_exec"` | Rust crate 名称（下划线分隔） |
| `test_tags` | `["no-sandbox"]` | 测试标签，表示测试不在 Bazel sandbox 中运行 |

## 具体技术实现

### 构建流程

`codex_rust_crate` 宏（定义在 `//:defs.bzl`）会展开为以下 Bazel 目标：

1. **库目标 (`rust_library`)**
   - 名称：`exec`
   - crate 名：`codex_exec`
   - 源文件：`src/**/*.rs`（排除二进制入口）

2. **二进制目标 (`rust_binary`)**
   - 名称：`codex-exec`
   - crate 根：`src/main.rs`
   - 依赖库目标

3. **单元测试目标 (`rust_test`)**
   - 名称：`exec-unit-tests`
   - 基于库目标运行单元测试

4. **集成测试目标**
   - 为 `tests/*.rs` 中的每个测试文件生成独立的测试目标
   - 例如：`exec-all-test`、`exec-event_processor_with_json_output-test`

### 测试标签 `"no-sandbox"`

该标签指示 Bazel 在运行测试时不使用沙箱隔离。这对于 `codex-exec` 的测试是必要的，因为：

- 测试本身需要测试沙箱功能（Landlock/Seatbelt）
- 沙箱中运行沙箱测试会导致嵌套沙箱问题
- 某些测试需要访问真实文件系统

## 关键代码路径与文件引用

### 依赖文件

| 文件 | 关系 | 说明 |
|------|------|------|
| `//:defs.bzl` | 加载 | 自定义 Rust crate 构建宏 |
| `Cargo.toml` | 并行 | Cargo 构建配置，Bazel 通过 `crate_name` 与之对应 |
| `src/lib.rs` | 编译 | 库入口 |
| `src/main.rs` | 编译 | 二进制入口 |

### 生成的目标

```
//codex-rs/exec:exec                  # 库
//codex-rs/exec:codex-exec            # 二进制
//codex-rs/exec:exec-unit-tests       # 单元测试
//codex-rs/exec:exec-all-test         # 集成测试 (tests/all.rs)
```

## 依赖与外部交互

### Bazel 工作区依赖

- `@crates//:defs.bzl` - 外部 crate 依赖解析
- `@rules_rust//rust:defs.bzl` - Rust 规则

### Cargo.toml 对应关系

```toml
# Cargo.toml
[package]
name = "codex-exec"          # -> crate_name = "codex_exec" (下划线替换)

[[bin]]
name = "codex-exec"          # -> 二进制目标名称

[lib]
name = "codex_exec"          # -> crate_name
```

## 风险、边界与改进建议

### 风险

1. **名称不一致风险**
   - `Cargo.toml` 使用 kebab-case (`codex-exec`)
   - `BUILD.bazel` 使用下划线 (`codex_exec`)
   - 手动维护时需确保两者同步

2. **测试标签扩散**
   - `"no-sandbox"` 标签意味着测试在宿主机上直接运行
   - 测试代码中的文件操作可能影响宿主机环境

### 边界

- 该文件仅声明构建配置，不包含编译选项细节
- 详细的编译标志、依赖版本在 `MODULE.bazel` 和 `Cargo.lock` 中管理
- 跨平台构建逻辑在 `defs.bzl` 中统一处理

### 改进建议

1. **自动化同步检查**
   - 添加 CI 检查确保 `Cargo.toml` 和 `BUILD.bazel` 的 crate 名称一致

2. **文档化测试标签**
   - 在文件中添加注释说明 `"no-sandbox"` 的必要性

3. **考虑细粒度标签**
   - 如果部分测试可以在沙箱中运行，考虑拆分测试套件
