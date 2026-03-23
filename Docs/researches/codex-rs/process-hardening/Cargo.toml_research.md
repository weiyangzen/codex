# Cargo.toml 研究文档

## 场景与职责

该文件是 `codex-process-hardening` crate 的 Cargo 包配置文件，定义了包的元数据、库配置、依赖关系和代码检查规则。它是 Rust 工具链（cargo）识别和构建该 crate 的核心配置文件。

## 功能点目的

1. **包标识**：定义 crate 的名称、版本、版本控制和许可证信息
2. **库配置**：指定库的名称和入口文件路径
3. **依赖管理**：声明运行时依赖（`libc`）和开发依赖（`pretty_assertions`）
4. **代码质量**：继承工作空间的 lint 规则，确保代码风格一致性

## 具体技术实现

### 包元数据配置

```toml
[package]
name = "codex-process-hardening"
version.workspace = true      # 继承工作空间版本（0.0.0）
edition.workspace = true      # 继承工作空间 Rust 版本（2024）
license.workspace = true      # 继承工作空间许可证（Apache-2.0）
```

### 库配置

```toml
[lib]
name = "codex_process_hardening"  # Rust 库名称（下划线格式）
path = "src/lib.rs"               # 库入口文件
```

### Lint 规则配置

```toml
[lints]
workspace = true  # 继承 codex-rs/Cargo.toml 中定义的 clippy 规则
```

继承的 clippy 规则包括：
- `expect_used = "deny"` - 禁止使用 `expect()`
- `unwrap_used = "deny"` - 禁止使用 `unwrap()`
- `uninlined_format_args = "deny"` - 要求内联 format 参数
- 以及 30+ 其他规则，详见工作空间配置

### 依赖配置

```toml
[dependencies]
libc = { workspace = true }  # 系统调用接口

[dev-dependencies]
pretty_assertions = { workspace = true }  # 测试断言美化
```

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/process-hardening/Cargo.toml` - 本配置文件

### 工作空间配置引用
- `codex-rs/Cargo.toml` - 定义工作空间成员和共享依赖
  - `[workspace.dependencies]` 中定义 `libc = "0.2.182"`
  - `[workspace.dependencies]` 中定义 `pretty_assertions = "1.4.1"`
  - `[workspace.lints.clippy]` 定义共享的代码检查规则

### 源码文件
- `codex-rs/process-hardening/src/lib.rs` - 库实现

### 构建配置
- `codex-rs/process-hardening/BUILD.bazel` - Bazel 构建定义

## 依赖与外部交互

### 运行时依赖

| 依赖 | 版本 | 用途 |
|------|------|------|
| `libc` | 0.2.182 | 提供 Unix 系统调用接口（prctl, ptrace, setrlimit 等） |

### 开发依赖

| 依赖 | 版本 | 用途 |
|------|------|------|
| `pretty_assertions` | 1.4.1 | 测试失败时提供美观的 diff 输出 |

### 依赖使用详情

`libc` crate 在 `src/lib.rs` 中的使用：
- `libc::prctl(libc::PR_SET_DUMPABLE, 0, 0, 0, 0)` - Linux 上禁用进程可 dump 性
- `libc::ptrace(libc::PT_DENY_ATTACH, ...)` - macOS 上禁止调试器附加
- `libc::setrlimit(libc::RLIMIT_CORE, &rlim)` - 设置核心文件大小限制为 0
- `libc::rlimit` 结构体 - 资源限制配置

### 被依赖方

该 crate 作为工作空间依赖被引用：
- `codex-rs/responses-api-proxy/Cargo.toml` - 使用 `codex-process-hardening = { workspace = true }`

## 风险、边界与改进建议

### 风险

1. **单一依赖风险**：该 crate 仅依赖 `libc`，但 `libc` 是底层系统接口，版本升级可能引入破坏性变更

2. **平台兼容性**：`libc` 在不同平台上的 API 可用性不同，需要仔细处理条件编译

3. **unsafe 代码风险**：通过 `libc` 进行的系统调用都是 `unsafe` 操作，需要确保正确的错误处理

### 边界

1. **无特性标志**：该 crate 没有定义任何 `[features]`，无法通过特性开关控制功能

2. **无构建脚本**：缺少 `build.rs`，无法执行自定义构建逻辑（如检测平台特性）

3. **无基准测试配置**：缺少 `[[bench]]` 配置，无法进行性能基准测试

4. **无示例**：缺少 `[[example]]` 配置，没有提供使用示例

### 改进建议

1. **添加特性标志**：考虑添加特性标志以允许选择性启用/禁用某些加固功能
   ```toml
   [features]
   default = ["core-dump", "ptrace", "env-sanitize"]
   core-dump = []
   ptrace = []
   env-sanitize = []
   ```

2. **添加文档示例**：在 `Cargo.toml` 中添加示例配置
   ```toml
   [[example]]
   name = "basic_usage"
   path = "examples/basic_usage.rs"
   ```

3. **版本管理**：目前使用工作空间版本（0.0.0），如果该 crate 需要独立发布，应考虑使用独立版本号

4. **添加更多元数据**：考虑添加以下字段：
   - `description` - 包描述
   - `repository` - 代码仓库 URL
   - `keywords` - 关键词标签
   - `categories` - crates.io 分类

5. **安全审计**：考虑添加 `cargo-audit` 到 CI 流程，定期检查依赖的安全漏洞
